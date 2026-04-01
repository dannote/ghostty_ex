defmodule Ghostty.PTYTest do
  use ExUnit.Case, async: false

  describe "start_link/1" do
    test "captures command output" do
      {:ok, pty} =
        Ghostty.PTY.start_link(
          cmd: "/bin/sh",
          args: ["-c", "printf hello_from_pty; sleep 0.2"]
        )

      assert_receive {:data, data}, 1_000
      assert data =~ "hello_from_pty"
      assert_close(pty)
    end

    test "writes to child stdin" do
      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/cat")

      Ghostty.PTY.write(pty, "echo_this\n")
      assert_receive {:data, data}, 1_000
      assert data =~ "echo_this"
      assert_close(pty)
    end

    test "child sees a real TTY" do
      {:ok, pty} =
        Ghostty.PTY.start_link(
          cmd: "/usr/bin/python3",
          args: [
            "-c",
            "import os, sys, time; print('tty' if os.isatty(0) else 'not_tty'); sys.stdout.flush(); time.sleep(0.2)"
          ]
        )

      assert_receive {:data, data}, 1_000
      assert data =~ "tty"
      refute data =~ "not_tty"
      assert_close(pty)
    end

    test "passes argv entries without shell joining" do
      {:ok, pty} =
        Ghostty.PTY.start_link(
          cmd: "/usr/bin/python3",
          args: [
            "-c",
            "import sys, time; print(repr(sys.argv)); sys.stdout.flush(); time.sleep(0.2)",
            "hello world"
          ]
        )

      assert_receive {:data, data}, 1_000
      assert data =~ "['-c', 'hello world']"
      assert_close(pty)
    end

    test "resize does not crash" do
      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/cat")
      assert :ok = Ghostty.PTY.resize(pty, 120, 40)
      assert_close(pty)
    end
  end

  defp assert_close(pty) do
    ref = Process.monitor(pty)
    assert :ok = Ghostty.PTY.close(pty)
    assert_receive {:DOWN, ^ref, :process, ^pty, _reason}, 1_000
  end
end
