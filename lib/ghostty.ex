defmodule Ghostty do
  @moduledoc """
  Terminal emulator library for the BEAM — libghostty-vt NIFs with OTP integration.

  Ghostty wraps [libghostty-vt](https://ghostty.org), the virtual terminal
  emulator library extracted from the Ghostty terminal. Each terminal is a
  GenServer with SIMD-optimized VT parsing, Unicode support, and a
  robust fuzz-tested codebase proven by millions of daily Ghostty users.

  ## Quick start

      {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)

      # Feed VT data
      Ghostty.Terminal.write(term, "Hello, \\e[1;32mworld\\e[0m!\\r\\n")

      # Read the screen
      {:ok, text} = Ghostty.Terminal.snapshot(term)
      # => "Hello, world!"

  ## Streaming from a PTY

      {:ok, term} = Ghostty.Terminal.start_link(
        cols: 120, rows: 40,
        on_output: fn data -> Ghostty.PTY.write(pty, data) end
      )

      # PTY data flows in
      Ghostty.Terminal.write(term, pty_data)

      # Keyboard events flow out
      Ghostty.Terminal.input_key(term, %Ghostty.KeyEvent{key: :c, mods: [:ctrl]})
      # => {:ok, <<3>>}

  ## Supervision

      children = [
        {Ghostty.Terminal, name: :console, cols: 120, rows: 40}
      ]
      Supervisor.start_link(children, strategy: :one_for_one)

  """
end
