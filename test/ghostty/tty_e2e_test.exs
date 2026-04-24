defmodule Ghostty.TTYE2ETest do
  use ExUnit.Case, async: false

  alias Ghostty.PTY

  @tag :tmp_dir
  test "TTY receives raw key events inside a real PTY", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "tty_echo.exs")
    File.write!(script, child_script())

    ebin_paths = Path.wildcard(Path.expand("_build/test/lib/*/ebin"))
    path_args = Enum.flat_map(ebin_paths, &["-pa", &1])

    {:ok, pty} = PTY.start_link(cmd: System.find_executable("elixir"), args: path_args ++ [script], cols: 100, rows: 24)

    output = wait_until("WAITING", "")

    PTY.write(pty, "a")
    output = wait_until("GOT:a", output)
    output = wait_until("WAITING:again", output)

    PTY.write(pty, <<3>>)
    output = wait_until("GOT:ctrl-c", output)

    refute output =~ "BREAK:"
    refute output =~ "TIMEOUT"
  end

  defp wait_until(expected, output) do
    deadline = System.monotonic_time(:millisecond) + 3_000
    collect_until(expected, output, deadline)
  end

  defp collect_until(expected, output, deadline) do
    if output =~ expected do
      output
    else
      receive do
        {:data, data} ->
          collect_until(expected, output <> data, deadline)

        {:exit, status} ->
          flunk("PTY exited with status #{inspect(status)} before #{inspect(expected)}. Output:\n#{output}")
      after
        20 ->
          if System.monotonic_time(:millisecond) < deadline do
            collect_until(expected, output, deadline)
          else
            flunk("Timed out waiting for #{inspect(expected)}. Output:\n#{output}")
          end
      end
    end
  end

  defp child_script do
    ~S'''
    {:ok, tty} = Ghostty.TTY.start_link(owner: self())
    Ghostty.TTY.write(tty, "READY\r\n")

    loop = fn loop, seen ->
      waiting = if seen == [], do: "WAITING", else: "WAITING:again"
      Ghostty.TTY.write(tty, [waiting, "\r\n"])

      receive do
        {Ghostty.TTY, ^tty, {:key, %Ghostty.KeyEvent{key: :c, mods: [:ctrl]}}} ->
          Ghostty.TTY.write(tty, "GOT:ctrl-c\r\n")

        {Ghostty.TTY, ^tty, {:key, %Ghostty.KeyEvent{utf8: utf8}}} when is_binary(utf8) ->
          Ghostty.TTY.write(tty, ["GOT:", utf8, "\r\n"])
          loop.(loop, [utf8 | seen])

        other ->
          Ghostty.TTY.write(tty, ["OTHER:", inspect(other), "\r\n"])
          loop.(loop, seen)
      after
        3_000 ->
          Ghostty.TTY.write(tty, "TIMEOUT\r\n")
      end
    end

    loop.(loop, [])
    '''
  end
end
