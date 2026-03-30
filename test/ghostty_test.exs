defmodule GhosttyTest do
  use ExUnit.Case, async: true

  alias Ghostty.Terminal
  alias Ghostty.Terminal.Cell

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

  describe "input_key/2" do
    test "encodes enter key" do
      {:ok, term} = Terminal.start_link()
      result = Terminal.input_key(term, %Ghostty.KeyEvent{key: :enter})
      assert {:ok, seq} = result
      assert seq == "\r"
      GenServer.stop(term)
    end

    test "encodes letter key with utf8" do
      {:ok, term} = Terminal.start_link()
      result = Terminal.input_key(term, %Ghostty.KeyEvent{key: :a, utf8: "a", unshifted_codepoint: ?a})
      assert {:ok, seq} = result
      assert seq == "a"
      GenServer.stop(term)
    end

    test "encodes ctrl+c" do
      {:ok, term} = Terminal.start_link()
      result = Terminal.input_key(term, %Ghostty.KeyEvent{key: :c, mods: [:ctrl], unshifted_codepoint: ?c})
      assert {:ok, seq} = result
      assert seq == <<3>>
      GenServer.stop(term)
    end

    test "encodes arrow up" do
      {:ok, term} = Terminal.start_link()
      result = Terminal.input_key(term, %Ghostty.KeyEvent{key: :arrow_up})
      assert {:ok, seq} = result
      assert seq == "\e[A"
      GenServer.stop(term)
    end

    test "encodes escape key" do
      {:ok, term} = Terminal.start_link()
      result = Terminal.input_key(term, %Ghostty.KeyEvent{key: :escape})
      assert {:ok, seq} = result
      assert seq == "\e"
      GenServer.stop(term)
    end
  end

  describe "input_mouse/2" do
    test "returns :none when mouse tracking disabled" do
      {:ok, term} = Terminal.start_link()
      result = Terminal.input_mouse(term, %Ghostty.MouseEvent{action: :press, button: :left, x: 10.0, y: 5.0})
      assert result == :none
      GenServer.stop(term)
    end
  end

  describe "encode_focus/1" do
    test "encodes focus gained" do
      assert {:ok, seq} = Terminal.encode_focus(true)
      assert seq == "\e[I"
    end

    test "encodes focus lost" do
      assert {:ok, seq} = Terminal.encode_focus(false)
      assert seq == "\e[O"
    end
  end

  describe "effects" do
    test "bell callback fires on BEL character" do
      test_pid = self()
      {:ok, term} = Terminal.start_link(subscriber: test_pid)
      Terminal.write(term, "\a")
      assert_receive :bell, 100
      GenServer.stop(term)
    end

    test "write_pty callback fires on DA query" do
      test_pid = self()
      {:ok, term} = Terminal.start_link(subscriber: test_pid)
      # Send a Device Attributes query (CSI c) — triggers a write-back response
      Terminal.write(term, "\e[c")
      assert_receive {:pty_write, _data}, 100
      GenServer.stop(term)
    end
  end

  describe "cells/1" do
    test "returns grid structure" do
      {:ok, term} = Terminal.start_link(cols: 10, rows: 3)
      Terminal.write(term, "Hi")
      cells = Terminal.cells(term)
      assert is_list(cells)
      assert length(cells) == 3
      [first_row | _] = cells
      assert length(first_row) == 10
      GenServer.stop(term)
    end

    test "cell contains grapheme text" do
      {:ok, term} = Terminal.start_link(cols: 10, rows: 3)
      Terminal.write(term, "AB")
      [[a, b | _] | _] = Terminal.cells(term)
      assert Cell.grapheme(a) == "A"
      assert Cell.grapheme(b) == "B"
      GenServer.stop(term)
    end

    test "cell flags for bold text" do
      {:ok, term} = Terminal.start_link(cols: 20, rows: 3)
      Terminal.write(term, "\e[1mBold\e[0m")
      [[cell | _] | _] = Terminal.cells(term)
      assert Cell.bold?(cell)
      refute Cell.italic?(cell)
      GenServer.stop(term)
    end

    test "colored text has fg color" do
      {:ok, term} = Terminal.start_link(cols: 20, rows: 3)
      Terminal.write(term, "\e[38;2;255;0;128mX\e[0m")
      [[cell | _] | _] = Terminal.cells(term)
      assert Cell.fg(cell) == {255, 0, 128}
      GenServer.stop(term)
    end

    test "blank cells have nil colors and empty grapheme" do
      {:ok, term} = Terminal.start_link(cols: 10, rows: 3)
      [[_ | rest] | _] = Terminal.cells(term)
      blank = List.last(rest)
      assert Cell.blank?(blank)
      GenServer.stop(term)
    end
  end

  describe "Ghostty.PTY" do
    test "captures command output" do
      test_pid = self()

      {:ok, pty} =
        Ghostty.PTY.start_link(
          cmd: "/bin/echo",
          args: ["hello_from_pty"],
          subscriber: test_pid
        )

      assert_receive {:data, data}, 2_000
      assert data =~ "hello_from_pty"
      assert_receive {:exit, _status}, 2_000
      refute Process.alive?(pty)
    end

    test "writes to subprocess stdin" do
      test_pid = self()

      {:ok, pty} =
        Ghostty.PTY.start_link(
          cmd: "/bin/cat",
          subscriber: test_pid
        )

      Ghostty.PTY.write(pty, "echo_this\n")
      assert_receive {:data, data}, 2_000
      assert data =~ "echo_this"
      Ghostty.PTY.close(pty)
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
      Process.flag(:trap_exit, true)
      {:ok, term} = Terminal.start_link()
      ref = Process.monitor(term)
      Process.exit(term, :kill)
      assert_receive {:DOWN, ^ref, :process, ^term, :killed}
    end
  end
end
