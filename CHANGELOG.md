# Changelog

## 0.4.1 (2026-04-24)

### TTY

- Fix `Ghostty.TTY.start_link/1` on OTP runtimes that do not expose `:sigwinch` through `:os.set_signal/2`
- Treat SIGWINCH registration as best-effort so current-terminal apps can still start when resize signals are unavailable

## 0.4.0 (2026-04-24)

### TTY

- Add `Ghostty.TTY` for local terminal applications that need raw keyboard input from the current BEAM terminal
- Add `Ghostty.KeyDecoder` for decoding terminal input bytes into `Ghostty.KeyEvent` values
- Add `examples/tty_keys.exs` as an interactive smoke test for current-terminal input, resize events, and key decoding

### Testing

- Add `Ghostty.Test` ExUnit helpers for concise terminal tests: `term/1`, `write/2`, `lines/2`, snapshots, text assertions, key encoding, and cell assertions
- Add snapshot assertion support via `assert_snap/3` with `UPDATE_GHOSTTY_SNAPSHOTS=1`
- Dogfood `Ghostty.Test` in terminal and cell tests

### Terminal

- Return `{:error, :invalid_key_event}` for invalid keyboard events instead of crashing the terminal GenServer
- Return `{:error, :invalid_mouse_event}` for invalid mouse events instead of crashing the terminal GenServer

### Docs

- Document `Ghostty.TTY` and ExUnit helpers in the README
- Add `Ghostty.TTY`, `Ghostty.KeyDecoder`, and `Ghostty.Test` to HexDocs groups and package files

## 0.3.2 (2026-04-14)

### Fix

- Fix precompiled NIF failing to load due to missing `nif_focus_mode` declaration

## 0.3.1 (2026-04-14) [YANKED]

### LiveView

- Add punctuation and shifted character key mappings

### PTY

- Fix UI hangs when typing fast by draining the PTY buffer fully on each poll wakeup
- Handle POLLHUP/POLLERR without POLLIN to ensure exit notification is always sent

### Internal

- Remove unused `nif_focus_mode` NIF
- Cache `nif_render_state` availability at compile time instead of try/rescue per call
- Deduplicate PTY reader exit path into `send_exit_and_wait`
- Remove redundant client-side input validation (kept in GenServer)
- Remove self-delegating `mods_to_bitmask` in favour of `to_bitmask`

## 0.3.0 (2026-04-08)

### LiveView

- Add render-state cursor overlay with block, bar, underline, and hollow styles
- Add hidden textarea input layer with IME composition and paste support
- Add local selection rendering with copy support
- Add mouse forwarding with mouse-mode-aware selection backoff
- Add `fit` option for auto-fit terminal size to container via `ResizeObserver`
- Add `autofocus` option for initial terminal focus on mount
- Add `{:terminal_ready, id, cols, rows}` message so the parent can defer PTY startup until the real container size is known
- Add `handle_resize/4` helper for resizing terminal and PTY together
- Add `phx-update="ignore"` to terminal hook roots so LiveView patches don't destroy client-rendered DOM
- Fix focus escape sequences being written into the terminal buffer when no PTY is attached
- Fix terminal reclaiming focus from outside page elements during text selection
- Track mouse modes in `Ghostty.Terminal` from VT writes for reliable LiveView payloads

### Hook

- Rewrite `ghostty.js` to TypeScript under `priv/ts/` with strict types
- Bundle TypeScript at compile time via OXC — no Node.js or Bun required
- Add oxlint and oxfmt for TypeScript quality checks
- Ship `priv/ts/` source in the Hex package instead of pre-built JS
- Add explicit outside-click blur so the terminal doesn't steal focus
- Add pointer-active tracking so outside mouse interactions can't refocus the terminal

### Examples

- Replace URL-param demo with a control panel: startup command input, fit/banner toggles, preset buttons
- Add `TERM=xterm-256color` and `COLORTERM=truecolor` for colorized shell output
- Add demo-specific bash rcfile with `ls` color aliases
- Use `bash -lc` for startup commands to avoid PTY write races
- Defer PTY startup until the hook reports its real container size
- Replace timer-based startup with event-driven ready handshake
- Add browser tests for flush-left prompt, outside focus, and demo controls
- Wire example browser tests into CI

### Build

- Add `{:oxc, "~> 0.5"}` dependency for compile-time TypeScript bundling
- Add a Mix compiler that bundles `priv/ts/hook.ts` → `priv/static/ghostty.js`
- Add CI job for TypeScript lint and format checks
- Stop tracking `priv/static/ghostty.js` in git

## 0.2.4 (2026-04-02)

### LiveView

- Add `mix igniter.install ghostty` to vendor `ghostty.js` into Phoenix assets and wire `GhosttyTerminal` into `assets/js/app.js`
- Cover the installer with tests for common Phoenix `app.js` layouts
- Update the LiveView docs to point to the Igniter install flow

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

- `start_link/1` with `:cols`, `:rows`, `:max_scrollback`, `:name`
- `write/2` — VT-encoded data
- `resize/3` — with text reflow
- `reset/1` — full terminal reset (RIS)
- `snapshot/2` — `:plain`, `:html`, `:vt` formats
- `scroll/2` — viewport scrolling
- `cursor/1` — cursor position
- `size/1` — terminal dimensions

### Build

- libghostty-vt C API via Zig NIFs (Zigler)
- Precompiled NIF binaries for Linux and macOS
