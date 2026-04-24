# AGENTS.md

## Build

```sh
mix ghostty.setup              # clone Ghostty, build libghostty-vt into priv/
GHOSTTY_BUILD=1 mix compile    # build NIF from source (requires Zig 0.15+)
mix test                       # full suite
```

Or use a local Ghostty checkout:

```sh
GHOSTTY_SOURCE_DIR=~/code/ghostty mix ghostty.setup
```

Set `GHOSTTY_BUILD=1` for any compilation that touches Zig code.
Without it, precompiled NIF binaries are downloaded from GitHub releases.

## Architecture

Elixir → GenServer (`Terminal`) → Zig NIFs (`ghostty_nif.zig`) → libghostty-vt C API.

PTY support is separate: `Ghostty.PTY` wraps a real PTY NIF built from `pty_nif.zig`.

Current-terminal support is separate: `Ghostty.TTY` adapts the terminal running the BEAM process and emits `Ghostty.KeyEvent` values decoded by `Ghostty.KeyDecoder`.

Test helpers are separate: `Ghostty.Test` contains ExUnit ergonomics and should not bloat the production `Ghostty.Terminal` API.

- `lib/ghostty.ex` — top-level module doc
- `lib/ghostty/terminal.ex` — GenServer, public API
- `lib/ghostty/terminal/nif.ex` — ZiglerPrecompiled NIF declaration
- `lib/ghostty/terminal/ghostty_nif.zig` — terminal NIF implementation (C API bindings)
- `lib/ghostty/terminal/cell.ex` — cell flag helpers
- `lib/ghostty/key_event.ex` — keyboard input struct + key code mapping
- `lib/ghostty/key_decoder.ex` — terminal input bytes → `Ghostty.KeyEvent`
- `lib/ghostty/mouse_event.ex` — mouse input struct
- `lib/ghostty/tty.ex` — current terminal raw-input adapter for local terminal apps
- `lib/ghostty/pty.ex` — real PTY wrapper and supervision integration
- `lib/ghostty/pty_nif.ex` — PTY Zig NIF declaration
- `lib/ghostty/pty_nif.zig` — PTY NIF implementation
- `lib/ghostty/live_terminal.ex` — optional LiveView integration
- `lib/ghostty/test.ex` — ExUnit helpers for terminal snapshots/assertions/key driving
- `lib/mix/tasks/ghostty.setup.ex` — builds libghostty-vt from source

## Adding a NIF

1. Add the function in `ghostty_nif.zig`
2. Register it in `nif.ex` under `nifs:` (name: arity)
3. Add the Elixir wrapper in `terminal.ex`

## Release

Normal release flow:

1. Bump `@version` in `mix.exs`
2. Update `CHANGELOG.md` (rename `Unreleased` → `vX.Y.Z`)
3. Commit the release prep:
   ```sh
   git add mix.exs CHANGELOG.md
   git commit -m "Release vX.Y.Z"
   ```
4. Tag and push once:
   ```sh
   git tag vX.Y.Z
   git push
   git push --tags
   ```
5. Wait for `.github/workflows/precompile.yml` to finish.
   It will:
   - build terminal and PTY precompiled NIF artifacts for:
     - `x86_64-linux-gnu`
     - `aarch64-linux-gnu`
     - `aarch64-macos-none`
   - upload the release tarballs
   - regenerate `checksum-Ghostty.Terminal.Nif.exs`
   - regenerate `checksum-Ghostty.PTY.Nif.exs`
   - commit the checksum updates back to `master`
6. Pull the checksum commit locally:
   ```sh
   git pull --ff-only
   ```
7. Verify a clean install path before publishing:
   ```sh
   rm -rf _build deps
   mix deps.get
   mix compile
   ```
   On supported platforms, this should download the precompiled terminal and PTY NIFs.
8. Optionally verify source-build path too:
   ```sh
   mix ghostty.setup
   GHOSTTY_BUILD=1 mix test
   ```
9. Publish to Hex:
   ```sh
   mix hex.publish
   ```

Notes:
- `Ghostty.Terminal.Nif` and `Ghostty.PTY.Nif` are precompiled and downloaded from GitHub releases by default.
- The macOS precompiled terminal artifact must bundle `libghostty-vt.dylib` alongside the terminal NIF.
- If the tag build fails, fix the issue and release a new patch version instead of mutating an already-published Hex release.

**Do not retag after publishing to Hex.** Tag rebuilds change release artifacts and checksums.
If anything in the shipped release is wrong, publish `vX.Y.(Z+1)` instead.
