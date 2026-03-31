defmodule Ghostty.TerminalTest do
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

    test "rejects zero cols" do
      Process.flag(:trap_exit, true)
      assert {:error, {:invalid_option, msg}} = Terminal.start_link(cols: 0)
      assert msg =~ "cols"
    end

    test "rejects negative rows" do
      Process.flag(:trap_exit, true)
      assert {:error, {:invalid_option, msg}} = Terminal.start_link(rows: -1)
      assert msg =~ "rows"
    end

    test "rejects non-integer cols" do
      Process.flag(:trap_exit, true)
      assert {:error, {:invalid_option, msg}} = Terminal.start_link(cols: "abc")
      assert msg =~ "cols"
    end

    test "rejects negative max_scrollback" do
      Process.flag(:trap_exit, true)
      assert {:error, {:invalid_option, msg}} = Terminal.start_link(max_scrollback: -1)
      assert msg =~ "max_scrollback"
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
      assert {:ok, "\r"} = Terminal.input_key(term, %Ghostty.KeyEvent{key: :enter})
      GenServer.stop(term)
    end

    test "encodes letter key with utf8" do
      {:ok, term} = Terminal.start_link()

      assert {:ok, "a"} =
               Terminal.input_key(term, %Ghostty.KeyEvent{
                 key: :a,
                 utf8: "a",
                 unshifted_codepoint: ?a
               })

      GenServer.stop(term)
    end

    test "encodes ctrl+c" do
      {:ok, term} = Terminal.start_link()

      assert {:ok, <<3>>} =
               Terminal.input_key(term, %Ghostty.KeyEvent{
                 key: :c,
                 mods: [:ctrl],
                 unshifted_codepoint: ?c
               })

      GenServer.stop(term)
    end

    test "encodes arrow up" do
      {:ok, term} = Terminal.start_link()
      assert {:ok, "\e[A"} = Terminal.input_key(term, %Ghostty.KeyEvent{key: :arrow_up})
      GenServer.stop(term)
    end

    test "encodes escape key" do
      {:ok, term} = Terminal.start_link()
      assert {:ok, "\e"} = Terminal.input_key(term, %Ghostty.KeyEvent{key: :escape})
      GenServer.stop(term)
    end

    test "exits on unknown key" do
      Process.flag(:trap_exit, true)
      {:ok, term} = Terminal.start_link()

      catch_exit(Terminal.input_key(term, %Ghostty.KeyEvent{key: :nonexistent}))
    end

    test "exits on unknown action" do
      Process.flag(:trap_exit, true)
      {:ok, term} = Terminal.start_link()

      catch_exit(Terminal.input_key(term, %Ghostty.KeyEvent{key: :a, action: :bogus}))
    end
  end

  describe "input_mouse/2" do
    test "returns :none when mouse tracking disabled" do
      {:ok, term} = Terminal.start_link()

      assert :none =
               Terminal.input_mouse(term, %Ghostty.MouseEvent{
                 action: :press,
                 button: :left,
                 x: 10.0,
                 y: 5.0
               })

      GenServer.stop(term)
    end

    test "exits on unknown button" do
      Process.flag(:trap_exit, true)
      {:ok, term} = Terminal.start_link()

      catch_exit(Terminal.input_mouse(term, %Ghostty.MouseEvent{button: :nonexistent}))
    end
  end

  describe "encode_focus/1" do
    test "encodes focus gained" do
      assert {:ok, "\e[I"} = Terminal.encode_focus(true)
    end

    test "encodes focus lost" do
      assert {:ok, "\e[O"} = Terminal.encode_focus(false)
    end
  end

  describe "effects" do
    test "bell message on BEL character" do
      {:ok, term} = Terminal.start_link()
      Terminal.write(term, "\a")
      assert_receive :bell, 100
      GenServer.stop(term)
    end

    test "pty_write message on DA query" do
      {:ok, term} = Terminal.start_link()
      Terminal.write(term, "\e[c")
      assert_receive {:pty_write, _data}, 100
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
      Process.flag(:trap_exit, true)
      {:ok, term} = Terminal.start_link()
      ref = Process.monitor(term)
      Process.exit(term, :kill)
      assert_receive {:DOWN, ^ref, :process, ^term, :killed}
    end
  end
end
