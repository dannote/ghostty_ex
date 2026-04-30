const beam = @import("beam");
const root = @import("root");
const std = @import("std");
const builtin = @import("builtin");
const g = @cImport(@cInclude("ghostty/vt.h"));
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("poll.h");
    @cInclude("sys/ioctl.h");
    @cInclude("termios.h");
    @cInclude("unistd.h");
});

const TerminalData = struct {
    terminal: g.GhosttyTerminal,
    owner_pid: ?beam.pid = null,
};

pub const TerminalResource = beam.Resource(TerminalData, root, .{
    .Callbacks = TerminalCallbacks,
});

pub const TerminalCallbacks = struct {
    pub fn dtor(data: *TerminalData) void {
        g.ghostty_terminal_free(data.terminal);
    }
};

const TtyData = struct {
    fd: c_int,
    write_fd: c_int,
    original: c.struct_termios,
    owner_pid: beam.pid,
    closed: std.atomic.Value(bool),
    thread: ?std.Thread,
};

pub const TtyResource = beam.Resource(TtyData, root, .{
    .Callbacks = TtyCallbacks,
});

pub const TtyCallbacks = struct {
    pub fn dtor(data: *TtyData) void {
        tty_close(data);
    }
};

fn get_errno() c_int {
    if (comptime builtin.os.tag == .macos)
        return c.__error().*
    else
        return c.__errno_location().*;
}

fn is_would_block(errno: c_int) bool {
    return errno == c.EAGAIN or errno == c.EWOULDBLOCK;
}

fn tty_wait_for_input(fd: c_int, timeout_ms: c_int) c_short {
    var pfd: c.struct_pollfd = .{
        .fd = fd,
        .events = c.POLLIN | c.POLLHUP | c.POLLERR,
        .revents = 0,
    };

    while (true) {
        const rc = c.poll(&pfd, 1, timeout_ms);

        if (rc > 0) return pfd.revents;
        if (rc == 0) return 0;
        if (get_errno() == c.EINTR) continue;
        return 0;
    }
}

fn tty_close(data: *TtyData) void {
    if (data.closed.swap(true, .acq_rel)) return;

    if (data.thread) |thread| {
        thread.join();
        data.thread = null;
    }

    _ = c.tcsetattr(data.fd, c.TCSANOW, &data.original);
    _ = c.close(data.fd);
    if (data.write_fd != data.fd) _ = c.close(data.write_fd);
}

fn tty_window_size(fd: c_int) ?c.struct_winsize {
    var size: c.struct_winsize = undefined;
    if (c.ioctl(fd, c.TIOCGWINSZ, &size) != 0) return null;
    if (size.ws_col == 0 or size.ws_row == 0) return null;
    return size;
}

fn tty_send_resize(owner: beam.pid, size: c.struct_winsize) void {
    const env = beam.alloc_env();
    beam.send(
        owner,
        .{ .tty_resize, @as(u16, size.ws_col), @as(u16, size.ws_row) },
        .{ .env = env },
    ) catch {};
    beam.free_env(env);
}

fn tty_reader_loop(fd: c_int, owner: beam.pid, closed: *std.atomic.Value(bool)) void {
    var buf: [4096]u8 = undefined;
    var last_size = tty_window_size(fd);

    const ready_env = beam.alloc_env();
    beam.send(owner, .{.tty_ready}, .{ .env = ready_env }) catch {};
    beam.free_env(ready_env);

    while (!closed.load(.acquire)) {
        const revents = tty_wait_for_input(fd, 100);

        if (tty_window_size(fd)) |current_size| {
            if (last_size == null or current_size.ws_col != last_size.?.ws_col or current_size.ws_row != last_size.?.ws_row) {
                last_size = current_size;
                tty_send_resize(owner, current_size);
            }
        }

        if (revents == 0) continue;

        if (revents & c.POLLIN != 0) {
            while (!closed.load(.acquire)) {
                const n = c.read(fd, &buf, buf.len);

                if (n > 0) {
                    const slice = buf[0..@intCast(n)];
                    const env = beam.alloc_env();
                    beam.send(owner, .{ .tty_data, beam.make(slice, .{ .env = env }) }, .{ .env = env }) catch {};
                    beam.free_env(env);
                    continue;
                }

                if (n < 0) {
                    const errno = get_errno();
                    if (errno == c.EINTR) continue;
                    if (is_would_block(errno)) break;
                    return;
                }

                const env = beam.alloc_env();
                beam.send(owner, .{.tty_eof}, .{ .env = env }) catch {};
                beam.free_env(env);
                return;
            }
        }

        if (revents & (c.POLLHUP | c.POLLERR) != 0 and revents & c.POLLIN == 0) {
            const env = beam.alloc_env();
            beam.send(owner, .{.tty_eof}, .{ .env = env }) catch {};
            beam.free_env(env);
            return;
        }
    }
}

