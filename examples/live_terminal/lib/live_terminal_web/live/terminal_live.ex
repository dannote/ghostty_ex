defmodule LiveTerminalWeb.TerminalLive do
  use Phoenix.LiveView

  @startup_timeout 1_250

  @impl true
  def mount(params, _session, socket) do
    socket =
      assign(socket,
        term: nil,
        pty: nil,
        banner?: !!params["banner"],
        command: params["cmd"],
        boot_output: "",
        pty_restart_attempts: 0,
        shell_prompt_seen?: false,
        startup_ref: nil,
        fit?: Map.get(params, "fit", "1") != "0"
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
                fit={@fit?}
                autofocus={true}
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
  def handle_info({:ghostty_terminal_ready, "term", cols, rows}, %{assigns: %{pty: nil}} = socket) do
    {:noreply, start_pty_session(socket, cols, rows)}
  end

  def handle_info({:ghostty_terminal_ready, _id, _cols, _rows}, socket), do: {:noreply, socket}

  def handle_info({:data, data}, socket) do
    Ghostty.Terminal.write(socket.assigns.term, data)

    socket =
      socket
      |> append_boot_output(data)
      |> maybe_mark_shell_prompt()

    refresh_terminal()
    {:noreply, socket}
  end

  def handle_info({:pty_write, data}, %{assigns: %{pty: pty}} = socket) when not is_nil(pty) do
    Ghostty.PTY.write(pty, data)
    {:noreply, socket}
  end

  def handle_info({:pty_write, _data}, socket), do: {:noreply, socket}

  def handle_info(
        {:startup_timeout, startup_ref},
        %{assigns: %{startup_ref: startup_ref, shell_prompt_seen?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_info(
        {:startup_timeout, startup_ref},
        %{assigns: %{startup_ref: startup_ref, pty_restart_attempts: attempts}} = socket
      )
      when attempts >= 1 do
    {:noreply, socket}
  end

  def handle_info({:startup_timeout, startup_ref}, %{assigns: %{startup_ref: startup_ref}} = socket) do
    {:noreply, restart_pty(socket)}
  end

  def handle_info({:startup_timeout, _startup_ref}, socket), do: {:noreply, socket}

  def handle_info(:bell, socket), do: {:noreply, socket}

  def handle_info({:exit, _status}, socket) do
    {:noreply, assign(socket, pty: nil)}
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

    socket
    |> assign(term: term, pty: nil)
    |> write_banner()
  end

  defp start_pty_session(socket, cols, rows) do
    Ghostty.Terminal.resize(socket.assigns.term, cols, rows)
    {:ok, pty} = start_pty(socket.assigns.command, cols, rows)

    startup_ref = make_ref()
    Process.send_after(self(), {:startup_timeout, startup_ref}, @startup_timeout)

    assign(socket,
      pty: pty,
      boot_output: "",
      shell_prompt_seen?: false,
      startup_ref: startup_ref
    )
  end

  defp start_command, do: "/usr/bin/env"

  defp interactive_start_args do
    [
      "BASH_SILENCE_DEPRECATION_WARNING=1",
      "PS1=ghostty$ ",
      "/bin/bash"
      | bash_args()
    ]
  end

  defp command_start_args(command) do
    [
      "BASH_SILENCE_DEPRECATION_WARNING=1",
      "/bin/bash",
      "--noprofile",
      "--norc",
      "-lc",
      command <>
        "; exec /usr/bin/env BASH_SILENCE_DEPRECATION_WARNING=1 PS1='ghostty$ ' /bin/bash --noprofile --norc -i"
    ]
  end

  defp bash_args, do: ["--noprofile", "--norc", "-i"]

  defp append_boot_output(socket, data) do
    assign(socket, :boot_output, trim_boot_output(socket.assigns.boot_output <> data))
  end

  defp maybe_mark_shell_prompt(%{assigns: %{shell_prompt_seen?: true}} = socket), do: socket

  defp maybe_mark_shell_prompt(socket) do
    if prompt_seen?(socket.assigns.boot_output) do
      assign(socket, shell_prompt_seen?: true)
    else
      socket
    end
  end

  defp prompt_seen?(data) do
    String.match?(data, ~r/(^|\r?\n).*(ghostty\$ |[#$] )$/m)
  end

  defp trim_boot_output(data) do
    data
    |> String.slice(-512, 512)
    |> Kernel.||("")
  end

  defp restart_pty(socket) do
    Ghostty.Terminal.reset(socket.assigns.term)

    if socket.assigns.pty do
      Ghostty.PTY.close(socket.assigns.pty)
    end

    socket =
      socket
      |> assign(pty: nil, pty_restart_attempts: socket.assigns.pty_restart_attempts + 1)
      |> write_banner()

    refresh_terminal()

    {cols, rows} = Ghostty.Terminal.size(socket.assigns.term)
    start_pty_session(socket, cols, rows)
  end

  defp start_pty(nil, cols, rows) do
    Ghostty.PTY.start_link(
      cmd: start_command(),
      args: interactive_start_args(),
      cols: cols,
      rows: rows
    )
  end

  defp start_pty(command, cols, rows) do
    Ghostty.PTY.start_link(
      cmd: start_command(),
      args: command_start_args(command),
      cols: cols,
      rows: rows
    )
  end

  defp write_banner(socket) do
    if socket.assigns.banner? do
      colored = IO.ANSI.green() <> "Welcome to Ghostty!" <> IO.ANSI.reset() <> "\r\n"
      Ghostty.Terminal.write(socket.assigns.term, colored)
    end

    socket
  end

  defp refresh_terminal do
    send_update(Ghostty.LiveTerminal.Component, id: "term", refresh: true)
  end
end
