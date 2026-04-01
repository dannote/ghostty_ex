defmodule LiveTerminalWeb.TerminalLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)

    Ghostty.Terminal.write(term, "Welcome to Ghostty LiveTerminal!\r\n")
    Ghostty.Terminal.write(term, "$ \e[32mecho\e[0m hello\r\nhello\r\n$ ")

    {:ok, assign(socket, term: term)}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={Ghostty.LiveTerminal.Component}
      id="term"
      term={@term}
      cols={80}
      rows={24}
    />
    """
  end
end
