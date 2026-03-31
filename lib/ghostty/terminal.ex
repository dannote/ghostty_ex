defmodule Ghostty.Terminal do
  @moduledoc """
  A managed terminal emulator backed by libghostty-vt.

  Each terminal is a GenServer that owns a libghostty-vt terminal instance.
  All operations are serialized through the GenServer to ensure thread safety
  (libghostty-vt terminal instances are not thread-safe).

  ## Examples

      {:ok, term} = Ghostty.Terminal.start_link(cols: 120, rows: 40)
      Ghostty.Terminal.write(term, File.read!("recording.vt"))
      {:ok, html} = Ghostty.Terminal.snapshot(term, :html)

  ## Supervision

      children = [
        {Ghostty.Terminal, name: :main, cols: 80, rows: 24, max_scrollback: 50_000}
      ]

  ## Effects

  Terminal programs can trigger side effects via VT sequences (query
  responses, bell, title changes). These are forwarded as messages to
  the process that called `start_link/1`:

    * `{:pty_write, binary}` — query responses to write back to the PTY
    * `:bell` — BEL character
    * `:title_changed` — title change via OSC 2

  ## Snapshot formats

    * `:plain` — plain text with all styling stripped
    * `:html` — HTML with inline styles preserving all colors and attributes
    * `:vt` — raw VT escape sequences (round-trippable)

  """

  use GenServer

  alias Ghostty.Terminal.Nif

  @type format :: :plain | :html | :vt

  @type cell ::
          {binary(), {byte(), byte(), byte()} | nil, {byte(), byte(), byte()} | nil, non_neg_integer()}

  @type option ::
          {:cols, pos_integer()}
          | {:rows, pos_integer()}
          | {:max_scrollback, non_neg_integer()}
          | {:name, GenServer.name()}

  defstruct [:ref, :cols, :rows]

  @doc """
  Starts a terminal process linked to the caller.

  Effect messages (`:bell`, `:title_changed`, `{:pty_write, data}`)
  are sent to the calling process.

  ## Options

    * `:cols` - number of columns (default: `80`)
    * `:rows` - number of rows (default: `24`)
    * `:max_scrollback` - maximum scrollback lines (default: `10_000`)
    * `:name` - GenServer name registration

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
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @doc """
  Writes VT-encoded data to the terminal.

  The terminal's VT parser processes escape sequences and updates
  the internal screen, cursor, and style state. Accepts iodata.

  ## Examples

      Ghostty.Terminal.write(term, "hello world")
      Ghostty.Terminal.write(term, "\\e[31mred\\e[0m")
      Ghostty.Terminal.write(term, ["line 1\\r\\n", "line 2\\r\\n"])

  """
  @spec write(GenServer.server(), iodata()) :: :ok
  def write(terminal, data) do
    GenServer.call(terminal, {:write, IO.iodata_to_binary(data)})
  end

  @doc """
  Resizes the terminal. Text reflow is handled automatically.

  ## Examples

      Ghostty.Terminal.resize(term, 120, 40)

  """
  @spec resize(GenServer.server(), pos_integer(), pos_integer()) :: :ok
  def resize(terminal, cols, rows) do
    GenServer.call(terminal, {:resize, cols, rows})
  end

  @doc """
  Performs a full terminal reset (RIS — Reset to Initial State).
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(terminal) do
    GenServer.call(terminal, :reset)
  end

  @doc """
  Returns a snapshot of the terminal screen content.

  ## Formats

    * `:plain` — plain text, stripped of all styling (default)
    * `:html` — HTML with inline styles preserving colors and attributes
    * `:vt` — raw VT escape sequences

  ## Examples

      {:ok, text} = Ghostty.Terminal.snapshot(term)
      {:ok, html} = Ghostty.Terminal.snapshot(term, :html)
      {:ok, vt}   = Ghostty.Terminal.snapshot(term, :vt)

  """
  @spec snapshot(GenServer.server(), format()) :: {:ok, binary()}
  def snapshot(terminal, format \\ :plain) do
    GenServer.call(terminal, {:snapshot, format})
  end

  @doc """
  Returns the terminal screen as a grid of cells.

  Each cell is `{grapheme, fg, bg, flags}` where:

    * `grapheme` — UTF-8 binary (empty for blank cells)
    * `fg` / `bg` — `{r, g, b}` tuples or `nil`
    * `flags` — bitmask (see `Ghostty.Terminal.Cell` for helpers)

  ## Examples

      rows = Ghostty.Terminal.cells(term)

      for row <- rows, {char, fg, _bg, flags} <- row, char != "" do
        if Ghostty.Terminal.Cell.bold?({char, fg, nil, flags}), do: IO.write("*")
        IO.write(char)
      end

  """
  @spec cells(GenServer.server()) :: [[cell()]]
  def cells(terminal) do
    GenServer.call(terminal, :cells)
  end

  @doc """
  Encodes a key event into a terminal escape sequence.

  Returns `{:ok, sequence}` with the bytes to send to the PTY,
  or `:none` if the key event produces no output.

  Raises `ArgumentError` for invalid key names or actions.

  ## Examples

      Ghostty.Terminal.input_key(term, %Ghostty.KeyEvent{key: :enter})
      # => {:ok, "\\r"}

      Ghostty.Terminal.input_key(term, %Ghostty.KeyEvent{key: :c, mods: [:ctrl]})
      # => {:ok, <<3>>}

  """
  @spec input_key(GenServer.server(), Ghostty.KeyEvent.t()) :: {:ok, binary()} | :none
  def input_key(terminal, %Ghostty.KeyEvent{} = event) do
    GenServer.call(terminal, {:input_key, event})
  end

  @doc """
  Encodes a mouse event into a terminal escape sequence.

  Returns `{:ok, sequence}` or `:none` if mouse tracking is not
  enabled by the running program.

  Raises `ArgumentError` for invalid button names or actions.
  """
  @spec input_mouse(GenServer.server(), Ghostty.MouseEvent.t()) :: {:ok, binary()} | :none
  def input_mouse(terminal, %Ghostty.MouseEvent{} = event) do
    GenServer.call(terminal, {:input_mouse, event})
  end

  @doc """
  Encodes a focus event into a terminal escape sequence.

  ## Examples

      {:ok, seq} = Ghostty.Terminal.encode_focus(true)   # => "\\e[I"
      {:ok, seq} = Ghostty.Terminal.encode_focus(false)  # => "\\e[O"

  """
  @spec encode_focus(boolean()) :: {:ok, binary()} | :none
  def encode_focus(gained?) do
    Nif.nif_encode_focus(gained?)
  end

  @doc """
  Scrolls the terminal viewport.

  Positive `delta` scrolls down (towards newer content),
  negative scrolls up (towards scrollback history).
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

  @doc """
  Returns the current terminal dimensions as `{cols, rows}`.
  """
  @spec size(GenServer.server()) :: {pos_integer(), pos_integer()}
  def size(terminal) do
    GenServer.call(terminal, :size)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)
    max_scrollback = Keyword.get(opts, :max_scrollback, 10_000)

    validate_pos_integer!(:cols, cols)
    validate_pos_integer!(:rows, rows)
    validate_non_neg_integer!(:max_scrollback, max_scrollback)

    ref = Nif.nif_new(cols, rows, max_scrollback)
    Nif.nif_set_effect_pid(ref, Keyword.fetch!(opts, :owner))

    {:ok, %__MODULE__{ref: ref, cols: cols, rows: rows}}
  rescue
    e in ErlangError ->
      {:stop, {:nif_not_loaded, Exception.message(e)}}

    e in ArgumentError ->
      {:stop, {:invalid_option, Exception.message(e)}}
  end

  defp validate_pos_integer!(_name, value) when is_integer(value) and value > 0, do: :ok

  defp validate_pos_integer!(name, value) do
    raise ArgumentError, "expected #{name} to be a positive integer, got: #{inspect(value)}"
  end

  defp validate_non_neg_integer!(_name, value) when is_integer(value) and value >= 0, do: :ok

  defp validate_non_neg_integer!(name, value) do
    raise ArgumentError,
          "expected #{name} to be a non-negative integer, got: #{inspect(value)}"
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
    result = Nif.nif_snapshot(state.ref, Atom.to_string(format))
    {:reply, {:ok, result}, state}
  end

  def handle_call({:scroll, delta}, _from, state) do
    Nif.nif_scroll(state.ref, delta)
    {:reply, :ok, state}
  end

  def handle_call(:cursor, _from, state) do
    {:reply, Nif.nif_get_cursor(state.ref), state}
  end

  def handle_call(:size, _from, state) do
    {:reply, {state.cols, state.rows}, state}
  end

  def handle_call(:cells, _from, state) do
    {:reply, Nif.nif_render_cells(state.ref), state}
  end

  def handle_call({:input_key, event}, _from, state) do
    result =
      Nif.nif_encode_key(
        state.ref,
        Ghostty.KeyEvent.action_to_int(event.action),
        Ghostty.KeyEvent.key_to_int(event.key),
        Ghostty.KeyEvent.mods_to_bitmask(event.mods),
        event.utf8 || "",
        event.unshifted_codepoint || 0
      )

    {:reply, result, state}
  end

  def handle_call({:input_mouse, event}, _from, state) do
    result =
      Nif.nif_encode_mouse(
        state.ref,
        Ghostty.MouseEvent.action_to_int(event.action),
        Ghostty.MouseEvent.button_to_int(event.button),
        Ghostty.MouseEvent.mods_to_bitmask(event.mods),
        event.x / 1,
        event.y / 1
      )

    {:reply, result, state}
  end
end
