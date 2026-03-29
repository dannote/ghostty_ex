# Ghostty

[![Hex.pm](https://img.shields.io/hexpm/v/ghostty.svg)](https://hex.pm/packages/ghostty)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ghostty)

Terminal emulator library for the BEAM.

Wraps [libghostty-vt](https://ghostty.org) — the virtual terminal extracted from
[Ghostty](https://github.com/ghostty-org/ghostty). SIMD-optimized VT parsing,
full Unicode, 24-bit color, scrollback with text reflow. Terminals are GenServers.

## Prerequisites

libghostty-vt must be built and placed in `priv/` before compilation.
Requires [Zig 0.15+](https://ziglang.org) and the
[Ghostty source](https://github.com/ghostty-org/ghostty):

```bash
cd /path/to/ghostty
zig build -Demit-lib-vt -Doptimize=ReleaseFast

# Copy into your project
mkdir -p priv/lib priv/include
cp zig-out/lib/libghostty-vt.dylib priv/lib/       # or .so on Linux
cp -R zig-out/include/ghostty priv/include/ghostty
```

Or set `GHOSTTY_SOURCE_DIR` and enable the built-in compiler:

```elixir
# mix.exs
compilers: [:ghostty_vt] ++ Mix.compilers()
```

## Installation

```elixir
def deps do
  [{:ghostty, "~> 0.1.0"}]
end
```

## Usage

```elixir
{:ok, term} = Ghostty.Terminal.start_link(cols: 120, rows: 40)

Ghostty.Terminal.write(term, "Hello, \e[1;32mworld\e[0m!\r\n")

{:ok, text} = Ghostty.Terminal.snapshot(term)
# => "Hello, world!"

{:ok, html} = Ghostty.Terminal.snapshot(term, :html)
# => HTML with inline color styles

{col, row} = Ghostty.Terminal.cursor(term)
# => {0, 1}
```

## Supervision

```elixir
children = [
  {Ghostty.Terminal, name: :console, cols: 120, rows: 40},
  {Ghostty.Terminal, name: :logs, id: :logs, cols: 200, rows: 100,
   max_scrollback: 100_000}
]

Supervisor.start_link(children, strategy: :one_for_one)

Ghostty.Terminal.write(:console, data)
{:ok, html} = Ghostty.Terminal.snapshot(:console, :html)
```

## Resize with reflow

```elixir
Ghostty.Terminal.write(term, String.duplicate("x", 120) <> "\r\n")
Ghostty.Terminal.resize(term, 40, 24)
{:ok, text} = Ghostty.Terminal.snapshot(term)
# Long line is now wrapped across 3 lines
```

## Strip ANSI

```elixir
{:ok, term} = Ghostty.Terminal.start_link(cols: 200, rows: 500)
Ghostty.Terminal.write(term, ansi_output)
{:ok, plain} = Ghostty.Terminal.snapshot(term)
```

## Examples

See the [`examples/`](examples/) directory:

- `hello.exs` — basic write/snapshot with colors
- `ansi_stripper.exs` — pipe stdin, strip ANSI codes
- `html_recorder.exs` — capture command output as styled HTML
- `progress_bar.exs` — `\r` overwrites → final screen state only
- `reflow.exs` — text reflow on resize
- `supervised.exs` — named terminals in a supervision tree
- `diff.exs` — terminal-aware Myers diff
- `expect.exs` — Expect-like automation with pattern matching
- `pool.exs` — reusable terminal pool for concurrent processing

## Roadmap

- [ ] Key encoding via `ghostty_key_encoder` NIF
- [ ] Mouse encoding via `ghostty_mouse_encoder` NIF
- [ ] Effect callbacks (PTY write-back, bell, title)
- [ ] Render state API (cell-level iteration for LiveView)
- [ ] PTY module (`forkpty` + non-blocking I/O)
- [ ] Precompiled NIF binaries

## License

MIT
