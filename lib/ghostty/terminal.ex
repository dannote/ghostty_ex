defmodule Ghostty.Terminal do
  @moduledoc """
  A managed terminal emulator backed by libghostty-vt.

  Each terminal is a GenServer that owns a libghostty-vt terminal instance.
  All operations are serialized through the GenServer to ensure thread safety
  (libghostty-vt terminal instances are not thread-safe).

  ## Examples

      # Simple usage
      {:ok, term} = Ghostty.Terminal.start_link(cols: 120, rows: 40)
      Ghostty.Terminal.write(term, File.read!("recording.vt"))
      {:ok, html} = Ghostty.Terminal.snapshot(term, :html)

      # With PTY write-back
      {:ok, term} = Ghostty.Terminal.start_link(
        cols: 80, rows: 24,
        on_output: fn data -> IO.write(data) end
      )

      # Supervised
      children = [
        {Ghostty.Terminal, name: :main, cols: 80, rows: 24, max_scrollback: 50_000}
      ]

  ## Formats

  The `:snapshot` function supports three output formats:

    * `:plain` — plain text with all styling stripped
    * `:html` — HTML with inline styles preserving all colors and attributes
    * `:vt` — raw VT escape sequences (round-trippable)

  ## Callbacks

  Terminal programs can trigger side effects via VT sequences. Register
  callbacks to handle them:

    * `:on_output` — PTY write-back (query responses, DA replies)
    * `:on_bell` — BEL character
    * `:on_title` — OSC 2 title change

  """

  use GenServer

  alias Ghostty.Terminal.Nif

  @type format :: :plain | :html | :vt

  @type option ::
          {:cols, pos_integer()}
          | {:rows, pos_integer()}
          | {:max_scrollback, non_neg_integer()}
          | {:on_output, (binary() -> any())}
          | {:on_bell, (-> any())}
          | {:on_title, (String.t() -> any())}
          | {:name, GenServer.name()}

  defstruct [:ref, :cols, :rows, :on_output, :on_bell, :on_title]

  @doc """
  Starts a terminal process linked to the caller.

  ## Options

    * `:cols` - number of columns (default: `80`)
    * `:rows` - number of rows (default: `24`)
    * `:max_scrollback` - maximum scrollback lines (default: `10_000`)
    * `:on_output` - callback `(binary -> any)` for PTY write-back
    * `:on_bell` - callback `(-> any)` for BEL character
    * `:on_title` - callback `(String.t -> any)` for title changes
    * `:name` - GenServer name registration

  ## Examples

      Ghostty.Terminal.start_link(cols: 120, rows: 40)
      Ghostty.Terminal.start_link(name: :console, max_scrollback: 50_000)

  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {server_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc "Returns a child spec for use in supervision trees."
  def child_spec(opts) do
    id = Keyword.get(opts, :id, Keyword.get(opts, :name, __MODULE__))

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]}
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
  Encodes a key event into a terminal escape sequence.

  Returns `{:ok, sequence}` with the bytes to send to the PTY,
  or `:none` if the key event produces no output.

  If `:on_output` is configured, the sequence is also automatically
  forwarded to the callback.

  ## Examples

      Ghostty.Terminal.input_key(term, %Ghostty.KeyEvent{key: :enter})
      # => {:ok, "\\r"}

      Ghostty.Terminal.input_key(term, %Ghostty.KeyEvent{key: :c, mods: [:ctrl]})
      # => {:ok, <<3>>}

      Ghostty.Terminal.input_key(term, %Ghostty.KeyEvent{key: :arrow_up})
      # => {:ok, "\\e[A"}

  """
  @spec input_key(GenServer.server(), Ghostty.KeyEvent.t()) :: {:ok, binary()} | :none
  def input_key(terminal, %Ghostty.KeyEvent{} = event) do
    GenServer.call(terminal, {:input_key, event})
  end

  @doc """
  Encodes a mouse event into a terminal escape sequence.

  Returns `{:ok, sequence}` or `:none` if mouse tracking is not
  enabled by the running program.

  ## Examples

      Ghostty.Terminal.input_mouse(term, %Ghostty.MouseEvent{
        action: :press, button: :left, x: 10.0, y: 5.0
      })

  """
  @spec input_mouse(GenServer.server(), Ghostty.MouseEvent.t()) :: {:ok, binary()} | :none
  def input_mouse(terminal, %Ghostty.MouseEvent{} = event) do
    GenServer.call(terminal, {:input_mouse, event})
  end

  @doc """
  Scrolls the terminal viewport.

  Positive `delta` scrolls down (towards newer content),
  negative scrolls up (towards scrollback history).

  ## Examples

      Ghostty.Terminal.scroll(term, -10)  # scroll up 10 lines
      Ghostty.Terminal.scroll(term, 5)    # scroll down 5 lines

  """
  @spec scroll(GenServer.server(), integer()) :: :ok
  def scroll(terminal, delta) do
    GenServer.call(terminal, {:scroll, delta})
  end

  @doc """
  Returns the current cursor position as `{col, row}` (0-indexed).

  ## Examples

      {col, row} = Ghostty.Terminal.cursor(term)

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

    ref = Nif.nif_new(cols, rows, max_scrollback)

    state = %__MODULE__{
      ref: ref,
      cols: cols,
      rows: rows,
      on_output: Keyword.get(opts, :on_output),
      on_bell: Keyword.get(opts, :on_bell),
      on_title: Keyword.get(opts, :on_title)
    }

    {:ok, state}
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
    pos = Nif.nif_get_cursor(state.ref)
    {:reply, pos, state}
  end

  def handle_call(:size, _from, state) do
    {:reply, {state.cols, state.rows}, state}
  end

  def handle_call({:input_key, _event}, _from, state) do
    # Phase 2: key encoding via NIF
    {:reply, :none, state}
  end

  def handle_call({:input_mouse, _event}, _from, state) do
    # Phase 2: mouse encoding via NIF
    {:reply, :none, state}
  end

  @impl true
  def handle_info({:ghostty_pty_write, data}, state) do
    if state.on_output, do: state.on_output.(data)
    {:noreply, state}
  end

  def handle_info({:ghostty_bell}, state) do
    if state.on_bell, do: state.on_bell.()
    {:noreply, state}
  end

  def handle_info({:ghostty_title, title}, state) do
    if state.on_title, do: state.on_title.(title)
    {:noreply, state}
  end
end
