# Expect-like automation — run a command, wait for patterns, send input.
# The terminal tracks the real screen state so pattern matching works
# even through ANSI codes, cursor movement, and progress bars.
#
#   mix run examples/expect.exs

defmodule Expect do
  defstruct [:term, :port]

  def open(cmd, opts \\ []) do
    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)

    {:ok, term} = Ghostty.Terminal.start_link(cols: cols, rows: rows)
    port = Port.open({:spawn, cmd}, [:binary, :exit_status, :use_stdio, :stderr_to_stdout])

    %__MODULE__{term: term, port: port}
  end

  def expect(%__MODULE__{} = e, pattern, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_expect(e, pattern, deadline)
  end

  defp do_expect(e, pattern, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:ok, screen} = Ghostty.Terminal.snapshot(e.term)
      {:error, {:timeout, screen}}
    else
      receive do
        {port, {:data, data}} when port == e.port ->
          Ghostty.Terminal.write(e.term, data)
          {:ok, screen} = Ghostty.Terminal.snapshot(e.term)

          if screen =~ pattern do
            {:ok, screen}
          else
            do_expect(e, pattern, deadline)
          end

        {port, {:exit_status, status}} when port == e.port ->
          {:exit, status}
      after
        min(remaining, 100) -> do_expect(e, pattern, deadline)
      end
    end
  end

  def send_input(%__MODULE__{port: port}, text) do
    Port.command(port, text)
  end

  def snapshot(%__MODULE__{term: term}, format \\ :plain) do
    Ghostty.Terminal.snapshot(term, format)
  end

  def close(%__MODULE__{term: term, port: port}) do
    Port.close(port)
    GenServer.stop(term)
  end
end

# Demo: run `echo` through bash
e = Expect.open("bash -c 'echo hello; echo world; sleep 0.1; echo done'")

case Expect.expect(e, "done") do
  {:ok, screen} ->
    IO.puts("Screen after 'done' appeared:")
    IO.puts(screen)

  {:error, {:timeout, screen}} ->
    IO.puts("Timed out. Screen:")
    IO.puts(screen)

  {:exit, status} ->
    IO.puts("Process exited with: #{status}")
end

Expect.close(e)
