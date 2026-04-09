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

    Run `mix igniter.install ghostty` in your Phoenix app to vendor
    `ghostty.js` into `assets/vendor/ghostty.js` and wire
    `GhosttyTerminal` into `assets/js/app.js`.

    """
    use Phoenix.Component

    attr(:id, :string, required: true)
    attr(:cols, :integer, default: 80)
    attr(:rows, :integer, default: 24)
    attr(:fit, :boolean, default: false)
    attr(:autofocus, :boolean, default: false)
    attr(:class, :string, default: "")
    attr(:rest, :global)

    @doc """
    Renders a terminal container `<div>` with the `GhosttyTerminal` JS hook.

    This is a stateless function component. For a stateful LiveComponent
    that handles key events internally, use `Ghostty.LiveTerminal.Component`.

    Supports global HTML attributes via `:rest`.
    """
    def terminal(assigns) do
      ~H"""
      <div
        id={@id}
        class={@class}
        phx-hook="GhosttyTerminal"
        phx-update="ignore"
        data-cols={@cols}
        data-rows={@rows}
        data-fit={to_string(@fit)}
        data-autofocus={to_string(@autofocus)}
        style="font-family: monospace; line-height: 1.2;"
        {@rest}
      >
        <textarea data-ghostty-input="true" autofocus={@autofocus} aria-label="Terminal input"></textarea>
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
    Writes committed browser text input to the terminal.

    This is intended for paste and IME composition commits.
    """
    @spec handle_text(GenServer.server(), binary()) :: :ok
    def handle_text(term, data) when is_binary(data) do
      Ghostty.Terminal.write(term, data)
    end

    @doc """
    Parses browser mouse event params into a `Ghostty.MouseEvent`.

    Returns a `Ghostty.MouseEvent` struct or `:none` for invalid events.
    """
    @spec mouse_event_from_params(map()) :: Ghostty.MouseEvent.t() | :none
    def mouse_event_from_params(%{"action" => action, "x" => x, "y" => y} = params) do
      with {:ok, mouse_action} <- mouse_action_from_param(action),
           {:ok, button} <- mouse_button_from_param(Map.get(params, "button")),
           {:ok, x} <- float_from_param(x),
           {:ok, y} <- float_from_param(y) do
        %Ghostty.MouseEvent{
          action: mouse_action,
          button: button,
          mods: mods_from_params(params),
          x: x,
          y: y
        }
      else
        _ -> :none
      end
    end

    def mouse_event_from_params(_params), do: :none

    @doc """
    Converts a browser mouse event into an encoded terminal escape sequence.
    """
    @spec handle_mouse(GenServer.server(), map()) :: {:ok, binary()} | :none
    def handle_mouse(term, params) do
      case mouse_event_from_params(params) do
        :none -> :none
        event -> Ghostty.Terminal.input_mouse(term, event)
      end
    end

    @doc """
    Resizes the terminal and optional PTY to the given dimensions.
    """
    @spec handle_resize(GenServer.server(), pos_integer(), pos_integer(), GenServer.server() | nil) ::
            :ok
    def handle_resize(term, cols, rows, pty \\ nil) do
      Ghostty.Terminal.resize(term, cols, rows)

      if pty do
        Ghostty.PTY.resize(pty, cols, rows)
      end

      :ok
    end

    @doc """
    Encodes a terminal focus change event.
    """
    @spec handle_focus(boolean()) :: {:ok, binary()} | :none
    def handle_focus(gained?) do
      Ghostty.Terminal.encode_focus(gained?)
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
      |> cells_to_payload()
    end

    @doc """
    Returns JSON-safe cursor metadata for the visible viewport.
    """
    @spec cursor_payload(GenServer.server()) :: map()
    def cursor_payload(term) do
      term
      |> Ghostty.Terminal.cursor_state()
      |> Map.update!(:color, &color_to_list/1)
    end

    @doc """
    Returns JSON-safe mouse reporting mode metadata.
    """
    @spec mouse_payload(GenServer.server()) :: map()
    def mouse_payload(term) do
      Ghostty.Terminal.mouse_modes(term)
    end

    @doc """
    Returns a render payload map for `push_event/3`.

    Includes the component `id` so the JS hook can filter events
    when multiple terminals share a LiveView.
    """
    @spec render_payload(String.t(), GenServer.server()) :: map()
    def render_payload(id, term) do
      %{cells: cells, cursor: cursor, mouse: mouse, scrollbar: scrollbar, focus_reporting: focus_reporting} =
        Ghostty.Terminal.render_state(term)

      %{
        id: id,
        cells: cells_to_payload(cells),
        cursor: cursor |> Map.update!(:color, &color_to_list/1),
        mouse: mouse,
        scrollbar: scrollbar,
        focus_reporting: focus_reporting
      }
    end

    @doc """
    Pushes a `"ghostty:render"` event with the current terminal cells.

    The payload includes the element `id` for multi-terminal filtering.
    """
    @spec push_render(Phoenix.LiveView.Socket.t(), String.t(), GenServer.server()) ::
            Phoenix.LiveView.Socket.t()
    def push_render(socket, id, term) do
      Phoenix.LiveView.push_event(socket, "ghostty:render", render_payload(id, term))
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

    defp cells_to_payload(cells) do
      Enum.map(cells, fn row ->
        Enum.map(row, fn {char, fg, bg, flags} ->
          [char, color_to_list(fg), color_to_list(bg), flags]
        end)
      end)
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

    defp mouse_action_from_param("press"), do: {:ok, :press}
    defp mouse_action_from_param("release"), do: {:ok, :release}
    defp mouse_action_from_param("motion"), do: {:ok, :motion}
    defp mouse_action_from_param(_action), do: :error

    defp mouse_button_from_param(nil), do: {:ok, nil}
    defp mouse_button_from_param("left"), do: {:ok, :left}
    defp mouse_button_from_param("right"), do: {:ok, :right}
    defp mouse_button_from_param("middle"), do: {:ok, :middle}
    defp mouse_button_from_param("four"), do: {:ok, :four}
    defp mouse_button_from_param("five"), do: {:ok, :five}
    defp mouse_button_from_param(_button), do: :error

    defp float_from_param(value) when is_float(value), do: {:ok, value}
    defp float_from_param(value) when is_integer(value), do: {:ok, value / 1}

    defp float_from_param(value) when is_binary(value) do
      case Float.parse(value) do
        {parsed, ""} -> {:ok, parsed}
        _ -> :error
      end
    end

    defp float_from_param(_value), do: :error
  end
end