fn tty_make_raw(original: c.struct_termios, signals: bool) c.struct_termios {
    var raw = original;

    c.cfmakeraw(&raw);
    if (signals) raw.c_lflag |= c.ISIG;
    raw.c_cc[c.VMIN] = 1;
    raw.c_cc[c.VTIME] = 0;

    return raw;
}

pub fn nif_tty_open(owner: beam.pid, signals: bool) !TtyResource {
    const fd = c.dup(c.STDIN_FILENO);
    if (fd < 0) return error.tty_open_failed;

    const write_fd = c.dup(c.STDOUT_FILENO);
    if (write_fd < 0) {
        _ = c.close(fd);
        return error.tty_open_failed;
    }

    const flags = c.fcntl(fd, c.F_GETFL);
    if (flags >= 0) _ = c.fcntl(fd, c.F_SETFL, flags | @as(c_int, c.O_NONBLOCK));

    // SAFETY: initialized by tcgetattr below before it is read.
    var original: c.struct_termios = undefined;
    if (c.tcgetattr(fd, &original) != 0) {
        _ = c.close(fd);
        _ = c.close(write_fd);
        return error.tcgetattr_failed;
    }

    var raw = tty_make_raw(original, signals);
    if (c.tcsetattr(fd, c.TCSANOW, &raw) != 0) {
        _ = c.close(fd);
        _ = c.close(write_fd);
        return error.tcsetattr_failed;
    }

    const res = try TtyResource.create(.{
        .fd = fd,
        .write_fd = write_fd,
        .original = original,
        .owner_pid = owner,
        .closed = std.atomic.Value(bool).init(false),
        .thread = null,
    }, .{});

    const tty = res.__payload;
    tty.thread = std.Thread.spawn(.{}, tty_reader_loop, .{ fd, owner, &tty.closed }) catch
        return error.thread_spawn_failed;

    return res;
}

pub fn nif_tty_write(res: TtyResource, data: []const u8) void {
    const tty = res.__payload;
    if (tty.closed.load(.acquire)) return;

    var off: usize = 0;
    while (off < data.len and !tty.closed.load(.acquire)) {
        const n = c.write(tty.write_fd, data.ptr + off, data.len - off);

        if (n > 0) {
            off += @intCast(n);
            continue;
        }

        if (n < 0 and get_errno() == c.EINTR) continue;
        break;
    }
}

pub fn nif_tty_close(res: TtyResource) void {
    tty_close(res.__payload);
}

fn on_write_pty(terminal: g.GhosttyTerminal, userdata: ?*anyopaque, data_ptr: [*c]const u8, len: usize) callconv(.c) void {
    _ = terminal;
    const td: *TerminalData = @ptrCast(@alignCast(userdata orelse return));
    const pid = td.owner_pid orelse return;
    const slice = if (len > 0) data_ptr[0..len] else &[_]u8{};
    const env = beam.alloc_env();
    beam.send(pid, .{ .pty_write, beam.make(slice, .{ .env = env }) }, .{ .env = env }) catch {};
    beam.free_env(env);
}

fn on_bell(terminal: g.GhosttyTerminal, userdata: ?*anyopaque) callconv(.c) void {
    _ = terminal;
    const td: *TerminalData = @ptrCast(@alignCast(userdata orelse return));
    const pid = td.owner_pid orelse return;
    const env = beam.alloc_env();
    beam.send(pid, .bell, .{ .env = env }) catch {};
    beam.free_env(env);
}

fn on_title_changed(terminal: g.GhosttyTerminal, userdata: ?*anyopaque) callconv(.c) void {
    _ = terminal;
    const td: *TerminalData = @ptrCast(@alignCast(userdata orelse return));
    const pid = td.owner_pid orelse return;
    const env = beam.alloc_env();
    beam.send(pid, .title_changed, .{ .env = env }) catch {};
    beam.free_env(env);
}

