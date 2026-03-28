defmodule Ghostty.Terminal do
  @moduledoc """
  A managed terminal emulator backed by libghostty-vt.

  Each terminal is a GenServer that owns a libghostty-vt terminal instance.
  All operations are serialized through the GenServer to ensure thread safety.

  ## Examples

      {:ok, term} = Ghostty.Terminal.start_link(cols: 120, rows: 40)
      Ghostty.Terminal.write(term, "Hello, \\e[1mBold\\e[0m World!\\r\\n")
      {:ok, text} = Ghostty.Terminal.snapshot(term)
      # => {:ok, "Hello, Bold World!\\n"}
  """

  use GenServer

  alias Ghostty.Terminal.Nif

  @type snapshot_format :: :plain | :html | :vt
  @type option ::
          {:cols, pos_integer()}
          | {:rows, pos_integer()}
          | {:max_scrollback, non_neg_integer()}
          | {:name, GenServer.name()}

  defstruct [:ref, :cols, :rows]

  @doc """
  Starts a terminal process.

  ## Options

    * `:cols` - number of columns (default: 80)
    * `:rows` - number of rows (default: 24)
    * `:max_scrollback` - maximum scrollback lines (default: 10_000)
    * `:name` - optional GenServer name

  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc """
  Writes VT-encoded data to the terminal.

  Accepts iodata — binaries, charlists, and nested combinations.
  The terminal's VT parser processes escape sequences and updates
  the internal screen/cursor/style state.
  """
  @spec write(GenServer.server(), iodata()) :: :ok
  def write(terminal, data) do
    GenServer.call(terminal, {:write, IO.iodata_to_binary(data)})
  end

  @doc """
  Resizes the terminal to the given dimensions.

  Text reflow is handled automatically by libghostty-vt.
  """
  @spec resize(GenServer.server(), pos_integer(), pos_integer()) :: :ok
  def resize(terminal, cols, rows) do
    GenServer.call(terminal, {:resize, cols, rows})
  end

  @doc """
  Performs a full terminal reset (RIS).
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(terminal) do
    GenServer.call(terminal, :reset)
  end

  @doc """
  Returns a snapshot of the terminal screen content.

  ## Formats

    * `:plain` - plain text, stripped of all styling (default)
    * `:html` - HTML with inline styles preserving colors and attributes
    * `:vt` - raw VT escape sequences

  """
  @spec snapshot(GenServer.server(), snapshot_format()) :: {:ok, binary()}
  def snapshot(terminal, format \\ :plain) do
    GenServer.call(terminal, {:snapshot, format})
  end

  @doc """
  Scrolls the terminal viewport by `delta` lines.

  Positive values scroll down, negative values scroll up.
  """
  @spec scroll(GenServer.server(), integer()) :: :ok
  def scroll(terminal, delta) do
    GenServer.call(terminal, {:scroll, delta})
  end

  @doc """
  Returns the current cursor position as `{col, row}` (0-indexed).
  """
  @spec cursor(GenServer.server()) :: {non_neg_integer(), non_neg_integer()}
  def cursor(terminal) do
    GenServer.call(terminal, :cursor)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)
    max_scrollback = Keyword.get(opts, :max_scrollback, 10_000)

    ref = Nif.nif_new(cols, rows, max_scrollback)
    {:ok, %__MODULE__{ref: ref, cols: cols, rows: rows}}
  end

  @impl true
  def handle_call({:write, data}, _from, state) do
    Nif.nif_vt_write(state.ref, data)
    {:reply, :ok, state}
  end

  def handle_call({:resize, cols, rows}, _from, state) do
    Nif.nif_resize(state.ref, cols, rows)
    {:reply, :ok, %{state | cols: cols, rows: rows}}
  end

  def handle_call(:reset, _from, state) do
    Nif.nif_reset(state.ref)
    {:reply, :ok, state}
  end

  def handle_call({:snapshot, format}, _from, state) do
    result = Nif.nif_snapshot(state.ref, format)
    {:reply, {:ok, result}, state}
  end

  def handle_call({:scroll, delta}, _from, state) do
    Nif.nif_scroll(state.ref, delta)
    {:reply, :ok, state}
  end

  def handle_call(:cursor, _from, state) do
    {col, row} = Nif.nif_get_cursor(state.ref)
    {:reply, {col, row}, state}
  end
end
