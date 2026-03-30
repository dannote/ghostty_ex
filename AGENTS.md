# AGENTS.md

## Build

```sh
mix ghostty.setup              # clone Ghostty, build libghostty-vt into priv/
GHOSTTY_BUILD=1 mix compile    # build NIF from source (requires Zig 0.15+)
mix test                       # full suite (35 tests)
```

Or use a local Ghostty checkout:

```sh
GHOSTTY_SOURCE_DIR=~/code/ghostty mix ghostty.setup
```

Set `GHOSTTY_BUILD=1` for any compilation that touches Zig code.
Without it, precompiled NIF binaries are downloaded from GitHub releases.

## Architecture

Elixir → GenServer (`Terminal`) → Zig NIFs (`ghostty_nif.zig`) → libghostty-vt C API.

- `lib/ghostty.ex` — top-level module doc
- `lib/ghostty/terminal.ex` — GenServer, public API
- `lib/ghostty/terminal/nif.ex` — ZiglerPrecompiled NIF declaration
- `lib/ghostty/terminal/ghostty_nif.zig` — NIF implementation (C API bindings)
- `lib/ghostty/terminal/cell.ex` — cell flag helpers
- `lib/ghostty/key_event.ex` — keyboard input struct + key code mapping
- `lib/ghostty/mouse_event.ex` — mouse input struct
- `lib/ghostty/pty.ex` — subprocess I/O via Erlang ports
- `lib/mix/tasks/ghostty.setup.ex` — builds libghostty-vt from source
- `lib/mix/tasks/compile/ghostty_vt.ex` — copies priv/ into _build priv/

## Adding a NIF

1. Add the function in `ghostty_nif.zig`
2. Register it in `nif.ex` under `nifs:` (name: arity)
3. Add the Elixir wrapper in `terminal.ex`

## Release

1. Bump `@version` in `mix.exs`
2. Update `CHANGELOG.md` (rename "Unreleased" → version)
3. Set placeholder checksums in `checksum-Ghostty.Terminal.Nif.exs`
4. Commit: `git commit -m "Release vX.Y.Z"`
5. Tag and push: `git tag vX.Y.Z && git push && git push --tags`
6. Wait for the precompile workflow (builds NIFs for linux-x64, linux-arm64, macos-arm64)
7. Download artifacts, compute checksums:
   ```sh
   gh release download vX.Y.Z --dir /tmp/release
   for f in /tmp/release/*.tar.gz; do
     echo "{\"$(basename $f)\", \"sha256:$(shasum -a 256 $f | cut -d' ' -f1)\"},"
   done
   ```
8. Update `checksum-Ghostty.Terminal.Nif.exs` with real hashes
9. Commit and push: `git commit -am "Update precompiled NIF checksums for vX.Y.Z" && git push`
10. Publish: `mix hex.publish`

**Never force-push a release tag.** The precompile workflow runs on tag push.
Force-pushing re-triggers it, producing new artifacts with different checksums
than what was already published to Hex. If you need to fix a release, publish
a patch version instead.
