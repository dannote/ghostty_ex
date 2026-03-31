defmodule Ghostty.PTYTest do
  use ExUnit.Case, async: false

  describe "start_link/1" do
    test "captures command output" do
      {:ok, pty} =
        Ghostty.PTY.start_link(
          cmd: "/bin/echo",
          args: ["hello_from_pty"]
        )

      data = collect_data(2_000)
      assert data =~ "hello_from_pty"
      assert_receive {:exit, _status}, 2_000
      Ghostty.PTY.close(pty)
    end

    test "writes to child stdin" do
      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/cat")

      Ghostty.PTY.write(pty, "echo_this\n")
      data = collect_data(2_000)
      assert data =~ "echo_this"
      Ghostty.PTY.close(pty)
    end

    test "child sees a real TTY" do
      {:ok, pty} =
        Ghostty.PTY.start_link(
          cmd: "/bin/sh",
          args: ["-c", "test -t 0 && echo tty || echo not_tty"]
        )

      data = collect_data(2_000)
      assert data =~ "tty"
      refute data =~ "not_tty"
    end

    test "resize does not crash" do
      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/cat")
      assert :ok = Ghostty.PTY.resize(pty, 120, 40)
      Ghostty.PTY.close(pty)
    end
  end

  defp collect_data(timeout) do
    collect_data("", timeout)
  end

  defp collect_data(acc, timeout) do
    receive do
      {:data, chunk} -> collect_data(acc <> chunk, 200)
    after
      timeout -> acc
    end
  end
end
