defmodule Ghostty.TTY.KeyDecoder do
  @moduledoc """
  Decodes bytes read from a local terminal into `Ghostty.KeyEvent` values.

  This decoder intentionally covers the portable baseline used by terminal apps:
  printable text, control keys, common CSI navigation keys, and Alt-modified
  printable keys. More advanced protocols can be added here without changing
  application runtimes.
  """

  alias Ghostty.KeyEvent

  @type decoded :: {:key, KeyEvent.t()} | {:data, binary()}

  @spec decode(binary()) :: decoded()
  def decode("\e[A"), do: key(:arrow_up)
  def decode("\e[B"), do: key(:arrow_down)
  def decode("\e[C"), do: key(:arrow_right)
  def decode("\e[D"), do: key(:arrow_left)
  def decode("\e[H"), do: key(:home)
  def decode("\e[F"), do: key(:end)
  def decode("\e[1~"), do: key(:home)
  def decode("\e[4~"), do: key(:end)
  def decode("\e[3~"), do: key(:delete)
  def decode("\e[2~"), do: key(:insert)
  def decode("\e[5~"), do: key(:page_up)
  def decode("\e[6~"), do: key(:page_down)
  def decode("\eOP"), do: key(:f1)
  def decode("\eOQ"), do: key(:f2)
  def decode("\eOR"), do: key(:f3)
  def decode("\eOS"), do: key(:f4)
  def decode("\r"), do: key(:enter)
  def decode("\n"), do: key(:enter)
  def decode("\t"), do: key(:tab)
  def decode("\e"), do: key(:escape)
  def decode("\u007F"), do: key(:backspace)
  def decode("\b"), do: key(:backspace)
  def decode(<<3>>), do: key(:c, mods: [:ctrl])

  def decode("\e[" <> _rest = sequence), do: {:data, sequence}
  def decode("\eO" <> _rest = sequence), do: {:data, sequence}

  def decode("\e" <> utf8) when byte_size(utf8) > 0 do
    case printable_key(utf8, [:alt]) do
      {:key, _event} = decoded -> decoded
      :error -> {:data, "\e" <> utf8}
    end
  end

  def decode(utf8) when is_binary(utf8) do
    case printable_key(utf8, []) do
      {:key, _event} = decoded -> decoded
      :error -> {:data, utf8}
    end
  end

  defp key(key, opts \\ []) do
    {:key,
     %KeyEvent{
       action: :press,
       key: key,
       mods: Keyword.get(opts, :mods, []),
       utf8: Keyword.get(opts, :utf8),
       unshifted_codepoint: Keyword.get(opts, :unshifted_codepoint)
     }}
  end

  defp printable_key(utf8, mods) do
    if String.printable?(utf8) and not String.match?(utf8, ~r/[\p{C}]/u) do
      key(printable_key_atom(utf8), mods: mods, utf8: utf8, unshifted_codepoint: codepoint(utf8))
    else
      :error
    end
  end

  defp printable_key_atom(" "), do: :space
  defp printable_key_atom("-"), do: :minus
  defp printable_key_atom("="), do: :equal
  defp printable_key_atom("["), do: :bracket_left
  defp printable_key_atom("]"), do: :bracket_right
  defp printable_key_atom("\\"), do: :backslash
  defp printable_key_atom(";"), do: :semicolon
  defp printable_key_atom("'"), do: :quote
  defp printable_key_atom(","), do: :comma
  defp printable_key_atom("."), do: :period
  defp printable_key_atom("/"), do: :slash
  defp printable_key_atom("`"), do: :backquote
  defp printable_key_atom(<<digit>>) when digit in ?0..?9, do: String.to_atom("digit_#{<<digit>>}")
  defp printable_key_atom(<<letter>>) when letter in ?a..?z, do: String.to_atom(<<letter>>)

  defp printable_key_atom(<<letter>>) when letter in ?A..?Z,
    do: (letter + 32) |> List.wrap() |> to_string() |> String.to_atom()

  defp printable_key_atom(_utf8), do: :unidentified

  defp codepoint(<<codepoint::utf8, _rest::binary>>), do: codepoint
end