pub fn nif_new(cols: u16, rows: u16, max_scrollback: u32) !TerminalResource {
    var terminal: g.GhosttyTerminal = undefined;
    const result = g.ghostty_terminal_new(null, &terminal, .{
        .cols = cols,
        .rows = rows,
        .max_scrollback = max_scrollback,
    });
    if (result != g.GHOSTTY_SUCCESS) return error.terminal_creation_failed;
    return TerminalResource.create(.{ .terminal = terminal }, .{});
}

pub fn nif_set_effect_pid(res: TerminalResource, pid: beam.pid) void {
    var data = res.unpack();
    data.owner_pid = pid;
    res.update(data);

    const t = data.terminal;
    const userdata_ptr: *anyopaque = @ptrCast(res.__payload);

    _ = g.ghostty_terminal_set(t, g.GHOSTTY_TERMINAL_OPT_USERDATA, userdata_ptr);
    _ = g.ghostty_terminal_set(t, g.GHOSTTY_TERMINAL_OPT_WRITE_PTY, @ptrCast(&on_write_pty));
    _ = g.ghostty_terminal_set(t, g.GHOSTTY_TERMINAL_OPT_BELL, @ptrCast(&on_bell));
    _ = g.ghostty_terminal_set(t, g.GHOSTTY_TERMINAL_OPT_TITLE_CHANGED, @ptrCast(&on_title_changed));
}

pub fn nif_vt_write(res: TerminalResource, data: []const u8) void {
    g.ghostty_terminal_vt_write(res.unpack().terminal, data.ptr, data.len);
}

pub fn nif_resize(res: TerminalResource, cols: u16, rows: u16) void {
    _ = g.ghostty_terminal_resize(res.unpack().terminal, cols, rows, 0, 0);
}

pub fn nif_reset(res: TerminalResource) void {
    g.ghostty_terminal_reset(res.unpack().terminal);
}

pub fn nif_scroll(res: TerminalResource, delta: i32) void {
    g.ghostty_terminal_scroll_viewport(res.unpack().terminal, .{
        .tag = g.GHOSTTY_SCROLL_VIEWPORT_DELTA,
        .value = .{ .delta = @intCast(delta) },
    });
}

pub fn nif_get_cursor(res: TerminalResource) !beam.term {
    const t = res.unpack().terminal;
    var col: u16 = 0;
    var row: u16 = 0;
    _ = g.ghostty_terminal_get(t, g.GHOSTTY_TERMINAL_DATA_CURSOR_X, &col);
    _ = g.ghostty_terminal_get(t, g.GHOSTTY_TERMINAL_DATA_CURSOR_Y, &row);
    return beam.make(.{ col, row }, .{});
}

pub fn nif_snapshot(res: TerminalResource, format_str: []const u8) !beam.term {
    const t = res.unpack().terminal;

    const emit: c_uint = if (eql(format_str, "plain"))
        @intCast(g.GHOSTTY_FORMATTER_FORMAT_PLAIN)
    else if (eql(format_str, "html"))
        @intCast(g.GHOSTTY_FORMATTER_FORMAT_HTML)
    else if (eql(format_str, "vt"))
        @intCast(g.GHOSTTY_FORMATTER_FORMAT_VT)
    else
        return error.badarg;

    var opts: g.GhosttyFormatterTerminalOptions = std.mem.zeroes(g.GhosttyFormatterTerminalOptions);
    opts.size = @sizeOf(g.GhosttyFormatterTerminalOptions);
    opts.emit = emit;
    opts.trim = true;

    var fmtr: g.GhosttyFormatter = undefined;
    if (g.ghostty_formatter_terminal_new(null, &fmtr, t, opts) != g.GHOSTTY_SUCCESS)
        return error.formatter_creation_failed;
    defer g.ghostty_formatter_free(fmtr);

    var needed: usize = 0;
    _ = g.ghostty_formatter_format_buf(fmtr, null, 0, &needed);

    const buf = beam.allocator.alloc(u8, needed) catch return error.out_of_memory;
    defer beam.allocator.free(buf);

    var written: usize = 0;
    if (g.ghostty_formatter_format_buf(fmtr, buf.ptr, buf.len, &written) != g.GHOSTTY_SUCCESS)
        return error.format_failed;

    return beam.make(buf[0..written], .{});
}

