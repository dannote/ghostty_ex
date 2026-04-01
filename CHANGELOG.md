# Changelog

## 0.2.3 (2026-04-02)

### Build

- Exclude the bundled Phoenix example app dependencies from the Hex package
- Keep the published package small enough for Hex validation while still shipping the top-level example scripts
- Fix the macOS precompiled terminal artifact so `libghostty-vt.dylib` is linked via `@loader_path` instead of a CI-only absolute path
- Verify the packaged macOS terminal artifact before upload in the precompile workflow

## 0.2.2 (2026-04-01)

### LiveView

- Make render events terminal-specific so multiple terminals can coexist in one LiveView safely
- Push the initial render automatically from `Ghostty.LiveTerminal.Component`
- Preserve incoming assigns on `send_update(..., refresh: true)`
- Support global HTML attributes on `Ghostty.LiveTerminal.terminal/1`
- Refresh the README LiveView docs around the component-first API

### Build

- Re-sync `priv/lib` and `priv/include` into `_build/<env>/lib/ghostty/priv` during `GHOSTTY_BUILD=1` compilation
- Fix macOS source builds after `_build` cleanup by rewriting the copied `libghostty-vt.dylib` install name to an absolute path

## 0.2.1 (2026-03-31)

### PTY

- Validate PTY size during startup as well as `resize/3`
- Remove generated PTY Zig wrapper file from the repo
- Ignore generated PTY Zig wrapper file going forward

### Build

- Make `mix ghostty.setup` copy `priv/` artifacts more robustly from the project root
- Refresh build `priv/` directories deterministically during setup

### Docs

- Use GitHub example links in README so HexDocs does not warn about missing local `examples/` paths

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

### Build

- `mix ghostty.setup` — one-command contributor onboarding
- Precompiled NIFs via `zigler_precompiled`
- Precompile workflow builds and uploads terminal and PTY NIF artifacts for Linux x86_64, Linux aarch64, and macOS aarch64
- Precompiled terminal artifacts bundle `libghostty-vt` so clean installs work without manual setup
- Release workflow regenerates and commits `checksum-Ghostty.Terminal.Nif.exs` and `checksum-Ghostty.PTY.Nif.exs`
- zlint for Zig code

### Docs

- README examples are covered by tests
- Release/install flow documented in `AGENTS.md`

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
