defmodule Ghostty.TestTest do
  use ExUnit.Case, async: true

  import Ghostty.Test

  @fixture Path.expand("../fixtures/ghostty_test/basic.txt", __DIR__)

  test "writes lines and asserts visible text" do
    {:ok, terminal} = term(cols: 20, rows: 4)

    terminal
    |> lines(["Hello", IO.ANSI.red(), "red", IO.ANSI.reset()])
    |> assert_text("Hello")
    |> assert_text("red")
    |> refute_text("missing")
  end

  test "asserts snapshots" do
    {:ok, terminal} = term(cols: 20, rows: 4)
    write(terminal, "Hello snapshot\r\n")

    assert_snap(terminal, @fixture)
  end

  test "encodes key events" do
    {:ok, terminal} = term()

    assert {:ok, bytes} = key(terminal, :enter)
    assert is_binary(bytes)
    assert key_bytes(:enter) == bytes
  end
end
