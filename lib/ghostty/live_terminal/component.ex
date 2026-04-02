if Code.ensure_loaded?(Phoenix.LiveComponent) do
  defmodule Ghostty.LiveTerminal.Component do
    @moduledoc """
    Stateful LiveComponent for rendering a terminal in the browser.

    Handles keyboard events internally — no `handle_event` wiring
    needed in the parent LiveView. The parent owns the terminal
    and optionally a PTY; this component owns the UI interaction.

    ## Usage

        # In your LiveView mount:
        {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
        {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/bash", cols: 80, rows: 24)
        {:ok, assign(socket, term: term, pty: pty)}

        # In your LiveView template:
        <.live_component
          module={Ghostty.LiveTerminal.Component}
          id="term"
          term={@term}
          pty={@pty}
        />

        # Forward PTY output to the terminal and trigger a refresh:
        def handle_info({:data, data}, socket) do
          Ghostty.Terminal.write(socket.assigns.term, data)
          send_update(Ghostty.LiveTerminal.Component, id: "term", refresh: true)
          {:noreply, socket}
        end

    ## Assigns

      * `:id` — required
      * `:term` — required, a `Ghostty.Terminal` pid
      * `:pty` — optional, a `Ghostty.PTY` pid; key input is written here when present
      * `:cols` — terminal width (default: `80`)
      * `:rows` — terminal height (default: `24`)
      * `:class` — CSS class for the container div (default: `""`)

    Global HTML attributes (`data-*`, `aria-*`, etc.) are passed through.

    ## Refreshing

    To push updated cells after writing to the terminal from the parent,
    use `send_update/3`:

        Ghostty.Terminal.write(socket.assigns.term, data)
        send_update(Ghostty.LiveTerminal.Component, id: "term", refresh: true)

    The component also pushes an initial render automatically when
    the LiveView socket is connected.
    """
    use Phoenix.LiveComponent

    @impl true
    def update(assigns, socket) do
      first_mount? = not Map.has_key?(socket.assigns, :term)

      socket =
        socket
        |> assign(assigns)
        |> assign_new(:pty, fn -> nil end)
        |> assign_new(:cols, fn -> 80 end)
        |> assign_new(:rows, fn -> 24 end)
        |> assign_new(:class, fn -> "" end)

      socket =
        if first_mount? or assigns[:refresh] do
          push_render(socket)
        else
          socket
        end

      {:ok, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div
        id={@id}
        class={@class}
        phx-hook="GhosttyTerminal"
        phx-target={@myself}
        data-cols={@cols}
        data-rows={@rows}
        style="font-family: monospace; line-height: 1.2;"
      >
      </div>
      """
    end

    @impl true
    def handle_event("key", params, socket) do
      case Ghostty.LiveTerminal.handle_key(socket.assigns.term, params) do
        {:ok, data} -> write_data(socket, data)
        :none -> :ok
      end

      {:noreply, push_render(socket)}
    end

    @impl true
    def handle_event("text", %{"data" => data}, socket) when is_binary(data) do
      if data != "" do
        if socket.assigns.pty do
          Ghostty.PTY.write(socket.assigns.pty, data)
        else
          Ghostty.LiveTerminal.handle_text(socket.assigns.term, data)
        end
      end

      {:noreply, push_render(socket)}
    end

    @impl true
    def handle_event("mouse", params, socket) do
      case Ghostty.LiveTerminal.handle_mouse(socket.assigns.term, params) do
        {:ok, data} -> write_data(socket, data)
        :none -> :ok
      end

      {:noreply, socket}
    end

    @impl true
    def handle_event("focus", %{"focused" => focused}, socket) do
      case Ghostty.LiveTerminal.handle_focus(focused) do
        {:ok, data} -> write_data(socket, data)
        :none -> :ok
      end

      {:noreply, push_render(socket)}
    end

    @impl true
    def handle_event("refresh", _params, socket) do
      {:noreply, push_render(socket)}
    end

    defp write_data(socket, data) do
      if socket.assigns.pty do
        Ghostty.PTY.write(socket.assigns.pty, data)
      else
        Ghostty.Terminal.write(socket.assigns.term, data)
      end
    end

    defp push_render(socket) do
      Ghostty.LiveTerminal.push_render(socket, socket.assigns.id, socket.assigns.term)
    end
  end
end
