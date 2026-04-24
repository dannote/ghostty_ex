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

Precompiled terminal and PTY NIF binaries are downloaded automatically for
x86_64 Linux, aarch64 Linux, and aarch64 macOS.

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

## Current terminal TTY

Use `Ghostty.TTY` for local terminal applications that need raw keyboard input
from the terminal running the BEAM process:

```elixir
{:ok, tty} = Ghostty.TTY.start_link()
Ghostty.TTY.write(tty, [IO.ANSI.clear(), IO.ANSI.home(), "Ready"])

receive do
  {Ghostty.TTY, ^tty, {:key, %Ghostty.KeyEvent{key: :enter}}} -> :submitted
  {Ghostty.TTY, ^tty, {:resize, cols, rows}} -> {cols, rows}
end
```

`Ghostty.TTY` complements `Ghostty.PTY`: TTY is the current terminal; PTY is for
child pseudo-terminals. Raw terminal bytes are decoded by `Ghostty.KeyDecoder`.
See `examples/tty_keys.exs` for an interactive smoke test.

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

## LiveView

Install the LiveView hook into a Phoenix app with:

```bash
mix igniter.install ghostty
```

Then drop in a terminal with `Ghostty.LiveTerminal.Component` — it handles
keyboard events internally so your LiveView only manages the terminal
and PTY lifecycle:

```elixir
defmodule MyAppWeb.TerminalLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
    {:ok, assign(socket, term: term, pty: nil)}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={Ghostty.LiveTerminal.Component}
      id="term"
      term={@term}
      pty={@pty}
      fit={true}
      autofocus={true}
    />
    """
  end

  def handle_info({:terminal_ready, "term", cols, rows}, socket) do
    {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/bash", cols: cols, rows: rows)
    {:noreply, assign(socket, pty: pty)}
  end

  def handle_info({:data, data}, socket) do
    Ghostty.Terminal.write(socket.assigns.term, data)
    send_update(Ghostty.LiveTerminal.Component, id: "term", refresh: true)
    {:noreply, socket}
  end

  def handle_info({:exit, _status}, socket), do: {:noreply, socket}
end
```

### Component assigns

| Assign | Default | Description |
|---|---|---|
| `:term` | required | `Ghostty.Terminal` pid |
| `:pty` | `nil` | `Ghostty.PTY` pid; key input is written here when present |
| `:fit` | `false` | Auto-fit terminal size to the rendered container |
| `:autofocus` | `false` | Focus the hidden terminal input on mount |
| `:class` | `""` | CSS class for the container div |

When `fit` is enabled, the hook measures the container and sends a `"ready"`
event with the computed `cols` and `rows`. The component resizes the terminal
and notifies the parent with `{:terminal_ready, id, cols, rows}` —
use this to defer PTY startup until the real container size is known.

### Low-level helpers

For full control, use the helpers directly:

```elixir
Ghostty.LiveTerminal.key_event_from_params(params)       # parse browser key event
Ghostty.LiveTerminal.handle_key(term, params)             # parse + encode
Ghostty.LiveTerminal.push_render(socket, "term-id", term) # push cells to client
```

### Asset bundling

`mix igniter.install ghostty` vendors `ghostty.js` into your app assets and wires
`GhosttyTerminal` into `assets/js/app.js` automatically.

TypeScript source lives in `priv/ts/` and is bundled at compile time via
[OXC](https://hex.pm/packages/oxc) — no Node.js or Bun required for end users.

Contributors can run TypeScript quality checks:

```bash
bun install && bun run lint && bun run format:check
```

### Demo app

See [`examples/live_terminal/`](https://github.com/dannote/ghostty_ex/tree/master/examples/live_terminal)
for a complete runnable app with Playwright browser tests. It includes a control
panel with preset commands, fit/banner toggles, and sets `TERM=xterm-256color`
for colorized shell output.

## ExUnit helpers

`Ghostty.Test` provides concise test helpers without expanding the core
`Ghostty.Terminal` API:

```elixir
defmodule MyTerminalTest do
  use ExUnit.Case, async: true

  import Ghostty.Test

  test "renders output" do
    {:ok, terminal} = term(cols: 80, rows: 24)

    terminal
    |> lines(["Hello", IO.ANSI.red(), "red", IO.ANSI.reset()])
    |> assert_text("Hello")
    |> refute_text("missing")
    |> assert_snap("test/fixtures/terminal/basic.txt")
  end
end
```

Set `UPDATE_GHOSTTY_SNAPSHOTS=1` to rewrite snapshot fixture files.

## Examples

See the [`examples/`](https://github.com/dannote/ghostty_ex/tree/master/examples) directory:

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
| [`live_terminal/`](https://github.com/dannote/ghostty_ex/tree/master/examples/live_terminal) | Phoenix LiveView terminal renderer with Playwright browser tests |

## Development

[Zig 0.15+](https://ziglang.org) is only required for source builds.

```bash
git clone https://github.com/dannote/ghostty_ex
cd ghostty_ex
mix deps.get
mix ghostty.setup            # clones Ghostty, builds libghostty-vt
GHOSTTY_BUILD=1 mix test
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
