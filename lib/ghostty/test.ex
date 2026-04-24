defmodule Ghostty.Test do
  @moduledoc """
  ExUnit helpers for terminal-oriented tests.

  These helpers keep `Ghostty.Terminal` focused on the core emulator API while
  making test code concise for common tasks: render iodata, inspect plain/HTML
  snapshots, assert visible text, and encode keyboard input.

  Import this module in tests:

      import Ghostty.Test

      {:ok, term} = term(cols: 80, rows: 24)
      write(term, ["Hello", "\r\n"])
      assert_text(term, "Hello")
  """

  import ExUnit.Assertions

  alias Ghostty.{KeyEvent, Terminal}
  alias Ghostty.Terminal.Cell

  @type terminal :: GenServer.server()
  @type snapshot_source :: terminal() | binary()

  @doc "Starts a `Ghostty.Terminal` for tests."
  @spec term(keyword()) :: GenServer.on_start()
  def term(opts \\ []), do: Terminal.start_link(opts)

  @doc "Writes iodata to the terminal and returns the terminal."
  @spec write(terminal(), iodata()) :: terminal()
  def write(term, data) do
    :ok = Terminal.write(term, data)
    term
  end

  @doc "Writes lines separated with CRLF and returns the terminal."
  @spec lines(terminal(), [iodata()]) :: terminal()
  def lines(term, lines) when is_list(lines) do
    write(term, Enum.intersperse(lines, "\r\n"))
  end

  @doc "Returns a terminal snapshot. Defaults to `:plain`."
  @spec snap(terminal(), Terminal.format()) :: binary()
  def snap(term, format \\ :plain) do
    {:ok, snapshot} = Terminal.snapshot(term, format)
    snapshot
  end

  @doc "Shortcut for a plain-text snapshot."
  @spec plain(terminal()) :: binary()
  def plain(term), do: snap(term, :plain)

  @doc "Shortcut for an HTML snapshot."
  @spec html(terminal()) :: binary()
  def html(term), do: snap(term, :html)

  @doc "Shortcut for a VT snapshot."
  @spec vt(terminal()) :: binary()
  def vt(term), do: snap(term, :vt)

  @doc "Returns terminal cells."
  @spec cells(terminal()) :: [[Terminal.cell()]]
  def cells(term), do: Terminal.cells(term)

  @doc "Asserts that a terminal/text snapshot includes a string or matches a regex."
  @spec assert_text(snapshot_source(), String.t() | Regex.t()) :: snapshot_source()
  def assert_text(source, expected) do
    text = source_text(source)

    case expected do
      %Regex{} = regex -> assert text =~ regex
      string when is_binary(string) -> assert text =~ string
    end

    source
  end

  @doc "Refutes that a terminal/text snapshot includes a string or matches a regex."
  @spec refute_text(snapshot_source(), String.t() | Regex.t()) :: snapshot_source()
  def refute_text(source, expected) do
    text = source_text(source)

    case expected do
      %Regex{} = regex -> refute text =~ regex
      string when is_binary(string) -> refute text =~ string
    end

    source
  end

  @doc "Asserts against an HTML snapshot."
  @spec assert_html(terminal(), String.t() | Regex.t()) :: terminal()
  def assert_html(term, expected) do
    assert_text(html(term), expected)
    term
  end

  @doc "Refutes against an HTML snapshot."
  @spec refute_html(terminal(), String.t() | Regex.t()) :: terminal()
  def refute_html(term, expected) do
    refute_text(html(term), expected)
    term
  end

  @doc "Asserts against a VT snapshot."
  @spec assert_vt(terminal(), String.t() | Regex.t()) :: terminal()
  def assert_vt(term, expected) do
    assert_text(vt(term), expected)
    term
  end

  @doc "Refutes against a VT snapshot."
  @spec refute_vt(terminal(), String.t() | Regex.t()) :: terminal()
  def refute_vt(term, expected) do
    refute_text(vt(term), expected)
    term
  end

  @doc "Returns the cell at `{x, y}` using zero-based coordinates."
  @spec cell(terminal(), {non_neg_integer(), non_neg_integer()}) :: Terminal.cell()
  def cell(term, {x, y}) do
    term
    |> cells()
    |> Enum.at(y)
    |> Enum.at(x)
  end

  @doc "Asserts a cell's grapheme and optional style properties."
  @spec assert_cell(terminal(), {non_neg_integer(), non_neg_integer()}, binary(), keyword()) :: terminal()
  def assert_cell(term, position, grapheme, opts \\ []) do
    cell = cell(term, position)
    assert Cell.grapheme(cell) == grapheme

    Enum.each(opts, fn
      {:fg, color} -> assert Cell.fg(cell) == color
      {:bg, color} -> assert Cell.bg(cell) == color
      {:bold?, expected} -> assert Cell.bold?(cell) == expected
      {:italic?, expected} -> assert Cell.italic?(cell) == expected
      {:underline?, expected} -> assert Cell.underline?(cell) == expected
    end)

    term
  end

  @doc "Encodes a key and writes the resulting bytes to the terminal."
  @spec write_key(terminal(), KeyEvent.key() | KeyEvent.t(), keyword()) :: terminal()
  def write_key(term, key_or_event, opts \\ []) do
    case key(term, key_or_event, opts) do
      {:ok, bytes} -> write(term, bytes)
      :none -> term
    end
  end

  @doc """
  Asserts a snapshot against a fixture file.

  Set `UPDATE_GHOSTTY_SNAPSHOTS=1` to rewrite fixtures.
  """
  @spec assert_snap(snapshot_source(), Path.t(), keyword()) :: snapshot_source()
  def assert_snap(source, path, opts \\ []) do
    actual = source_text(source, Keyword.get(opts, :format, :plain))

    if System.get_env("UPDATE_GHOSTTY_SNAPSHOTS") in ["1", "true"] do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, actual)
    end

    assert File.read!(path) == actual
    source
  end

  @doc "Builds a `Ghostty.KeyEvent` with defaults for tests."
  @spec event(KeyEvent.key(), keyword()) :: KeyEvent.t()
  def event(key, opts \\ []) do
    %KeyEvent{
      action: Keyword.get(opts, :action, :press),
      key: key,
      mods: Keyword.get(opts, :mods, []),
      utf8: Keyword.get(opts, :utf8),
      unshifted_codepoint: Keyword.get(opts, :unshifted_codepoint)
    }
  end

  @doc "Encodes a key event through Ghostty's terminal encoder."
  @spec key(terminal(), KeyEvent.key() | KeyEvent.t(), keyword()) :: {:ok, binary()} | :none
  def key(term, event_or_key, opts \\ [])
  def key(term, %KeyEvent{} = event, _opts), do: Terminal.input_key(term, event)
  def key(term, key, opts), do: key(term, event(key, opts), [])

  @doc "Encodes a key event using a short-lived terminal."
  @spec key_bytes(KeyEvent.key() | KeyEvent.t(), keyword()) :: binary() | :none
  def key_bytes(event_or_key, opts \\ [])

  def key_bytes(%KeyEvent{} = event, _opts) do
    {:ok, term} = term()

    case Terminal.input_key(term, event) do
      {:ok, bytes} -> bytes
      :none -> :none
    end
  end

  def key_bytes(key, opts), do: key_bytes(event(key, opts), [])

  defp source_text(source, format \\ :plain)
  defp source_text(text, _format) when is_binary(text), do: text
  defp source_text(term, format), do: snap(term, format)
end
