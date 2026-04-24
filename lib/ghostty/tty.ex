defmodule Ghostty.TTY do
  @moduledoc """
  Current-terminal adapter for local terminal applications.

  `Ghostty.Terminal` emulates a terminal and `Ghostty.PTY` manages child
  pseudo-terminals. `Ghostty.TTY` is the complementary adapter for the terminal
  running the current BEAM process: it starts raw input, decodes keyboard bytes
  into `Ghostty.KeyEvent`, writes output, and reports resize events.

  Events are sent to the owner process passed in `:owner` (defaults to the
  process that calls `start_link/1`):

      {Ghostty.TTY, tty, {:key, %Ghostty.KeyEvent{}}}
      {Ghostty.TTY, tty, {:data, binary}}
      {Ghostty.TTY, tty, {:resize, cols, rows}}
      {Ghostty.TTY, tty, :eof}

  This module uses OTP terminal facilities rather than shelling out to `stty`.
  """

  use GenServer

  alias Ghostty.KeyDecoder

  @escape_timeout 10

  @type event ::
          {:key, Ghostty.KeyEvent.t()}
          | {:data, binary()}
          | {:resize, pos_integer(), pos_integer()}
          | :eof

  @type option ::
          {:owner, pid()}
          | {:name, GenServer.name()}
          | {:raw, boolean()}

  defstruct [:owner, :reader, :ref, buffer: nil]

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])
    init_opts = Keyword.put_new(init_opts, :owner, self())
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc "Returns a child spec for supervision trees."
  def child_spec(opts) do
    %{
      id: opts[:id] || opts[:name] || __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000
    }
  end

  @spec write(GenServer.server(), iodata()) :: :ok
  def write(tty, data), do: GenServer.call(tty, {:write, IO.iodata_to_binary(data)})

  @spec size() :: {pos_integer(), pos_integer()}
  def size do
    cols =
      case :io.columns() do
        {:ok, value} -> value
        _ -> 80
      end

    rows =
      case :io.rows() do
        {:ok, value} -> value
        _ -> 24
      end

    {cols, rows}
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :raw, true), do: start_raw_shell()

    owner = Keyword.fetch!(opts, :owner)
    ref = make_ref()
    handle_sigwinch()
    :ok = :gen_event.add_handler(:erl_signal_server, __MODULE__.Winch, {owner, self(), ref})
    {:ok, reader} = __MODULE__.Reader.start_link(self())
    {:ok, %__MODULE__{owner: owner, reader: reader, ref: ref}}
  rescue
    exception -> {:stop, Exception.message(exception)}
  catch
    kind, reason -> {:stop, {kind, reason}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.reader, do: Process.exit(state.reader, :kill)
    :ok
  end

  @impl true
  def handle_call({:write, data}, _from, state) do
    IO.write(data)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:tty_data, :eof}, state) do
    send_event(state, :eof)
    {:noreply, state}
  end

  def handle_info({:tty_data, data}, state) when is_binary(data) do
    handle_data(data, state)
  end

  def handle_info(:escape_timeout, %__MODULE__{buffer: nil} = state), do: {:noreply, state}

  def handle_info(:escape_timeout, state) do
    emit_decoded(state.buffer, state)
    {:noreply, %{state | buffer: nil}}
  end

  def handle_info({:resize, ref}, %__MODULE__{ref: ref} = state) do
    {cols, rows} = size()
    send_event(state, {:resize, cols, rows})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_raw_shell do
    start_interactive = &:shell.start_interactive/1
    start_interactive.({:noshell, :raw})
  end

  defp handle_sigwinch do
    set_signal = &:os.set_signal/2
    set_signal.(:sigwinch, :handle)
  end

  defp handle_data("\e", %__MODULE__{buffer: nil} = state) do
    Process.send_after(self(), :escape_timeout, @escape_timeout)
    {:noreply, %{state | buffer: "\e"}}
  end

  defp handle_data(data, %__MODULE__{buffer: nil} = state) do
    emit_decoded(data, state)
    {:noreply, state}
  end

  defp handle_data(data, state) do
    buffer = state.buffer <> data

    if complete_escape?(buffer) do
      emit_decoded(buffer, state)
      {:noreply, %{state | buffer: nil}}
    else
      Process.send_after(self(), :escape_timeout, @escape_timeout)
      {:noreply, %{state | buffer: buffer}}
    end
  end

  defp emit_decoded(data, state) do
    case KeyDecoder.decode(data) do
      {:key, event} -> send_event(state, {:key, event})
      {:data, bytes} -> send_event(state, {:data, bytes})
    end
  end

  defp send_event(state, event), do: send(state.owner, {__MODULE__, self(), event})

  defp complete_escape?("\e[" <> rest) when rest != "" do
    rest |> String.last() |> csi_final_byte?()
  end

  defp complete_escape?("\eO" <> rest) when rest != "", do: rest |> String.last() |> ss3_final_byte?()
  defp complete_escape?("\e" <> rest) when byte_size(rest) > 0, do: true
  defp complete_escape?(_buffer), do: false

  defp csi_final_byte?(<<byte>>) when byte >= ?@ and byte <= ?~, do: true
  defp csi_final_byte?(_byte), do: false
  defp ss3_final_byte?(<<byte>>) when byte >= ?@ and byte <= ?~, do: true
  defp ss3_final_byte?(_byte), do: false
end

defmodule Ghostty.TTY.Reader do
  @moduledoc false

  use GenServer

  @spec start_link(pid()) :: GenServer.on_start()
  def start_link(parent), do: GenServer.start_link(__MODULE__, parent)

  @impl true
  def init(parent), do: {:ok, parent, {:continue, :read}}

  @impl true
  def handle_continue(:read, parent) do
    case IO.getn("") do
      :eof -> send(parent, {:tty_data, :eof})
      {:error, _reason} -> :ok
      data when is_binary(data) -> send(parent, {:tty_data, data})
    end

    {:noreply, parent, {:continue, :read}}
  end
end

defmodule Ghostty.TTY.Winch do
  @moduledoc false

  @behaviour :gen_event

  @impl true
  def init({owner, tty, ref}), do: {:ok, %{owner: owner, tty: tty, ref: ref}}

  @impl true
  def handle_event(:sigwinch, state) do
    send(state.tty, {:resize, state.ref})
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def handle_call(_request, state), do: {:ok, :ok, state}

  @impl true
  def handle_info(_message, state), do: {:ok, state}
end
