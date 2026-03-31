defmodule Ghostty.Mods do
  @moduledoc false

  import Bitwise

  @mod_bits %{shift: 1, ctrl: 2, alt: 4, super: 8}

  @doc false
  def to_bitmask(mods) do
    Enum.reduce(mods, 0, fn mod, acc ->
      bit = Map.get(@mod_bits, mod) || raise ArgumentError, "unknown modifier: #{inspect(mod)}"
      acc ||| bit
    end)
  end

  defdelegate mods_to_bitmask(mods), to: __MODULE__, as: :to_bitmask
end
