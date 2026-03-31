# Changelog

## 0.2.0 (2026-03-30)

### Terminal

- `input_key/2` — encode keyboard events to escape sequences
- `input_mouse/2` — encode mouse events (when tracking enabled)
- `encode_focus/1` — encode focus gained/lost
- `cells/1` — render state as grid of `{grapheme, fg, bg, flags}` tuples
- `Ghostty.Terminal.Cell` — flag helpers (`bold?/1`, `italic?/1`, etc.)
- Effect messages sent to the calling process:
  `{:pty_write, data}`, `:bell`, `:title_changed`
- Option validation — `ArgumentError` for invalid cols/rows/scrollback
- Graceful init failure — `{:error, reason}` instead of crash

### PTY

- Real pseudo-terminal via `forkpty()` NIF
- Programs like `vim`, `top`, `htop` work (child gets a real TTY)
- Non-blocking reader thread sends `{:data, binary}` messages
- `write/2`, `resize/3`, `close/1`
- Proper cleanup in destructor (SIGHUP, waitpid)

### LiveView

- `Ghostty.LiveTerminal` — Phoenix LiveView component
- `terminal/1` component with JS hook
- `handle_key/2` converts JS keyboard events to key encoding
- `priv/static/ghostty.js` — renders cell grid with colors and styles
- Optional: only compiles when `phoenix_live_view` is present

### Input

- `Ghostty.KeyEvent` — strict validation, raises on unknown keys
- `Ghostty.MouseEvent` — strict validation, raises on unknown buttons
- `Ghostty.Mods` — shared modifier bitmask encoding

### Build

- `mix ghostty.setup` — one-command contributor onboarding
- Precompiled NIFs via `zigler_precompiled`
- zlint for Zig code

## 0.1.0 (2026-03-29)

Initial release.

### Terminal

- `Ghostty.Terminal` GenServer with full lifecycle management
- `write/2`, `snapshot/2`, `resize/3`, `reset/1`, `scroll/2`, `cursor/1`, `size/1`
- Supervision support, named terminals

### NIF

- Zigler-based NIFs linking libghostty-vt via C API
- NIF resource with destructor
- BEAM allocator for format buffers

### Build

- Precompiled NIF binaries for x86_64 Linux, aarch64 Linux, aarch64 macOS
- Requires Zig 0.15+ for source builds
