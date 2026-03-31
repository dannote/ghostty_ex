defmodule Ghostty.Terminal.CellTest do
  use ExUnit.Case, async: true

  alias Ghostty.Terminal
  alias Ghostty.Terminal.Cell

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
end
