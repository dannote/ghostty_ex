defmodule Ghostty do
  @moduledoc """
  Terminal emulator library for the BEAM.

  Wraps [libghostty-vt](https://ghostty.org) — the virtual terminal extracted
  from [Ghostty](https://github.com/ghostty-org/ghostty). SIMD-optimized VT
  parsing, full Unicode, 24-bit color, scrollback with text reflow. Terminals
  are GenServers.

  ## Quick start

      {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)

      Ghostty.Terminal.write(term, "Hello, \\e[1;32mworld\\e[0m!\\r\\n")

      {:ok, text} = Ghostty.Terminal.snapshot(term)
      # => "Hello, world!"

  ## Supervision

      children = [
        {Ghostty.Terminal, name: :console, cols: 120, rows: 40}
      ]
      Supervisor.start_link(children, strategy: :one_for_one)

  """
end
