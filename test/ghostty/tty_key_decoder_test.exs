defmodule Ghostty.TTY.KeyDecoderTest do
  use ExUnit.Case, async: true

  alias Ghostty.TTY.KeyDecoder

  test "decodes navigation keys" do
    assert {:key, %{key: :arrow_left}} = KeyDecoder.decode("\e[D")
    assert {:key, %{key: :arrow_right}} = KeyDecoder.decode("\e[C")
    assert {:key, %{key: :arrow_up}} = KeyDecoder.decode("\e[A")
    assert {:key, %{key: :arrow_down}} = KeyDecoder.decode("\e[B")
    assert {:key, %{key: :delete}} = KeyDecoder.decode("\e[3~")
  end

  test "decodes control keys" do
    assert {:key, %{key: :enter}} = KeyDecoder.decode("\r")
    assert {:key, %{key: :tab}} = KeyDecoder.decode("\t")
    assert {:key, %{key: :escape}} = KeyDecoder.decode("\e")
    assert {:key, %{key: :backspace}} = KeyDecoder.decode("\u007F")
    assert {:key, %{key: :c, mods: [:ctrl]}} = KeyDecoder.decode(<<3>>)
  end

  test "decodes printable and alt-modified keys" do
    assert {:key, %{key: :a, utf8: "a", mods: []}} = KeyDecoder.decode("a")
    assert {:key, %{key: :a, utf8: "A", mods: []}} = KeyDecoder.decode("A")
    assert {:key, %{key: :digit_1, utf8: "1"}} = KeyDecoder.decode("1")
    assert {:key, %{key: :b, utf8: "b", mods: [:alt]}} = KeyDecoder.decode("\eb")
  end

  test "falls back to data for unknown sequences" do
    assert {:data, "\e[?2004h"} = KeyDecoder.decode("\e[?2004h")
  end
end
