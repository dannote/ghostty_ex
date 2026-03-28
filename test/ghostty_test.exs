defmodule GhosttyTest do
  use ExUnit.Case, async: true

  alias Ghostty.Terminal

  describe "start_link/1" do
    test "creates a terminal with default dimensions" do
      {:ok, term} = Terminal.start_link()
      assert is_pid(term)
      GenServer.stop(term)
    end

    test "creates a terminal with custom dimensions" do
      {:ok, term} = Terminal.start_link(cols: 120, rows: 40)
      assert is_pid(term)
      GenServer.stop(term)
    end

    test "accepts a name option" do
      {:ok, _} = Terminal.start_link(name: :test_terminal)
      assert is_pid(Process.whereis(:test_terminal))
      GenServer.stop(:test_terminal)
    end
  end

  describe "write/2" do
    test "writes plain text" do
      {:ok, term} = Terminal.start_link()
      assert :ok = Terminal.write(term, "hello world")
      GenServer.stop(term)
    end

    test "writes VT escape sequences" do
      {:ok, term} = Terminal.start_link()
      assert :ok = Terminal.write(term, "Hello, \e[1mBold\e[0m World!\r\n")
      GenServer.stop(term)
    end

    test "accepts iodata" do
      {:ok, term} = Terminal.start_link()
      assert :ok = Terminal.write(term, ["hello", ?\s, "world"])
      GenServer.stop(term)
    end
  end

  describe "snapshot/2" do
    test "returns plain text snapshot" do
      {:ok, term} = Terminal.start_link(cols: 40, rows: 5)
      Terminal.write(term, "Hello World!\r\nLine 2\r\n")
      {:ok, text} = Terminal.snapshot(term)
      assert text =~ "Hello World!"
      assert text =~ "Line 2"
      GenServer.stop(term)
    end

    test "strips ANSI codes in plain format" do
      {:ok, term} = Terminal.start_link(cols: 40, rows: 5)
      Terminal.write(term, "\e[31mRed\e[0m \e[1mBold\e[0m\r\n")
      {:ok, text} = Terminal.snapshot(term, :plain)
      assert text =~ "Red Bold"
      refute text =~ "\e["
      GenServer.stop(term)
    end

    test "returns HTML snapshot" do
      {:ok, term} = Terminal.start_link(cols: 40, rows: 5)
      Terminal.write(term, "\e[31mRed\e[0m Text\r\n")
      {:ok, html} = Terminal.snapshot(term, :html)
      assert html =~ "Red"
      GenServer.stop(term)
    end

    test "returns VT snapshot" do
      {:ok, term} = Terminal.start_link(cols: 40, rows: 5)
      Terminal.write(term, "\e[31mRed\e[0m Text\r\n")
      {:ok, vt} = Terminal.snapshot(term, :vt)
      assert is_binary(vt)
      GenServer.stop(term)
    end
  end

  describe "resize/3" do
    test "resizes the terminal" do
      {:ok, term} = Terminal.start_link(cols: 80, rows: 24)
      assert :ok = Terminal.resize(term, 120, 40)
      GenServer.stop(term)
    end

    test "handles text reflow on resize" do
      {:ok, term} = Terminal.start_link(cols: 10, rows: 5)
      Terminal.write(term, "ABCDEFGHIJ")
      Terminal.resize(term, 5, 5)
      {:ok, text} = Terminal.snapshot(term)
      assert text =~ "ABCDE"
      GenServer.stop(term)
    end
  end

  describe "reset/1" do
    test "clears terminal state" do
      {:ok, term} = Terminal.start_link(cols: 40, rows: 5)
      Terminal.write(term, "Some content\r\n")
      Terminal.reset(term)
      {:ok, text} = Terminal.snapshot(term)
      assert String.trim(text) == ""
      GenServer.stop(term)
    end
  end

  describe "cursor/1" do
    test "returns cursor position" do
      {:ok, term} = Terminal.start_link(cols: 40, rows: 5)
      Terminal.write(term, "Hello")
      {col, row} = Terminal.cursor(term)
      assert col == 5
      assert row == 0
      GenServer.stop(term)
    end

    test "tracks cursor across lines" do
      {:ok, term} = Terminal.start_link(cols: 40, rows: 5)
      Terminal.write(term, "Line 1\r\nLine 2\r\n")
      {_col, row} = Terminal.cursor(term)
      assert row == 2
      GenServer.stop(term)
    end
  end

  describe "scroll/2" do
    test "scrolls viewport" do
      {:ok, term} = Terminal.start_link(cols: 40, rows: 3, max_scrollback: 100)

      for i <- 1..10 do
        Terminal.write(term, "Line #{i}\r\n")
      end

      assert :ok = Terminal.scroll(term, -3)
      GenServer.stop(term)
    end
  end

  describe "process lifecycle" do
    test "terminal is cleaned up when process stops" do
      {:ok, term} = Terminal.start_link()
      ref = Process.monitor(term)
      GenServer.stop(term)
      assert_receive {:DOWN, ^ref, :process, ^term, :normal}
    end

    test "terminal is cleaned up on crash" do
      {:ok, term} = Terminal.start_link()
      ref = Process.monitor(term)
      Process.exit(term, :kill)
      assert_receive {:DOWN, ^ref, :process, ^term, :killed}
    end
  end
end
