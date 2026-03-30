# Ghostty

Terminal emulator library for the BEAM.

Wraps [libghostty-vt](https://ghostty.org) — the virtual terminal extracted from
[Ghostty](https://github.com/ghostty-org/ghostty). SIMD-optimized VT parsing,
full Unicode, 24-bit color, scrollback with text reflow. Terminals are GenServers.

## Prerequisites

Precompiled NIF binaries are downloaded automatically for supported platforms
(x86_64 Linux, aarch64 Linux, aarch64 macOS).

To build from source instead, set `GHOSTTY_BUILD=1` and ensure
[Zig 0.15+](https://ziglang.org) is on PATH. libghostty-vt headers and library
must be in `priv/`:

```bash
cd /path/to/ghostty
zig build -Demit-lib-vt -Doptimize=ReleaseFast

# Copy into your project
mkdir -p priv/lib priv/include
cp zig-out/lib/libghostty-vt.* priv/lib/
cp -R zig-out/include/ghostty priv/include/ghostty
```

## Installation

```elixir
def deps do
  [{:ghostty, "~> 0.1"}]
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

| Example | What it does |
|---|---|
| [`hello.exs`](examples/hello.exs) | Write with colors, read back plain + HTML |
| [`ansi_stripper.exs`](examples/ansi_stripper.exs) | Pipe stdin, strip ANSI codes |
| [`html_recorder.exs`](examples/html_recorder.exs) | Capture command output as styled HTML |
| [`progress_bar.exs`](examples/progress_bar.exs) | `\r` overwrites → final screen state only |
| [`reflow.exs`](examples/reflow.exs) | Text reflow on resize |
| [`supervised.exs`](examples/supervised.exs) | Named terminals in a supervision tree |
| [`diff.exs`](examples/diff.exs) | Terminal-aware Myers diff |
| [`expect.exs`](examples/expect.exs) | Expect-like automation with pattern matching |
| [`pool.exs`](examples/pool.exs) | Reusable terminal pool for concurrent processing |

## Render state

Read the screen as a grid of cells for building custom renderers (LiveView, Scenic, etc.):

```elixir
rows = Ghostty.Terminal.cells(term)

for row <- rows do
  for {grapheme, fg, bg, flags} <- row do
    if Ghostty.Terminal.Cell.bold?({grapheme, fg, bg, flags}) do
      IO.write(IO.ANSI.bright())
    end
    IO.write(grapheme)
  end
  IO.puts("")
end
```

## PTY

Run a subprocess and pipe its output through the terminal:

```elixir
{:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
{:ok, pty} = Ghostty.PTY.start_link(
  cmd: "/bin/bash",
  on_data: fn data -> Ghostty.Terminal.write(term, data) end
)

Ghostty.PTY.write(pty, "ls --color\n")
Process.sleep(100)
{:ok, html} = Ghostty.Terminal.snapshot(term, :html)
```

## License

MIT
