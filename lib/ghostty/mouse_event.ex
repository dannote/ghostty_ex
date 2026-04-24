defmodule Ghostty.MouseEvent do
  @moduledoc """
  Represents a mouse input event for the terminal.

  ## Examples

      %Ghostty.MouseEvent{action: :press, button: :left, x: 50.0, y: 40.0}
      %Ghostty.MouseEvent{action: :release, button: :left, x: 50.0, y: 40.0}
      %Ghostty.MouseEvent{action: :motion, x: 55.0, y: 42.0}

  """

  @type action :: :press | :release | :motion

  @type button ::
          :left
          | :right
          | :middle
          | :four
          | :five
          | nil

  @type modifier :: :shift | :ctrl | :alt | :super

  @type t :: %__MODULE__{
          action: action(),
          button: button(),
          mods: [modifier()],
          x: float(),
          y: float()
        }

  defstruct action: :press,
            button: :left,
            mods: [],
            x: 0.0,
            y: 0.0

  @action_map %{press: 0, release: 1, motion: 2}

  @button_map %{left: 1, right: 2, middle: 3, four: 4, five: 5}

  @doc false
  def action_to_int(action), do: Map.fetch(@action_map, action)

  @doc false
  def button_to_int(nil), do: {:ok, 0}

  def button_to_int(button), do: Map.fetch(@button_map, button)

  @doc false
  defdelegate to_bitmask(mods), to: Ghostty.Mods
end
