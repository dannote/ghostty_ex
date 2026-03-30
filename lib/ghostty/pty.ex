defmodule Ghostty.PTY do
  @moduledoc """
  Manages a subprocess with piped stdio.

  Wraps an Erlang port for basic subprocess I/O. This provides
  stdin/stdout piping but not a true pseudo-terminal — programs that
  require a TTY (like `vim` or `top`) won't work correctly. For those,
  a `forkpty()`-based NIF would be needed.

  Works well for non-interactive commands, scripts, and programs that
  detect they're not on a TTY and fall back to line-buffered output.

  ## Examples

      {:ok, pty} = Ghostty.PTY.start_link(
        cmd: "/bin/echo",
        args: ["hello"],
        on_data: fn data -> IO.write(data) end
      )

  ## With a terminal

      {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
      {:ok, pty} = Ghostty.PTY.start_link(
        cmd: "/bin/ls",
        args: ["--color=always"],
        on_data: fn data -> Ghostty.Terminal.write(term, data) end
      )

  """

  use GenServer

  @type option ::
          {:cmd, Path.t()}
          | {:args, [String.t()]}
          | {:env, [{String.t(), String.t()}]}
          | {:on_data, (binary() -> any())}
          | {:on_exit, (non_neg_integer() -> any())}
          | {:name, GenServer.name()}

  defstruct [:port, :on_data, :on_exit]

  @doc """
  Starts a PTY process linked to the caller.

  ## Options

    * `:cmd` — command to run (default: `$SHELL` or `/bin/sh`)
    * `:args` — argument list (default: `[]`)
    * `:env` — environment as `[{"KEY", "VALUE"}]` (default: `[{"TERM", "xterm-256color"}]`)
    * `:on_data` — callback `(binary -> any)` for stdout/stderr data
    * `:on_exit` — callback `(integer -> any)` for process exit
    * `:name` — GenServer name registration

  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc "Writes data to the subprocess stdin."
  @spec write(GenServer.server(), iodata()) :: :ok
  def write(pty, data) do
    GenServer.call(pty, {:write, IO.iodata_to_binary(data)})
  end

  @doc "Closes the subprocess."
  @spec close(GenServer.server()) :: :ok
  def close(pty) do
    GenServer.stop(pty)
  end

  @impl true
  def init(opts) do
    cmd = Keyword.get(opts, :cmd, System.get_env("SHELL") || "/bin/sh")
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, [{"TERM", "xterm-256color"}])

    env_charlist = Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    port =
      Port.open({:spawn_executable, cmd}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, args},
        {:env, env_charlist}
      ])

    {:ok,
     %__MODULE__{
       port: port,
       on_data: Keyword.get(opts, :on_data),
       on_exit: Keyword.get(opts, :on_exit)
     }}
  end

  @impl true
  def handle_call({:write, data}, _from, state) do
    Port.command(state.port, data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    if state.on_data, do: state.on_data.(data)
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    if state.on_exit, do: state.on_exit.(status)
    {:stop, :normal, state}
  end
end
