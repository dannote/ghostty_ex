defmodule Ghostty.TTYTest do
  use ExUnit.Case, async: true

  alias Ghostty.TTY

  test "size returns a terminal-shaped tuple" do
    {cols, rows} = TTY.size()
    assert is_integer(cols) and cols > 0
    assert is_integer(rows) and rows > 0
  end

  test "child spec is supervision friendly" do
    assert %{start: {TTY, :start_link, [_opts]}, restart: :temporary} = TTY.child_spec(owner: self())
  end
end
