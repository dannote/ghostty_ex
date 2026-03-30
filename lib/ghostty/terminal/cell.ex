defmodule Ghostty.Terminal.Cell do
  @moduledoc """
  Helpers for working with terminal cell tuples.

  Each cell is `{grapheme, fg, bg, flags}` where:

    * `grapheme` — UTF-8 binary (empty for blank cells)
    * `fg` / `bg` — `{r, g, b}` tuples or `nil`
    * `flags` — bitmask of style attributes

  ## Flag bits

  | Bit | Attribute     |
  |-----|---------------|
  | 0   | bold          |
  | 1   | italic        |
  | 2   | faint         |
  | 3   | underline     |
  | 4   | strikethrough |
  | 5   | inverse       |
  | 6   | blink         |
  | 7   | overline      |
  """

  import Bitwise

  @type color :: {0..255, 0..255, 0..255} | nil
  @type t :: {binary(), color(), color(), non_neg_integer()}

  @bold 1
  @italic 2
  @faint 4
  @underline 8
  @strikethrough 16
  @inverse 32
  @blink 64
  @overline 128

  @doc "Returns the grapheme string."
  @spec grapheme(t()) :: binary()
  def grapheme({char, _, _, _}), do: char

  @doc "Returns the foreground color or `nil`."
  @spec fg(t()) :: color()
  def fg({_, fg, _, _}), do: fg

  @doc "Returns the background color or `nil`."
  @spec bg(t()) :: color()
  def bg({_, _, bg, _}), do: bg

  @doc "Returns the raw flags bitmask."
  @spec flags(t()) :: non_neg_integer()
  def flags({_, _, _, flags}), do: flags

  @spec bold?(t()) :: boolean()
  def bold?({_, _, _, f}), do: (f &&& @bold) != 0

  @spec italic?(t()) :: boolean()
  def italic?({_, _, _, f}), do: (f &&& @italic) != 0

  @spec faint?(t()) :: boolean()
  def faint?({_, _, _, f}), do: (f &&& @faint) != 0

  @spec underline?(t()) :: boolean()
  def underline?({_, _, _, f}), do: (f &&& @underline) != 0

  @spec strikethrough?(t()) :: boolean()
  def strikethrough?({_, _, _, f}), do: (f &&& @strikethrough) != 0

  @spec inverse?(t()) :: boolean()
  def inverse?({_, _, _, f}), do: (f &&& @inverse) != 0

  @spec blink?(t()) :: boolean()
  def blink?({_, _, _, f}), do: (f &&& @blink) != 0

  @spec overline?(t()) :: boolean()
  def overline?({_, _, _, f}), do: (f &&& @overline) != 0

  @doc "Returns `true` if the cell is blank (empty grapheme, no styling)."
  @spec blank?(t()) :: boolean()
  def blank?({char, fg, bg, flags}), do: char == "" and fg == nil and bg == nil and flags == 0
end
