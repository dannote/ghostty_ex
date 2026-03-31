defmodule Ghostty.ExamplesTest do
  use ExUnit.Case, async: true

  alias Ghostty.Terminal

  describe "hello example" do
    test "write with ANSI colors and snapshot" do
      {:ok, term} = Terminal.start_link(cols: 60, rows: 10)
      Terminal.write(term, "Hello, \e[1;32mGhostty\e[0m!\r\n")
      {:ok, text} = Terminal.snapshot(term)
      assert text =~ "Hello, Ghostty!"
      {:ok, html} = Terminal.snapshot(term, :html)
      assert html =~ "Ghostty"
      GenServer.stop(term)
    end
  end

  describe "progress bar example" do
    test "carriage return overwrites produce final state only" do
      {:ok, term} = Terminal.start_link(cols: 60, rows: 5)

      for i <- 1..10 do
        Terminal.write(term, "\r#{i}0%")
      end

      Terminal.write(term, "\r\nDone\r\n")
      {:ok, text} = Terminal.snapshot(term)
      assert text =~ "100%"
      assert text =~ "Done"
      refute text =~ "50%"
      GenServer.stop(term)
    end
  end

  describe "reflow example" do
    test "text reflows on resize" do
      {:ok, term} = Terminal.start_link(cols: 20, rows: 5)
      Terminal.write(term, "ABCDEFGHIJKLMNOPQRST\r\n")
      {:ok, wide} = Terminal.snapshot(term)
      assert wide =~ "ABCDEFGHIJKLMNOPQRST"

      Terminal.resize(term, 10, 5)
      {:ok, narrow} = Terminal.snapshot(term)
      assert narrow =~ "ABCDEFGHIJ"
      assert narrow =~ "KLMNOPQRST"
      GenServer.stop(term)
    end
  end

  describe "supervised example" do
    test "named terminals in supervision tree" do
      children = [
        {Terminal, name: :ex_console, id: :ex_console, cols: 40, rows: 5},
        {Terminal, name: :ex_logs, id: :ex_logs, cols: 40, rows: 5}
      ]

      {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

      Terminal.write(:ex_console, "console\r\n")
      Terminal.write(:ex_logs, "log entry\r\n")

      {:ok, c} = Terminal.snapshot(:ex_console)
      {:ok, l} = Terminal.snapshot(:ex_logs)
      assert c =~ "console"
      assert l =~ "log entry"

      Supervisor.stop(sup)
    end
  end

  describe "diff example" do
    test "strip ANSI for clean diff" do
      {:ok, t1} = Terminal.start_link(cols: 80, rows: 10)
      {:ok, t2} = Terminal.start_link(cols: 80, rows: 10)

      Terminal.write(t1, "\e[32m3 tests, 0 failures\e[0m\r\n")
      Terminal.write(t2, "\e[31m3 tests, 1 failure\e[0m\r\n")

      {:ok, before} = Terminal.snapshot(t1)
      {:ok, after_} = Terminal.snapshot(t2)

      assert before =~ "0 failures"
      assert after_ =~ "1 failure"

      diff = String.myers_difference(before, after_)
      assert Keyword.has_key?(diff, :del)
      assert Keyword.has_key?(diff, :ins)

      GenServer.stop(t1)
      GenServer.stop(t2)
    end
  end

  describe "pool example" do
    test "concurrent ANSI stripping" do
      inputs = [
        "\e[31mError\e[0m\r\n",
        "\e[32mOK\e[0m\r\n",
        "\e[33mWarn\e[0m\r\n"
      ]

      results =
        inputs
        |> Task.async_stream(fn input ->
          {:ok, term} = Terminal.start_link(cols: 40, rows: 5)
          Terminal.write(term, input)
          {:ok, text} = Terminal.snapshot(term)
          GenServer.stop(term)
          String.trim(text)
        end)
        |> Enum.map(fn {:ok, text} -> text end)

      assert "Error" in results
      assert "OK" in results
      assert "Warn" in results
    end
  end
end
