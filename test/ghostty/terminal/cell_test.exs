defmodule Ghostty.Terminal.CellTest do
  use ExUnit.Case, async: true

  import Ghostty.Test

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
      {:ok, term} = term(cols: 10, rows: 3)
      write(term, "AB")
      assert_cell(term, {0, 0}, "A")
      assert_cell(term, {1, 0}, "B")
      GenServer.stop(term)
    end

    test "cell flags for bold text" do
      {:ok, term} = term(cols: 20, rows: 3)
      write(term, "\e[1mBold\e[0m")
      assert_cell(term, {0, 0}, "B", bold?: true, italic?: false)
      GenServer.stop(term)
    end

    test "colored text has fg color" do
      {:ok, term} = term(cols: 20, rows: 3)
      write(term, "\e[38;2;255;0;128mX\e[0m")
      assert_cell(term, {0, 0}, "X", fg: {255, 0, 128})
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
