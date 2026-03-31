defmodule Ghostty.PortTest do
  use ExUnit.Case, async: true

  describe "start_link/1" do
    test "captures command output" do
      {:ok, port} =
        Ghostty.Port.start_link(
          cmd: "/bin/echo",
          args: ["hello_from_port"]
        )

      assert_receive {:data, data}, 2_000
      assert data =~ "hello_from_port"
      assert_receive {:exit, _status}, 2_000

      ref = Process.monitor(port)
      assert_receive {:DOWN, ^ref, :process, ^port, _}, 1_000
    end

    test "writes to subprocess stdin" do
      {:ok, port} = Ghostty.Port.start_link(cmd: "/bin/cat")

      Ghostty.Port.write(port, "echo_this\n")
      assert_receive {:data, data}, 2_000
      assert data =~ "echo_this"
      Ghostty.Port.close(port)
    end
  end
end
