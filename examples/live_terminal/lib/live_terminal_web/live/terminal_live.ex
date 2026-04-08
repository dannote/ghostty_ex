defmodule LiveTerminalWeb.TerminalLive do
  use Phoenix.LiveView

  @default_fit true
  @startup_timeout 1_250
  @term_env "TERM=xterm-256color"
  @color_term_env "COLORTERM=truecolor"
  @shell_env "BASH_SILENCE_DEPRECATION_WARNING=1"

  @impl true
  def mount(params, _session, socket) do
    %{banner?: banner?, fit?: fit?, command: command} = initial_options(params)

    socket =
      assign(socket,
        term: nil,
        pty: nil,
        component_id: "term-1",
        session_version: 1,
        banner?: banner?,
        fit?: fit?,
        command: command,
        banner_input?: banner?,
        fit_input?: fit?,
        command_input: command || "",
        boot_output: "",
        pty_restart_attempts: 0,
        shell_prompt_seen?: false,
        startup_ref: nil
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
              bash --noprofile --rcfile demo.bashrc -i
            </div>
          </div>

          <div class="terminal-controls-wrap">
            <form id="demo-controls" phx-submit="restart_terminal" class="terminal-controls">
              <label class="terminal-field terminal-field-command" for="startup-command">
                <span class="terminal-field-label">Startup command</span>
                <input
                  id="startup-command"
                  name="command"
                  type="text"
                  value={@command_input}
                  placeholder="printf '\\033[31mred\\033[0m'; echo hello"
                  class="terminal-input"
                  autocomplete="off"
                  spellcheck="false"
                />
              </label>

              <div class="terminal-control-row">
                <label class="terminal-toggle" for="show-banner">
                  <input id="show-banner" type="checkbox" name="banner" checked={@banner_input?} />
                  <span>Welcome banner</span>
                </label>

                <label class="terminal-toggle" for="fit-terminal">
                  <input id="fit-terminal" type="checkbox" name="fit" checked={@fit_input?} />
                  <span>Fit to panel</span>
                </label>

                <span class="terminal-env-pill"><%= term_env() %></span>
              </div>

              <div class="terminal-actions">
                <button id="restart-session" type="submit" class="terminal-button terminal-button-primary">
                  Restart session
                </button>

                <button
                  id="preset-blank-shell"
                  type="button"
                  class="terminal-button"
                  phx-click="run_preset"
                  phx-value-command=""
                >
                  Blank shell
                </button>

                <button
                  id="preset-hello-demo"
                  type="button"
                  class="terminal-button"
                  phx-click="run_preset"
                  phx-value-command={hello_demo_command()}
                >
                  Hello demo
                </button>

                <button
                  id="preset-color-demo"
                  type="button"
                  class="terminal-button"
                  phx-click="run_preset"
                  phx-value-command={color_demo_command()}
                >
                  Color demo
                </button>

                <button
                  id="preset-mouse-demo"
                  type="button"
                  class="terminal-button"
                  phx-click="run_preset"
                  phx-value-command={mouse_demo_command()}
                >
                  Mouse mode demo
                </button>
              </div>
            </form>
          </div>

          <div class="min-h-[420px] p-0">
            <%= if @term do %>
              <.live_component
                module={Ghostty.LiveTerminal.Component}
                id={@component_id}
                term={@term}
                pty={@pty}
                fit={@fit?}
                autofocus={false}
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
  def handle_event("restart_terminal", params, socket) do
    socket =
      socket
      |> assign_control_inputs(params)
      |> apply_control_inputs()
      |> restart_terminal_session()

    {:noreply, socket}
  end

  def handle_event("run_preset", %{"command" => command}, socket) do
    socket =
      socket
      |> assign(command_input: command)
      |> apply_control_inputs()
      |> restart_terminal_session()

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:terminal_ready, component_id, cols, rows},
        %{assigns: %{component_id: component_id, pty: nil}} = socket
      ) do
    {:noreply, start_pty_session(socket, cols, rows)}
  end

  def handle_info({:terminal_ready, _id, _cols, _rows}, socket), do: {:noreply, socket}

  def handle_info({:data, data}, socket) do
    Ghostty.Terminal.write(socket.assigns.term, data)

    socket =
      socket
      |> append_boot_output(data)
      |> maybe_mark_shell_prompt()

    refresh_terminal(socket)
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
    stop_session(socket)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp initial_options(params) do
    %{
      banner?: truthy_param?(params["banner"]),
      fit?: truthy_param?(Map.get(params, "fit", if(@default_fit, do: "1", else: "0"))),
      command: normalize_command(params["cmd"])
    }
  end

  defp start_terminal(socket) do
    {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)

    socket
    |> assign(term: term, pty: nil, boot_output: "", shell_prompt_seen?: false, startup_ref: nil)
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

  defp restart_terminal_session(socket) do
    socket
    |> stop_session()
    |> bump_component_id()
    |> start_terminal()
  end

  defp stop_session(socket) do
    if pty = socket.assigns[:pty] do
      safe_stop(pty)
    end

    if term = socket.assigns[:term] do
      safe_stop(term)
    end

    assign(socket, term: nil, pty: nil, startup_ref: nil)
  end

  defp safe_stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, _ -> :ok
  end

  defp bump_component_id(socket) do
    session_version = socket.assigns.session_version + 1

    assign(socket,
      component_id: component_id(session_version),
      session_version: session_version,
      pty_restart_attempts: 0
    )
  end

  defp component_id(session_version), do: "term-#{session_version}"

  defp assign_control_inputs(socket, params) do
    assign(socket,
      banner_input?: checkbox_enabled?(params, "banner", socket.assigns.banner_input?),
      fit_input?: checkbox_enabled?(params, "fit", socket.assigns.fit_input?),
      command_input: Map.get(params, "command", socket.assigns.command_input)
    )
  end

  defp apply_control_inputs(socket) do
    assign(socket,
      banner?: socket.assigns.banner_input?,
      fit?: socket.assigns.fit_input?,
      command: normalize_command(socket.assigns.command_input)
    )
  end

  defp checkbox_enabled?(params, key, _current), do: Map.has_key?(params, key)

  defp normalize_command(nil), do: nil

  defp normalize_command(command) do
    case String.trim(command) do
      "" -> nil
      _ -> command
    end
  end

  defp truthy_param?(value), do: value not in [nil, "", "0", "false"]

  defp start_command, do: "/usr/bin/env"

  defp interactive_start_args do
    [@term_env, @color_term_env, @shell_env, "/bin/bash" | bash_args()]
  end

  defp command_start_args(command) do
    rcfile = shell_escape(demo_rcfile())

    [
      @term_env,
      @color_term_env,
      @shell_env,
      "/bin/bash",
      "--noprofile",
      "-lc",
      "source #{rcfile}; #{command}; exec /usr/bin/env #{@term_env} #{@color_term_env} #{@shell_env} /bin/bash --noprofile --rcfile #{rcfile} -i"
    ]
  end

  defp bash_args, do: ["--noprofile", "--rcfile", demo_rcfile(), "-i"]

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
    if socket.assigns.pty do
      safe_stop(socket.assigns.pty)
    end

    Ghostty.Terminal.reset(socket.assigns.term)

    socket =
      socket
      |> assign(pty: nil, pty_restart_attempts: socket.assigns.pty_restart_attempts + 1)
      |> write_banner()

    refresh_terminal(socket)

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

  defp refresh_terminal(socket) do
    send_update(Ghostty.LiveTerminal.Component, id: socket.assigns.component_id, refresh: true)
  end

  defp term_env, do: @term_env

  defp demo_rcfile, do: Application.app_dir(:live_terminal, "priv/demo.bashrc")

  defp shell_escape(value), do: "'" <> String.replace(value, "'", "'\"'\"'") <> "'"

  defp hello_demo_command, do: "echo hello"

  defp color_demo_command do
    ~S(printf '\033[31mred\033[0m \033[32mgreen\033[0m \033[34mblue\033[0m\n')
  end

  defp mouse_demo_command do
    ~S(printf '\033[31mred\033[0m \033[32mgreen\033[0m \033[34mblue\033[0m\n\033[?1000h\033[?1006h'; echo hello)
  end
end
