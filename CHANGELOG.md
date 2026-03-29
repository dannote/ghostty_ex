# Changelog

## 0.1.0 (2026-03-29)

Initial release.

### Terminal

- `Ghostty.Terminal` GenServer with full lifecycle management
- `write/2` — feed VT-encoded data (iodata)
- `snapshot/2` — read screen as `:plain`, `:html`, or `:vt`
- `resize/3` — resize with automatic text reflow
- `reset/1` — full terminal reset (RIS)
- `scroll/2` — viewport scrollback
- `cursor/1` — current cursor position
- `size/1` — current dimensions
- Supervision support via `child_spec/1`
- Named terminals for direct access

### NIF

- Zigler-based NIFs linking libghostty-vt via C API
- NIF resource with destructor (no leaks on GC or crash)
- All operations on dirty CPU scheduler
- BEAM allocator for format buffers

### Build

- `Mix.Tasks.Compile.GhosttyVt` — builds libghostty-vt from source
- Requires Zig 0.15+ and Ghostty source tree
