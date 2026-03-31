defmodule Ghostty.Port do
  @moduledoc """
  Manages a subprocess with piped stdio.

  Wraps an Erlang port for subprocess I/O. This provides stdin/stdout
  piping but not a true pseudo-terminal — programs that require a TTY
  (like `vim` or `top`) won't work correctly.

  Output is sent as `{:data, binary}` messages to the calling process.
  Exit is reported as `{:exit, status}`.

  ## Examples

      {:ok, port} = Ghostty.Port.start_link(cmd: "/bin/echo", args: ["hello"])
      receive do: ({:data, data} -> IO.write(data))

  ## With a terminal

      {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
      {:ok, port} = Ghostty.Port.start_link(cmd: "/bin/ls", args: ["--color=always"])

      receive do
        {:data, data} -> Ghostty.Terminal.write(term, data)
      end

  """

  use GenServer

  @type option ::
          {:cmd, Path.t()}
          | {:args, [String.t()]}
          | {:env, [{String.t(), String.t()}]}
          | {:name, GenServer.name()}

  defstruct [:port, :owner]

  @doc """
  Starts a subprocess linked to the caller.

  Output and exit messages are sent to the calling process.

  ## Options

    * `:cmd` — command to run (default: `$SHELL` or `/bin/sh`)
    * `:args` — argument list (default: `[]`)
    * `:env` — environment as `[{"KEY", "VALUE"}]` (default: `[{"TERM", "xterm-256color"}]`)
    * `:name` — GenServer name registration

  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])
    init_opts = Keyword.put(init_opts, :owner, self())
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc "Returns a child spec for use in supervision trees."
  def child_spec(opts) do
    id = Keyword.get(opts, :id, Keyword.get(opts, :name, __MODULE__))

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000
    }
  end

  @doc "Writes data to the subprocess stdin."
  @spec write(GenServer.server(), iodata()) :: :ok
  def write(port, data) do
    GenServer.call(port, {:write, IO.iodata_to_binary(data)})
  end

  @doc "Closes the subprocess."
  @spec close(GenServer.server()) :: :ok
  def close(port) do
    GenServer.stop(port)
  end

  @impl true
  def init(opts) do
    cmd = Keyword.get(opts, :cmd, System.get_env("SHELL") || "/bin/sh")
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, [{"TERM", "xterm-256color"}])
    owner = Keyword.fetch!(opts, :owner)

    env_charlist = Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    port =
      Elixir.Port.open({:spawn_executable, cmd}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, args},
        {:env, env_charlist}
      ])

    {:ok, %__MODULE__{port: port, owner: owner}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.port && Elixir.Port.info(state.port), do: Elixir.Port.close(state.port)
  end

  @impl true
  def handle_call({:write, data}, _from, state) do
    Elixir.Port.command(state.port, data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    send(state.owner, {:data, data})
    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    send(state.owner, {:exit, status})
    {:stop, :normal, state}
  end
end
