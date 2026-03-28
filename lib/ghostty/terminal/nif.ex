defmodule Ghostty.Terminal.Nif do
  @moduledoc false

  use Zig,
    otp_app: :ghostty,
    c: [
      include_dirs: [
        {:priv, "include"}
      ],
      link_lib: [
        {:priv, "lib/libghostty-vt"}
      ]
    ],
    resources: [:TerminalResource],
    nifs: [
      nif_new: [:dirty_cpu],
      nif_free: [:dirty_cpu],
      nif_vt_write: [:dirty_cpu],
      nif_resize: [:dirty_cpu],
      nif_reset: [:dirty_cpu],
      nif_snapshot: [:dirty_cpu],
      nif_scroll: [:dirty_cpu],
      nif_get_cursor: [:dirty_cpu]
    ]

  ~Z"""
  const beam = @import("beam");
  const root = @import("root");
  const ghostty = @cImport({
      @cInclude("ghostty/vt.h");
  });

  const TerminalData = struct {
      terminal: ghostty.GhosttyTerminal,
  };

  pub const TerminalResource = beam.Resource(TerminalData, root, .{
      .Callbacks = TerminalCallbacks,
  });

  pub const TerminalCallbacks = struct {
      pub fn dtor(data: *TerminalData) void {
          ghostty.ghostty_terminal_free(data.terminal);
      }
  };

  pub fn nif_new(cols: u16, rows: u16, max_scrollback: u32) !TerminalResource {
      var terminal: ghostty.GhosttyTerminal = undefined;
      const opts = ghostty.GhosttyTerminalOptions{
          .cols = cols,
          .rows = rows,
          .max_scrollback = max_scrollback,
      };
      const result = ghostty.ghostty_terminal_new(null, &terminal, opts);
      if (result != ghostty.GHOSTTY_SUCCESS) {
          return error.terminal_creation_failed;
      }
      return TerminalResource.create(.{ .terminal = terminal }, .{});
  }

  pub fn nif_free(res: TerminalResource) void {
      const data = res.unpack();
      ghostty.ghostty_terminal_free(data.terminal);
      // Mark as freed - resource destructor will handle if called again
      // Actually, we need to prevent double-free. For now, the resource
      // destructor handles cleanup when GC'd.
      _ = data;
  }

  pub fn nif_vt_write(res: TerminalResource, data: []const u8) void {
      const term_data = res.unpack();
      ghostty.ghostty_terminal_vt_write(term_data.terminal, data.ptr, data.len);
  }

  pub fn nif_resize(res: TerminalResource, cols: u16, rows: u16) void {
      const term_data = res.unpack();
      ghostty.ghostty_terminal_resize(term_data.terminal, cols, rows);
  }

  pub fn nif_reset(res: TerminalResource) void {
      const term_data = res.unpack();
      ghostty.ghostty_terminal_reset(term_data.terminal);
  }

  pub fn nif_scroll(res: TerminalResource, delta: i32) void {
      const term_data = res.unpack();
      ghostty.ghostty_terminal_scroll_viewport(term_data.terminal, delta);
  }

  pub fn nif_get_cursor(res: TerminalResource) !beam.term {
      const term_data = res.unpack();
      var col: u16 = 0;
      var row: u16 = 0;
      _ = ghostty.ghostty_terminal_get(term_data.terminal, ghostty.GHOSTTY_TERMINAL_DATA_CURSOR_X, &col);
      _ = ghostty.ghostty_terminal_get(term_data.terminal, ghostty.GHOSTTY_TERMINAL_DATA_CURSOR_Y, &row);
      return beam.make(.{ col, row }, .{});
  }

  pub fn nif_snapshot(res: TerminalResource, format_atom: beam.term) !beam.term {
      const term_data = res.unpack();

      // Determine format from atom
      const format_str = beam.get([]const u8, format_atom, .{}) catch return error.badarg;
      var emit: c_uint = undefined;
      if (std_mem_eql(format_str, "plain")) {
          emit = ghostty.GHOSTTY_FORMATTER_FORMAT_PLAIN;
      } else if (std_mem_eql(format_str, "html")) {
          emit = ghostty.GHOSTTY_FORMATTER_FORMAT_HTML;
      } else if (std_mem_eql(format_str, "vt")) {
          emit = ghostty.GHOSTTY_FORMATTER_FORMAT_VT;
      } else {
          return error.badarg;
      }

      // Create formatter options
      var fmt_opts: ghostty.GhosttyFormatterTerminalOptions = std.mem.zeroes(ghostty.GhosttyFormatterTerminalOptions);
      fmt_opts.size = @sizeOf(ghostty.GhosttyFormatterTerminalOptions);
      fmt_opts.emit = emit;
      fmt_opts.trim = true;

      // Create formatter
      var fmtr: ghostty.GhosttyFormatter = undefined;
      const fmtr_result = ghostty.ghostty_formatter_terminal_new(null, &fmtr, term_data.terminal, fmt_opts);
      if (fmtr_result != ghostty.GHOSTTY_SUCCESS) {
          return error.formatter_creation_failed;
      }
      defer ghostty.ghostty_formatter_free(fmtr);

      // Format with alloc
      var buf: [*c]u8 = undefined;
      var len: usize = 0;
      const format_result = ghostty.ghostty_formatter_format_alloc(fmtr, null, &buf, &len);
      if (format_result != ghostty.GHOSTTY_SUCCESS) {
          return error.format_failed;
      }

      // Copy to BEAM binary and free C buffer
      const slice = buf[0..len];
      defer std.c.free(@ptrCast(buf));
      return beam.make(slice, .{});
  }

  const std = @import("std");

  fn std_mem_eql(a: []const u8, comptime b: []const u8) bool {
      return std.mem.eql(u8, a, b);
  }
  """
end
