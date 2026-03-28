defmodule Ghostty.KeyEvent do
  @moduledoc """
  Represents a keyboard input event for the terminal.

  ## Examples

      %Ghostty.KeyEvent{action: :press, key: :c, mods: [:ctrl]}
      %Ghostty.KeyEvent{action: :press, key: :enter}
      %Ghostty.KeyEvent{action: :press, key: :a, utf8: "a"}

  """

  @type action :: :press | :release | :repeat

  @type key ::
          :a | :b | :c | :d | :e | :f | :g | :h | :i | :j | :k | :l | :m
          | :n | :o | :p | :q | :r | :s | :t | :u | :v | :w | :x | :y | :z
          | :digit_0 | :digit_1 | :digit_2 | :digit_3 | :digit_4
          | :digit_5 | :digit_6 | :digit_7 | :digit_8 | :digit_9
          | :enter | :tab | :backspace | :delete | :escape | :space
          | :arrow_up | :arrow_down | :arrow_left | :arrow_right
          | :home | :end | :page_up | :page_down | :insert
          | :f1 | :f2 | :f3 | :f4 | :f5 | :f6
          | :f7 | :f8 | :f9 | :f10 | :f11 | :f12
          | :minus | :equal | :bracket_left | :bracket_right
          | :backslash | :semicolon | :quote | :comma | :period | :slash
          | :backquote

  @type modifier :: :shift | :ctrl | :alt | :super

  @type t :: %__MODULE__{
          action: action(),
          key: key(),
          mods: [modifier()],
          utf8: String.t() | nil,
          unshifted_codepoint: non_neg_integer() | nil
        }

  defstruct action: :press,
            key: nil,
            mods: [],
            utf8: nil,
            unshifted_codepoint: nil
end
