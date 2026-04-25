defmodule Ghostty.PTYTest do
  use ExUnit.Case, async: false

  @pty_event_timeout_ms 3_000
  @poll_interval_ms 20

  describe "start_link/1" do
    test "captures command output" do
      {:ok, pty} =
        Ghostty.PTY.start_link(
          cmd: "/bin/sh",
          args: ["-c", "printf hello_from_pty; sleep 0.2"]
        )

      data = wait_until_output("hello_from_pty")
      assert data =~ "hello_from_pty"
      assert_close(pty)
    end

    test "writes to child stdin" do
      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/cat")

      Ghostty.PTY.write(pty, "echo_this\r")
      data = wait_until_output("echo_this")
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

      data = wait_until_output("tty")
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

      data = wait_until_output("['-c', 'hello world']")
      assert data =~ "['-c', 'hello world']"
      assert_close(pty)
    end

    test "resize does not crash" do
      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/cat")
      assert :ok = Ghostty.PTY.resize(pty, 120, 40)
      assert_close(pty)
    end

    test "accepts configurable reader start timeout" do
      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/cat", reader_start_timeout: @pty_event_timeout_ms)
      assert_close(pty)
    end

    test "rejects invalid reader start timeout" do
      Process.flag(:trap_exit, true)

      assert {:error, {:pty_open_failed, message}} =
               Ghostty.PTY.start_link(cmd: "/bin/cat", reader_start_timeout: -1)

      assert message =~ "reader_start_timeout"
    end
  end

  defp assert_close(pty) do
    ref = Process.monitor(pty)
    assert :ok = Ghostty.PTY.close(pty)
    assert_receive {:DOWN, ^ref, :process, ^pty, _reason}, @pty_event_timeout_ms
  end

  defp wait_until_output(expected) do
    deadline = System.monotonic_time(:millisecond) + @pty_event_timeout_ms
    collect_until_output(expected, "", deadline)
  end

  defp collect_until_output(expected, output, deadline) do
    if output =~ expected do
      output
    else
      receive do
        {:data, data} ->
          collect_until_output(expected, output <> data, deadline)

        {:exit, status} ->
          flunk("PTY exited with status #{inspect(status)} before output #{inspect(expected)}. Output:\n#{output}")
      after
        @poll_interval_ms ->
          if System.monotonic_time(:millisecond) < deadline do
            collect_until_output(expected, output, deadline)
          else
            flunk("Timed out waiting for output #{inspect(expected)}. Output:\n#{output}")
          end
      end
    end
  end
end
