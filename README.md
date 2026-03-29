# Ghostty

Terminal emulator library for the BEAM — [libghostty-vt](https://ghostty.org)
NIFs with OTP integration.

SIMD-optimized VT parsing, Unicode, 24-bit color, scrollback with reflow —
all proven by millions of daily Ghostty users. Terminals are GenServers.

## Installation

```elixir
def deps do
  [{:ghostty, "~> 0.1.0"}]
end
```

Requires Zig 0.15+ (installed automatically by Zigler, or use system Zig).

## Quick start

```elixir
{:ok, term} = Ghostty.Terminal.start_link(cols: 120, rows: 40)

Ghostty.Terminal.write(term, "Hello, \e[1;32mworld\e[0m!\r\n")
Ghostty.Terminal.write(term, "\e[38;2;255;128;0morange text\e[0m\r\n")

{:ok, text} = Ghostty.Terminal.snapshot(term)
# => "Hello, world!\norange text"

{:ok, html} = Ghostty.Terminal.snapshot(term, :html)
# => HTML with inline color styles

{col, row} = Ghostty.Terminal.cursor(term)
# => {0, 2}
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

## Input encoding

```elixir
# Key events → escape sequences
{:ok, seq} = Ghostty.Terminal.input_key(term, %Ghostty.KeyEvent{
  key: :c, mods: [:ctrl]
})
# => {:ok, <<3>>}

# Mouse events (when enabled by the running program)
{:ok, seq} = Ghostty.Terminal.input_mouse(term, %Ghostty.MouseEvent{
  action: :press, button: :left, x: 10.0, y: 5.0
})
```

## PTY write-back

Programs running inside the terminal send query responses back via
the PTY. Register a callback to handle them:

```elixir
{:ok, term} = Ghostty.Terminal.start_link(
  cols: 80, rows: 24,
  on_output: fn data -> Ghostty.PTY.write(pty, data) end,
  on_bell: fn -> Logger.info("bell!") end,
  on_title: fn title -> Logger.info("title: #{title}") end
)
```

## Use cases

- **LiveView terminal** — real terminal in the browser via Phoenix
- **CI output parser** — strip ANSI from test output, get plain text
- **Terminal recorder** — capture command output as HTML for docs
- **Expect-like automation** — script interactive CLI tools
- **Terminal multiplexer** — tmux as an OTP app with hot code reload
- **Log viewer** — tail logs with progress bars → clean final state

## License

MIT
