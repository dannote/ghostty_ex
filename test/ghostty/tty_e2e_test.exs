defmodule Ghostty.TTYE2ETest do
  use ExUnit.Case, async: false

  alias Ghostty.PTY

  @child_event_timeout_ms 3_000
  @parent_event_timeout_ms 5_000
  @poll_interval_ms 20

  @tag :tmp_dir
  test "TTY receives resize events inside a real PTY", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "tty_resize.exs")
    File.write!(script, resize_child_script())

    ebin_paths = Path.wildcard(Path.expand("_build/test/lib/*/ebin"))
    path_args = Enum.flat_map(ebin_paths, &["-pa", &1])

    {:ok, pty} = PTY.start_link(cmd: System.find_executable("elixir"), args: path_args ++ [script], cols: 100, rows: 24)

    try do
      output = wait_until("START:100x24", "")
      PTY.resize(pty, 60, 20)

      output = wait_until("RESIZE:60x20", output)
      refute output =~ "TIMEOUT"
    after
      if Process.alive?(pty), do: Process.exit(pty, :kill)
    end
  end

  @tag :tmp_dir
  test "TTY receives raw key events inside a real PTY", %{tmp_dir: tmp_dir} do
    script = Path.join(tmp_dir, "tty_echo.exs")
    File.write!(script, child_script())

    ebin_paths = Path.wildcard(Path.expand("_build/test/lib/*/ebin"))
    path_args = Enum.flat_map(ebin_paths, &["-pa", &1])

    {:ok, pty} = PTY.start_link(cmd: System.find_executable("elixir"), args: path_args ++ [script], cols: 100, rows: 24)

    try do
      output = wait_until("WAITING", "")

      PTY.write(pty, "a")
      output = wait_until("GOT:a", output)
      output = wait_until("WAITING:again", output)

      PTY.write(pty, <<3>>)
      output = wait_until("GOT:ctrl-c", output)

      refute output =~ "BREAK:"
      refute output =~ "TIMEOUT"
    after
      if Process.alive?(pty), do: Process.exit(pty, :kill)
    end
  end

  defp wait_until(expected, output) do
    deadline = System.monotonic_time(:millisecond) + @parent_event_timeout_ms
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
        @poll_interval_ms ->
          if System.monotonic_time(:millisecond) < deadline do
            collect_until(expected, output, deadline)
          else
            flunk("Timed out waiting for #{inspect(expected)}. Output:\n#{output}")
          end
      end
    end
  end

  defp resize_child_script do
    timeout_ms = @child_event_timeout_ms

    """
    {:ok, _} = Application.ensure_all_started(:ghostty)
    {:ok, tty} = Ghostty.TTY.start_link(owner: self(), backend: :nif, takeover: true)
    {cols, rows} = Ghostty.TTY.size()
    Ghostty.TTY.write(tty, "START:\#{cols}x\#{rows}\\r\\n")

    receive do
      {Ghostty.TTY, ^tty, {:resize, cols, rows}} ->
        Ghostty.TTY.write(tty, "RESIZE:\#{cols}x\#{rows}\\r\\n")
    after
      #{timeout_ms} ->
        {cols, rows} = Ghostty.TTY.size()
        Ghostty.TTY.write(tty, "TIMEOUT:\#{cols}x\#{rows}\\r\\n")
    end
    """
  end

  defp child_script do
    timeout_ms = @child_event_timeout_ms

    """
    {:ok, _} = Application.ensure_all_started(:ghostty)
    {:ok, tty} = Ghostty.TTY.start_link(owner: self(), backend: :nif, takeover: true)
    Ghostty.TTY.write(tty, "READY\\r\\n")

    loop = fn loop, seen ->
      waiting = if seen == [], do: "WAITING", else: "WAITING:again"
      Ghostty.TTY.write(tty, [waiting, "\\r\\n"])

      receive do
        {Ghostty.TTY, ^tty, {:key, %Ghostty.KeyEvent{key: :c, mods: [:ctrl]}}} ->
          Ghostty.TTY.write(tty, "GOT:ctrl-c\\r\\n")

        {Ghostty.TTY, ^tty, {:key, %Ghostty.KeyEvent{utf8: utf8}}} when is_binary(utf8) ->
          Ghostty.TTY.write(tty, ["GOT:", utf8, "\\r\\n"])
          loop.(loop, [utf8 | seen])

        _other ->
          loop.(loop, seen)
      after
        #{timeout_ms} ->
          Ghostty.TTY.write(tty, "TIMEOUT\\r\\n")
      end
    end

    loop.(loop, [])
    """
  end
end
