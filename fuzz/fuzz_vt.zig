const std = @import("std");
const g = @cImport(@cInclude("ghostty/vt.h"));

fn fuzz_one(_: void, input: []const u8) anyerror!void {
    var terminal: g.GhosttyTerminal = undefined;
    const result = g.ghostty_terminal_new(null, &terminal, .{
        .cols = 80,
        .rows = 24,
        .max_scrollback = 100,
    });
    if (result != g.GHOSTTY_SUCCESS) return;
    defer g.ghostty_terminal_free(terminal);

    g.ghostty_terminal_vt_write(terminal, input.ptr, input.len);

    var state: g.GhosttyRenderState = undefined;
    if (g.ghostty_render_state_new(null, &state) == g.GHOSTTY_SUCCESS) {
        _ = g.ghostty_render_state_update(state, terminal);
        g.ghostty_render_state_free(state);
    }

    _ = g.ghostty_terminal_resize(terminal, 40, 12, 0, 0);

    g.ghostty_terminal_reset(terminal);
}

test "fuzz vt parser" {
    try std.testing.fuzz({}, fuzz_one, .{});
}