pub fn nif_encode_key(res: TerminalResource, action: u8, key: u32, mods: u16, utf8: []const u8, unshifted_codepoint: u32) !beam.term {
    const t = res.unpack().terminal;

    var encoder: g.GhosttyKeyEncoder = undefined;
    if (g.ghostty_key_encoder_new(null, &encoder) != g.GHOSTTY_SUCCESS)
        return error.encoder_creation_failed;
    defer g.ghostty_key_encoder_free(encoder);

    g.ghostty_key_encoder_setopt_from_terminal(encoder, t);

    var event: g.GhosttyKeyEvent = undefined;
    if (g.ghostty_key_event_new(null, &event) != g.GHOSTTY_SUCCESS)
        return error.event_creation_failed;
    defer g.ghostty_key_event_free(event);

    g.ghostty_key_event_set_action(event, @intCast(action));
    g.ghostty_key_event_set_key(event, @intCast(key));
    g.ghostty_key_event_set_mods(event, mods);
    if (utf8.len > 0) {
        g.ghostty_key_event_set_utf8(event, @ptrCast(utf8.ptr), utf8.len);
    }
    if (unshifted_codepoint > 0) {
        g.ghostty_key_event_set_unshifted_codepoint(event, unshifted_codepoint);
    }

    var buf: [128]u8 = undefined;
    var written: usize = 0;
    const result = g.ghostty_key_encoder_encode(encoder, event, &buf, buf.len, &written);

    if (result == g.GHOSTTY_SUCCESS) {
        if (written == 0) return beam.make(.none, .{});
        return beam.make(.{ .ok, buf[0..written] }, .{});
    }

    if (result == g.GHOSTTY_OUT_OF_SPACE) {
        const big_buf = beam.allocator.alloc(u8, written) catch return error.out_of_memory;
        defer beam.allocator.free(big_buf);
        var big_written: usize = 0;
        if (g.ghostty_key_encoder_encode(encoder, event, big_buf.ptr, big_buf.len, &big_written) != g.GHOSTTY_SUCCESS)
            return error.encode_failed;
        if (big_written == 0) return beam.make(.none, .{});
        return beam.make(.{ .ok, big_buf[0..big_written] }, .{});
    }

    return error.encode_failed;
}

pub fn nif_encode_mouse(res: TerminalResource, action: u8, button: u8, mods: u16, x: f32, y: f32) !beam.term {
    const t = res.unpack().terminal;

    var encoder: g.GhosttyMouseEncoder = undefined;
    if (g.ghostty_mouse_encoder_new(null, &encoder) != g.GHOSTTY_SUCCESS)
        return error.encoder_creation_failed;
    defer g.ghostty_mouse_encoder_free(encoder);

    g.ghostty_mouse_encoder_setopt_from_terminal(encoder, t);

    const size = g.GhosttyMouseEncoderSize{
        .size = @sizeOf(g.GhosttyMouseEncoderSize),
        .screen_width = 800,
        .screen_height = 600,
        .cell_width = 10,
        .cell_height = 20,
    };
    g.ghostty_mouse_encoder_setopt(encoder, g.GHOSTTY_MOUSE_ENCODER_OPT_SIZE, @ptrCast(&size));

    var event: g.GhosttyMouseEvent = undefined;
    if (g.ghostty_mouse_event_new(null, &event) != g.GHOSTTY_SUCCESS)
        return error.event_creation_failed;
    defer g.ghostty_mouse_event_free(event);

    g.ghostty_mouse_event_set_action(event, @intCast(action));
    if (button > 0) {
        g.ghostty_mouse_event_set_button(event, @intCast(button));
    }
    g.ghostty_mouse_event_set_mods(event, mods);
    g.ghostty_mouse_event_set_position(event, .{ .x = x, .y = y });

    var buf: [128]u8 = undefined;
    var written: usize = 0;
    const result = g.ghostty_mouse_encoder_encode(encoder, event, &buf, buf.len, &written);

    if (result != g.GHOSTTY_SUCCESS) return error.encode_failed;
    if (written == 0) return beam.make(.none, .{});
    return beam.make(.{ .ok, buf[0..written] }, .{});
}

