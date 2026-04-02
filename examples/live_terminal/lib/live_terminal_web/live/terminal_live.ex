defmodule LiveTerminalWeb.TerminalLive do
  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    socket =
      assign(socket,
        term: nil,
        pty: nil,
        banner?: !!params["banner"],
        command: params["cmd"]
      )

    if connected?(socket) do
      {:ok, start_terminal(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="terminal-page">
      <section class="terminal-shell">
        <header class="grid gap-2.5 text-slate-100">
          <div class="flex flex-wrap items-center gap-2.5">
            <span class="terminal-kicker terminal-kicker-primary">Ghostty LiveTerminal</span>
            <span class="terminal-kicker terminal-kicker-success">/bin/bash over PTY</span>
          </div>

          <div class="grid gap-1.5">
            <h1 class="m-0 text-4xl font-bold tracking-tight text-slate-100 sm:text-5xl">
              Real bash session in Phoenix LiveView
            </h1>
            <p class="m-0 max-w-3xl text-base leading-7 text-slate-300 sm:text-lg">
              The browser hook renders Ghostty cells, the LiveComponent handles key events, and a real PTY runs bash behind the scenes.
            </p>
          </div>
        </header>

        <article class="terminal-window">
          <div class="terminal-window-bar">
            <div class="flex items-center gap-2">
              <span class="terminal-dot bg-rose-300"></span>
              <span class="terminal-dot bg-amber-200"></span>
              <span class="terminal-dot bg-emerald-300"></span>
            </div>

            <div class="font-mono text-sm font-medium text-slate-400">
              bash --noprofile --norc -i
            </div>
          </div>

          <div class="min-h-[420px] p-0">
            <%= if @term do %>
              <.live_component
                module={Ghostty.LiveTerminal.Component}
                id="term"
                term={@term}
                pty={@pty}
                class="live-terminal-shell"
              />
            <% else %>
              <div
                id="term-loading"
                class="flex min-h-[420px] items-center justify-center font-mono text-sm font-medium text-slate-300"
              >
                Connecting terminal...
              </div>
            <% end %>
          </div>
        </article>
      </section>
    </main>
    """
  end

  @impl true
  def handle_info({:data, data}, socket) do
    Ghostty.Terminal.write(socket.assigns.term, data)
    refresh_terminal()
    Process.send_after(self(), :refresh_terminal, 25)
    {:noreply, socket}
  end

  def handle_info({:pty_write, data}, socket) do
    Ghostty.PTY.write(socket.assigns.pty, data)
    {:noreply, socket}
  end

  def handle_info(:bell, socket), do: {:noreply, socket}

  def handle_info({:exit, _status}, socket), do: {:noreply, socket}

  def handle_info(:refresh_terminal, socket) do
    refresh_terminal()
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if pty = socket.assigns[:pty] do
      Ghostty.PTY.close(pty)
    end

    :ok
  catch
    :exit, _ -> :ok
  end

  defp start_terminal(socket) do
    {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)

    {:ok, pty} =
      Ghostty.PTY.start_link(
        cmd: "/bin/bash",
        args: bash_args(socket.assigns.command),
        cols: 80,
        rows: 24
      )

    if socket.assigns.banner? do
      colored = IO.ANSI.green() <> "Welcome to Ghostty!" <> IO.ANSI.reset() <> "\r\n"
      Ghostty.Terminal.write(term, colored)
    end

    assign(socket, term: term, pty: pty)
  end

  defp bash_args(nil), do: ["--noprofile", "--norc", "-i"]

  defp bash_args(command) do
    ["-lc", command <> "; exec /bin/bash --noprofile --norc -i"]
  end

  defp refresh_terminal do
    send_update(Ghostty.LiveTerminal.Component, id: "term", refresh: true)
  end
end
