# Ghostty

Terminal emulator library for the BEAM.

Wraps [libghostty-vt](https://ghostty.org) — the virtual terminal extracted from
[Ghostty](https://github.com/ghostty-org/ghostty). SIMD-optimized VT parsing,
full Unicode, 24-bit color, scrollback with text reflow. Terminals are GenServers.

## Installation

```elixir
def deps do
  [{:ghostty, "~> 0.2"}]
end
```

Precompiled NIF binaries are downloaded automatically for x86_64 Linux,
aarch64 Linux, and aarch64 macOS.

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

## Messages

### Terminal effects

Effect messages are sent to the process that called `start_link/1`:

| Message | Trigger |
|---|---|
| `{:pty_write, binary}` | Query responses to write back to the PTY |
| `:bell` | BEL character (`\a`) |
| `:title_changed` | Title change via OSC 2 |

### Subprocess output

`Ghostty.PTY` sends messages to the process that called `start_link/1`:

| Message | Trigger |
|---|---|
| `{:data, binary}` | Subprocess stdout/stderr |
| `{:exit, status}` | Subprocess exit |

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

## Render state

Read the screen as a grid of cells for building custom renderers
(LiveView, Scenic, etc.):

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

Run interactive programs in a real pseudo-terminal:

```elixir
{:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
{:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/bash", cols: 80, rows: 24)

# PTY output arrives as messages
receive do
  {:data, data} -> Ghostty.Terminal.write(term, data)
end

# Send keyboard input
Ghostty.PTY.write(pty, "ls --color\n")

# Resize the PTY (reflows in the terminal too)
Ghostty.PTY.resize(pty, 120, 40)
Ghostty.Terminal.resize(term, 120, 40)
```

## Examples

See the [`examples/`](https://github.com/dannote/ghostty_ex/blob/master/examples/) directory:

| Example | What it does |
|---|---|
| [`hello.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/hello.exs) | Write with colors, read back plain + HTML |
| [`ansi_stripper.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/ansi_stripper.exs) | Pipe stdin, strip ANSI codes |
| [`html_recorder.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/html_recorder.exs) | Capture command output as styled HTML |
| [`progress_bar.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/progress_bar.exs) | `\r` overwrites → final screen state only |
| [`reflow.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/reflow.exs) | Text reflow on resize |
| [`supervised.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/supervised.exs) | Named terminals in a supervision tree |
| [`diff.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/diff.exs) | Terminal-aware Myers diff |
| [`expect.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/expect.exs) | Expect-like automation with pattern matching |
| [`pool.exs`](https://github.com/dannote/ghostty_ex/blob/master/examples/pool.exs) | Reusable terminal pool for concurrent processing |

## Development

[Zig 0.15+](https://ziglang.org) required to build from source.

```bash
git clone https://github.com/dannote/ghostty_ex
cd ghostty_ex
mix deps.get
mix ghostty.setup            # clones Ghostty, builds libghostty-vt
GHOSTTY_BUILD=1 mix test     # 44 tests
```

To use an existing Ghostty checkout:

```bash
GHOSTTY_SOURCE_DIR=~/code/ghostty mix ghostty.setup
```

### Troubleshooting

**Xcode 26.4 breaks Zig builds on macOS.** Downgrade to Xcode 26.3 CLT:

```bash
# Download from https://developer.apple.com/download/all/?q=Command+Line+Tools+for+Xcode+26.3
sudo xcode-select --switch /Library/Developer/CommandLineTools
```

See [ziglang/zig#31658](https://codeberg.org/ziglang/zig/issues/31658) for details.

## License

MIT
