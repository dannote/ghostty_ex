defmodule Ghostty.TTY.Winch do
  @moduledoc false

  @behaviour :gen_event

  @impl true
  def init({_owner, tty, ref}), do: {:ok, %{tty: tty, ref: ref}}

  @impl true
  def handle_event(:sigwinch, state) do
    send(state.tty, {:resize, state.ref})
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def handle_call(_request, state), do: {:ok, :ok, state}

  @impl true
  def handle_info(_message, state), do: {:ok, state}
end
