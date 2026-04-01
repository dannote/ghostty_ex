defmodule Ghostty.PTY do
  @moduledoc """
  Pseudo-terminal for running interactive programs.

  Uses `forkpty()` to create a real PTY — programs like `vim`, `top`,
  and `htop` work correctly. The child process gets a proper TTY with
  the requested dimensions.

  Output is sent as `{:data, binary}` messages to the calling process.
  Exit is reported as `{:exit, status}`.

  ## Examples

      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/bash")
      Ghostty.PTY.write(pty, "echo hello\\n")
      receive do: ({:data, data} -> IO.write(data))

  ## With a terminal

      {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
      {:ok, pty} = Ghostty.PTY.start_link(cmd: "/bin/bash", cols: 80, rows: 24)

      # In a loop: forward PTY output to terminal, encode key events back to PTY

  """

  use GenServer

  alias Ghostty.PTY.Nif

  @type option ::
          {:cmd, Path.t()}
          | {:args, [String.t()]}
          | {:cols, pos_integer()}
          | {:rows, pos_integer()}
          | {:name, GenServer.name()}

  defstruct [:ref, :owner]

  @doc """
  Starts a PTY process linked to the caller.

  Output and exit messages are sent to the calling process.

  ## Options

    * `:cmd` — command to run (default: `$SHELL` or `/bin/sh`)
    * `:args` — argument list (default: `[]`)
    * `:cols` — terminal width in columns (default: `80`)
    * `:rows` — terminal height in rows (default: `24`)
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

  @doc "Writes data to the PTY (child's stdin)."
  @spec write(GenServer.server(), iodata()) :: :ok
  def write(pty, data) do
    GenServer.call(pty, {:write, IO.iodata_to_binary(data)})
  end

  @doc "Resizes the PTY. Sends SIGWINCH to the child."
  @spec resize(GenServer.server(), pos_integer(), pos_integer()) :: :ok
  def resize(pty, cols, rows)
      when is_integer(cols) and cols > 0 and is_integer(rows) and rows > 0 do
    GenServer.call(pty, {:resize, cols, rows})
  end

  @doc "Closes the PTY and terminates the child process."
  @spec close(GenServer.server()) :: :ok
  def close(pty) do
    GenServer.stop(pty)
  end

  @impl true
  def init(opts) do
    cmd = Keyword.get(opts, :cmd, System.get_env("SHELL") || "/bin/sh")
    args = Keyword.get(opts, :args, [])
    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)
    owner = Keyword.fetch!(opts, :owner)

    validate_size!(cols, rows)

    ref = Nif.nif_pty_open(cmd, args, cols, rows, owner)
    {:ok, %__MODULE__{ref: ref, owner: owner}}
  rescue
    e in [ErlangError, ArgumentError] ->
      {:stop, {:pty_open_failed, Exception.message(e)}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.ref, do: Nif.nif_pty_close(state.ref)
  end

  @impl true
  def handle_call({:write, data}, _from, state) do
    Nif.nif_pty_write(state.ref, data)
    {:reply, :ok, state}
  end

  def handle_call({:resize, cols, rows}, _from, state) do
    Nif.nif_pty_resize(state.ref, cols, rows)
    {:reply, :ok, state}
  end

  defp validate_size!(cols, rows)
       when is_integer(cols) and cols > 0 and is_integer(rows) and rows > 0,
       do: :ok

  defp validate_size!(_cols, _rows) do
    raise ArgumentError, "cols and rows must be positive integers"
  end
end
