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
          :a
          | :b
          | :c
          | :d
          | :e
          | :f
          | :g
          | :h
          | :i
          | :j
          | :k
          | :l
          | :m
          | :n
          | :o
          | :p
          | :q
          | :r
          | :s
          | :t
          | :u
          | :v
          | :w
          | :x
          | :y
          | :z
          | :digit_0
          | :digit_1
          | :digit_2
          | :digit_3
          | :digit_4
          | :digit_5
          | :digit_6
          | :digit_7
          | :digit_8
          | :digit_9
          | :enter
          | :tab
          | :backspace
          | :delete
          | :escape
          | :space
          | :arrow_up
          | :arrow_down
          | :arrow_left
          | :arrow_right
          | :home
          | :end
          | :page_up
          | :page_down
          | :insert
          | :f1
          | :f2
          | :f3
          | :f4
          | :f5
          | :f6
          | :f7
          | :f8
          | :f9
          | :f10
          | :f11
          | :f12
          | :minus
          | :equal
          | :bracket_left
          | :bracket_right
          | :backslash
          | :semicolon
          | :quote
          | :comma
          | :period
          | :slash
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

  # GhosttyKey enum values from key/event.h (0-indexed, sequential)
  @key_map %{
    unidentified: 0,
    backquote: 1,
    backslash: 2,
    bracket_left: 3,
    bracket_right: 4,
    comma: 5,
    digit_0: 6,
    digit_1: 7,
    digit_2: 8,
    digit_3: 9,
    digit_4: 10,
    digit_5: 11,
    digit_6: 12,
    digit_7: 13,
    digit_8: 14,
    digit_9: 15,
    equal: 16,
    a: 20,
    b: 21,
    c: 22,
    d: 23,
    e: 24,
    f: 25,
    g: 26,
    h: 27,
    i: 28,
    j: 29,
    k: 30,
    l: 31,
    m: 32,
    n: 33,
    o: 34,
    p: 35,
    q: 36,
    r: 37,
    s: 38,
    t: 39,
    u: 40,
    v: 41,
    w: 42,
    x: 43,
    y: 44,
    z: 45,
    minus: 46,
    period: 47,
    quote: 48,
    semicolon: 49,
    slash: 50,
    backspace: 53,
    enter: 58,
    space: 63,
    tab: 64,
    delete: 68,
    end: 69,
    home: 71,
    insert: 72,
    page_down: 73,
    page_up: 74,
    arrow_down: 75,
    arrow_left: 76,
    arrow_right: 77,
    arrow_up: 78,
    escape: 120,
    f1: 121,
    f2: 122,
    f3: 123,
    f4: 124,
    f5: 125,
    f6: 126,
    f7: 127,
    f8: 128,
    f9: 129,
    f10: 130,
    f11: 131,
    f12: 132
  }

  @action_map %{release: 0, press: 1, repeat: 2}

  @doc false
  def action_to_int(action) do
    Map.get(@action_map, action) ||
      raise ArgumentError, "unknown key action: #{inspect(action)}"
  end

  @doc false
  def key_to_int(key) do
    Map.get(@key_map, key) ||
      raise ArgumentError, "unknown key: #{inspect(key)}"
  end

  @doc false
  defdelegate mods_to_bitmask(mods), to: Ghostty.Mods
end