pub fn nif_encode_focus(gained: bool) !beam.term {
    const event: c_uint = if (gained) g.GHOSTTY_FOCUS_GAINED else g.GHOSTTY_FOCUS_LOST;
    var buf: [8]u8 = undefined;
    var written: usize = 0;
    if (g.ghostty_focus_encode(event, &buf, buf.len, &written) != g.GHOSTTY_SUCCESS)
        return error.encode_failed;
    if (written == 0) return beam.make(.none, .{});
    return beam.make(.{ .ok, buf[0..written] }, .{});
}

pub fn nif_render_cells(res: TerminalResource) !beam.term {
    const state = try new_render_state(res.unpack().terminal);
    defer g.ghostty_render_state_free(state);
    return try make_cells_term(state);
}

pub fn nif_render_state(res: TerminalResource) !beam.term {
    const terminal = res.unpack().terminal;
    const state = try new_render_state(terminal);
    defer g.ghostty_render_state_free(state);

    const cells = try make_cells_term(state);
    const cursor = make_cursor_term(state);
    const mouse = make_mouse_modes_term(terminal);
    return beam.make(.{ cells, cursor, mouse }, .{});
}

pub fn nif_mouse_modes(res: TerminalResource) beam.term {
    return make_mouse_modes_term(res.unpack().terminal);
}

fn new_render_state(t: g.GhosttyTerminal) !g.GhosttyRenderState {
    var state: g.GhosttyRenderState = undefined;
    if (g.ghostty_render_state_new(null, &state) != g.GHOSTTY_SUCCESS)
        return error.render_state_failed;
    errdefer g.ghostty_render_state_free(state);

    if (g.ghostty_render_state_update(state, t) != g.GHOSTTY_SUCCESS)
        return error.render_update_failed;

    return state;
}

fn make_cells_term(state: g.GhosttyRenderState) !beam.term {
    var row_iter: g.GhosttyRenderStateRowIterator = undefined;
    if (g.ghostty_render_state_row_iterator_new(null, &row_iter) != g.GHOSTTY_SUCCESS)
        return error.row_iterator_failed;
    defer g.ghostty_render_state_row_iterator_free(row_iter);

    _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, @ptrCast(&row_iter));

    var row_cells: g.GhosttyRenderStateRowCells = undefined;
    if (g.ghostty_render_state_row_cells_new(null, &row_cells) != g.GHOSTTY_SUCCESS)
        return error.row_cells_failed;
    defer g.ghostty_render_state_row_cells_free(row_cells);

    var num_cols: u16 = 0;
    _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_COLS, &num_cols);
    var num_rows: u16 = 0;
    _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_ROWS, &num_rows);

    const rows_list = beam.allocator.alloc(beam.term, num_rows) catch return error.out_of_memory;
    defer beam.allocator.free(rows_list);

    var row_idx: u16 = 0;
    while (g.ghostty_render_state_row_iterator_next(row_iter)) : (row_idx += 1) {
        _ = g.ghostty_render_state_row_get(row_iter, g.GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, @ptrCast(&row_cells));

        const cells_list = beam.allocator.alloc(beam.term, num_cols) catch return error.out_of_memory;
        defer beam.allocator.free(cells_list);

        var col_idx: u16 = 0;
        while (g.ghostty_render_state_row_cells_next(row_cells)) : (col_idx += 1) {
            if (col_idx >= num_cols) break;

            var grapheme_len: u32 = 0;
            _ = g.ghostty_render_state_row_cells_get(row_cells, g.GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &grapheme_len);

            var char_term: beam.term = beam.make("", .{});
            if (grapheme_len > 0) {
                var cp_buf: [16]u32 = undefined;
                const cp_count = @min(grapheme_len, 16);
                _ = g.ghostty_render_state_row_cells_get(row_cells, g.GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, &cp_buf);

                var utf8_buf: [64]u8 = undefined;
                var utf8_len: usize = 0;
                for (cp_buf[0..cp_count]) |cp| {
                    const n = std.unicode.utf8Encode(@intCast(cp), utf8_buf[utf8_len..]) catch break;
                    utf8_len += n;
                }
                char_term = beam.make(utf8_buf[0..utf8_len], .{});
            }

            var fg_term: beam.term = beam.make(.nil, .{});
            var bg_term: beam.term = beam.make(.nil, .{});

            var fg_color: g.GhosttyColorRgb = undefined;
            if (g.ghostty_render_state_row_cells_get(row_cells, g.GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &fg_color) == g.GHOSTTY_SUCCESS) {
                fg_term = beam.make(.{ fg_color.r, fg_color.g, fg_color.b }, .{});
            }

            var bg_color: g.GhosttyColorRgb = undefined;
            if (g.ghostty_render_state_row_cells_get(row_cells, g.GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &bg_color) == g.GHOSTTY_SUCCESS) {
                bg_term = beam.make(.{ bg_color.r, bg_color.g, bg_color.b }, .{});
            }

            var style: g.GhosttyStyle = std.mem.zeroes(g.GhosttyStyle);
            style.size = @sizeOf(g.GhosttyStyle);
            _ = g.ghostty_render_state_row_cells_get(row_cells, g.GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style);

            var flags: u16 = 0;
            if (style.bold) flags |= 1;
            if (style.italic) flags |= 2;
            if (style.faint) flags |= 4;
            if (style.underline != 0) flags |= 8;
            if (style.strikethrough) flags |= 16;
            if (style.inverse) flags |= 32;
            if (style.blink) flags |= 64;
            if (style.overline) flags |= 128;

            cells_list[col_idx] = beam.make(.{ char_term, fg_term, bg_term, flags }, .{});
        }

        if (row_idx < num_rows) {
            rows_list[row_idx] = beam.make(cells_list[0..col_idx], .{});
        }
    }

    return beam.make(rows_list[0..row_idx], .{});
}

