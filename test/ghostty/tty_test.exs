defmodule Ghostty.TTYTest do
  use ExUnit.Case, async: false

  alias Ghostty.TTY

  test "size returns a terminal-shaped tuple" do
    {cols, rows} = TTY.size()
    assert is_integer(cols) and cols > 0
    assert is_integer(rows) and rows > 0
  end

  test "child spec is supervision friendly" do
    assert %{start: {TTY, :start_link, [_opts]}, restart: :temporary} = TTY.child_spec(owner: self())
  end

  test "starts without raw mode in non-interactive test processes" do
    assert {:ok, tty} = TTY.start_link(owner: self(), raw: false)
    assert :ok = TTY.write(tty, "")
    GenServer.stop(tty)
  end

  test "emits NIF resize notifications as public resize events" do
    assert {:ok, tty} = TTY.start_link(owner: self(), raw: false)

    send(tty, {:tty_resize, 60, 20})
    assert_receive {TTY, ^tty, {:resize, 60, 20}}

    send(tty, {:tty_resize, 60, 20})
    refute_receive {TTY, ^tty, {:resize, 60, 20}}, 50

    GenServer.stop(tty)
  end

  test "winch handler ids can be registered independently" do
    {:ok, events} = :gen_event.start_link()
    first_ref = make_ref()
    second_ref = make_ref()
    tty = self()

    :ok = :gen_event.add_handler(events, {TTY.Winch, first_ref}, {self(), tty, first_ref})
    :ok = :gen_event.add_handler(events, {TTY.Winch, second_ref}, {self(), tty, second_ref})

    :gen_event.notify(events, :sigwinch)

    assert_receive {:resize, ^first_ref}
    assert_receive {:resize, ^second_ref}

    :ok = :gen_event.delete_handler(events, {TTY.Winch, first_ref}, :ok)
    :gen_event.notify(events, :sigwinch)

    refute_receive {:resize, ^first_ref}, 50
    assert_receive {:resize, ^second_ref}
  end
end
