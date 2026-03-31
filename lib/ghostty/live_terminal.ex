if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Ghostty.LiveTerminal do
    @moduledoc """
    Phoenix LiveView component for rendering a terminal in the browser.

    Requires `phoenix_live_view` as a dependency.

    ## Usage

        # In your LiveView
        def mount(_params, _session, socket) do
          {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
          {:ok, assign(socket, term: term)}
        end

        def render(assigns) do
          ~H\"\"\"
          <Ghostty.LiveTerminal.terminal id="term" term={@term} />
          \"\"\"
        end

        def handle_event("key", params, socket) do
          Ghostty.LiveTerminal.handle_key(socket.assigns.term, params)
          {:noreply, push_cells(socket)}
        end

        defp push_cells(socket) do
          cells = Ghostty.Terminal.cells(socket.assigns.term)
          push_event(socket, "render", %{cells: cells})
        end

    ## JavaScript hook

    Add the hook from `priv/static/ghostty.js` to your LiveView socket:

        import { GhosttyTerminal } from "ghostty/priv/static/ghostty"
        let liveSocket = new LiveSocket("/live", Socket, {
          hooks: { GhosttyTerminal }
        })

    """
    use Phoenix.Component

    attr(:id, :string, required: true)
    attr(:cols, :integer, default: 80)
    attr(:rows, :integer, default: 24)
    attr(:class, :string, default: "")

    @doc "Renders a terminal container with the LiveView hook attached."
    def terminal(assigns) do
      ~H"""
      <div
        id={@id}
        class={@class}
        phx-hook="GhosttyTerminal"
        data-cols={@cols}
        data-rows={@rows}
        style="font-family: monospace; line-height: 1.2;"
      >
      </div>
      """
    end

    @doc """
    Converts a LiveView key event into a `Ghostty.KeyEvent` and encodes it.

    Returns `{:ok, binary}` with the escape sequence, or `:none`.
    """
    def handle_key(term, %{"key" => key} = params) do
      mods =
        []
        |> then(fn m -> if params["shiftKey"], do: [:shift | m], else: m end)
        |> then(fn m -> if params["ctrlKey"], do: [:ctrl | m], else: m end)
        |> then(fn m -> if params["altKey"], do: [:alt | m], else: m end)
        |> then(fn m -> if params["metaKey"], do: [:super | m], else: m end)

      ghostty_key = js_key_to_atom(key)

      if ghostty_key == :unidentified do
        :none
      else
        event = %Ghostty.KeyEvent{
          action: :press,
          key: ghostty_key,
          mods: mods,
          utf8: if(String.length(key) == 1, do: key)
        }

        Ghostty.Terminal.input_key(term, event)
      end
    end

    defp js_key_to_atom(key) when byte_size(key) == 1 do
      cond do
        key >= "a" and key <= "z" -> String.to_existing_atom(key)
        key >= "A" and key <= "Z" -> String.to_existing_atom(String.downcase(key))
        key >= "0" and key <= "9" -> String.to_existing_atom("digit_#{key}")
        true -> special_key(key)
      end
    end

    defp js_key_to_atom(key), do: special_key(key)

    @special_keys %{
      "Enter" => :enter,
      "Backspace" => :backspace,
      "Tab" => :tab,
      "Escape" => :escape,
      "ArrowUp" => :arrow_up,
      "ArrowDown" => :arrow_down,
      "ArrowLeft" => :arrow_left,
      "ArrowRight" => :arrow_right,
      "Delete" => :delete,
      "Home" => :home,
      "End" => :end,
      "PageUp" => :page_up,
      "PageDown" => :page_down,
      "Insert" => :insert,
      " " => :space,
      "F1" => :f1,
      "F2" => :f2,
      "F3" => :f3,
      "F4" => :f4,
      "F5" => :f5,
      "F6" => :f6,
      "F7" => :f7,
      "F8" => :f8,
      "F9" => :f9,
      "F10" => :f10,
      "F11" => :f11,
      "F12" => :f12
    }

    defp special_key(key), do: Map.get(@special_keys, key, :unidentified)
  end
end