fn make_cursor_term(state: g.GhosttyRenderState) beam.term {
    var visible = false;
    _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE, &visible);

    var blinking = false;
    _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_CURSOR_BLINKING, &blinking);

    var has_position = false;
    _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE, &has_position);

    var x: u16 = 0;
    var y: u16 = 0;
    var wide_tail = false;
    if (has_position) {
        _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X, &x);
        _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y, &y);
        _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL, &wide_tail);
    }

    var visual_style: c_uint = g.GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK;
    _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE, &visual_style);

    const style_term = switch (visual_style) {
        g.GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR => beam.make(.bar, .{}),
        g.GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE => beam.make(.underline, .{}),
        g.GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW => beam.make(.block_hollow, .{}),
        else => beam.make(.block, .{}),
    };

    var color_has_value = false;
    _ = g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_COLOR_CURSOR_HAS_VALUE, &color_has_value);

    var color_term: beam.term = beam.make(.nil, .{});
    if (color_has_value) {
        var color: g.GhosttyColorRgb = undefined;
        if (g.ghostty_render_state_get(state, g.GHOSTTY_RENDER_STATE_DATA_COLOR_CURSOR, &color) == g.GHOSTTY_SUCCESS) {
            color_term = beam.make(.{ color.r, color.g, color.b }, .{});
        }
    }

    return beam.make(.{ has_position, x, y, visible, blinking, style_term, wide_tail, color_term }, .{});
}

fn make_mouse_modes_term(terminal: g.GhosttyTerminal) beam.term {
    var tracking = false;
    _ = g.ghostty_terminal_get(terminal, g.GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, &tracking);

    var x10 = false;
    _ = g.ghostty_terminal_mode_get(terminal, dec_mode(9), &x10);

    var normal = false;
    _ = g.ghostty_terminal_mode_get(terminal, dec_mode(1000), &normal);

    var button = false;
    _ = g.ghostty_terminal_mode_get(terminal, dec_mode(1002), &button);

    var any = false;
    _ = g.ghostty_terminal_mode_get(terminal, dec_mode(1003), &any);

    var sgr = false;
    _ = g.ghostty_terminal_mode_get(terminal, dec_mode(1006), &sgr);

    return beam.make(.{ tracking, x10, normal, button, any, sgr }, .{});
}

fn dec_mode(value: u16) g.GhosttyMode {
    return g.ghostty_mode_new(value, false);
}

pub fn nif_scrollbar(res: TerminalResource) beam.term {
    const t = res.unpack().terminal;
    var scrollbar: g.GhosttyTerminalScrollbar = undefined;
    _ = g.ghostty_terminal_get(t, g.GHOSTTY_TERMINAL_DATA_SCROLLBAR, &scrollbar);
    return beam.make(.{ scrollbar.total, scrollbar.offset, scrollbar.len }, .{});
}

pub fn nif_focus_mode(res: TerminalResource) bool {
    const t = res.unpack().terminal;
    var enabled: bool = false;
    _ = g.ghostty_terminal_mode_get(t, dec_mode(1004), &enabled);
    return enabled;
}

fn eql(a: []const u8, comptime b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
