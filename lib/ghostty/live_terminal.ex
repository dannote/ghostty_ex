if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Ghostty.LiveTerminal do
    @moduledoc """
    Low-level Phoenix LiveView helpers for terminal rendering.

    Provides utilities for translating browser keyboard events,
    building JSON-safe render payloads, and pushing terminal state
    to the client. Use these when you need full control over the
    LiveView wiring.

    For a higher-level drop-in component, see `Ghostty.LiveTerminal.Component`.

    ## JavaScript hook

    Add the hook from `priv/static/ghostty.js` to your LiveView socket:

        import { GhosttyTerminal } from "ghostty/priv/static/ghostty"

        let liveSocket = new LiveSocket("/live", Socket, {
          params: {_csrf_token: csrfToken},
          hooks: { GhosttyTerminal }
        })

    """
    use Phoenix.Component

    attr(:id, :string, required: true)
    attr(:cols, :integer, default: 80)
    attr(:rows, :integer, default: 24)
    attr(:class, :string, default: "")

    @doc """
    Renders a terminal container `<div>` with the `GhosttyTerminal` JS hook.

    This is a stateless function component. For a stateful LiveComponent
    that handles key events internally, use `Ghostty.LiveTerminal.Component`.
    """
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
    Parses browser key event params into a `Ghostty.KeyEvent`.

    Returns a `Ghostty.KeyEvent` struct or `:none` for unrecognized keys.

    ## Examples

        key_event_from_params(%{"key" => "Enter"})
        #=> %Ghostty.KeyEvent{action: :press, key: :enter}

        key_event_from_params(%{"key" => "Dead"})
        #=> :none

    """
    @spec key_event_from_params(map()) :: Ghostty.KeyEvent.t() | :none
    def key_event_from_params(%{"key" => key} = params) do
      ghostty_key = js_key_to_atom(key)

      if ghostty_key == :unidentified do
        :none
      else
        %Ghostty.KeyEvent{
          action: :press,
          key: ghostty_key,
          mods: mods_from_params(params),
          utf8: if(String.length(key) == 1, do: key)
        }
      end
    end

    @doc """
    Converts a browser key event into an encoded terminal escape sequence.

    Returns `{:ok, binary}` or `:none` for unrecognized keys.
    """
    @spec handle_key(GenServer.server(), map()) :: {:ok, binary()} | :none
    def handle_key(term, params) do
      case key_event_from_params(params) do
        :none -> :none
        event -> Ghostty.Terminal.input_key(term, event)
      end
    end

    @doc """
    Converts terminal cells into a JSON-safe nested list.

    Cell tuples `{grapheme, fg, bg, flags}` become `[grapheme, fg, bg, flags]`
    where colors are `[r, g, b]` or `nil`.
    """
    @spec cells_payload(GenServer.server()) :: [[list()]]
    def cells_payload(term) do
      term
      |> Ghostty.Terminal.cells()
      |> Enum.map(fn row ->
        Enum.map(row, fn {char, fg, bg, flags} ->
          [char, color_to_list(fg), color_to_list(bg), flags]
        end)
      end)
    end

    @doc """
    Returns a render payload map suitable for `push_event/3`.

        push_event(socket, "render", Ghostty.LiveTerminal.render_payload(term))
    """
    @spec render_payload(GenServer.server()) :: map()
    def render_payload(term) do
      %{cells: cells_payload(term)}
    end

    @doc """
    Pushes a `"render"` event with the current terminal cells to the client.
    """
    @spec push_render(Phoenix.LiveView.Socket.t(), GenServer.server()) ::
            Phoenix.LiveView.Socket.t()
    def push_render(socket, term) do
      Phoenix.LiveView.push_event(socket, "render", render_payload(term))
    end

    defp mods_from_params(params) do
      []
      |> then(fn m -> if params["shiftKey"], do: [:shift | m], else: m end)
      |> then(fn m -> if params["ctrlKey"], do: [:ctrl | m], else: m end)
      |> then(fn m -> if params["altKey"], do: [:alt | m], else: m end)
      |> then(fn m -> if params["metaKey"], do: [:super | m], else: m end)
    end

    defp color_to_list(nil), do: nil
    defp color_to_list({r, g, b}), do: [r, g, b]

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
