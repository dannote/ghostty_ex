const beam = @import("beam");
const root = @import("root");
const std = @import("std");
const g = @cImport(@cInclude("ghostty/vt.h"));

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

fn eql(a: []const u8, comptime b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
