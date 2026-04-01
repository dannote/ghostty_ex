defmodule LiveTerminalWeb.TerminalLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)

    Ghostty.Terminal.write(term, "Welcome to Ghostty LiveTerminal!\r\n")
    Ghostty.Terminal.write(term, "$ \e[32mecho\e[0m hello\r\nhello\r\n$ ")

    socket = assign(socket, term: term)

    if connected?(socket) do
      {:ok, push_cells(socket)}
    else
      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <Ghostty.LiveTerminal.terminal id="term" cols={80} rows={24} />
    """
  end

  def handle_event("key", params, socket) do
    case Ghostty.LiveTerminal.handle_key(socket.assigns.term, params) do
      {:ok, data} ->
        Ghostty.Terminal.write(socket.assigns.term, data)

      :none ->
        :ok
    end

    {:noreply, push_cells(socket)}
  end

  defp push_cells(socket) do
    cells =
      socket.assigns.term
      |> Ghostty.Terminal.cells()
      |> Enum.map(fn row ->
        Enum.map(row, fn {char, fg, bg, flags} ->
          [char, color_to_list(fg), color_to_list(bg), flags]
        end)
      end)

    push_event(socket, "render", %{cells: cells})
  end

  defp color_to_list(nil), do: nil
  defp color_to_list({r, g, b}), do: [r, g, b]
end
