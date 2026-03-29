const beam = @import("beam");
const root = @import("root");
const std = @import("std");
const g = @cImport(@cInclude("ghostty/vt.h"));

const TerminalData = struct {
    terminal: g.GhosttyTerminal,
};

pub const TerminalResource = beam.Resource(TerminalData, root, .{
    .Callbacks = TerminalCallbacks,
});

pub const TerminalCallbacks = struct {
    pub fn dtor(data: *TerminalData) void {
        g.ghostty_terminal_free(data.terminal);
    }
};

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

fn eql(a: []const u8, comptime b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
