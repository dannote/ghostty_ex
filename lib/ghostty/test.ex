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
