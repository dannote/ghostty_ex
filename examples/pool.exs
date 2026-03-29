# Terminal pool — reuse terminals across tasks to avoid allocation overhead.
# Each terminal is checked out, used, reset, and returned.
#
#   mix run examples/pool.exs

defmodule TerminalPool do
  use GenServer

  def start_link(opts) do
    size = Keyword.fetch!(opts, :size)
    terminal_opts = Keyword.get(opts, :terminal, [])
    GenServer.start_link(__MODULE__, {size, terminal_opts}, name: Keyword.get(opts, :name))
  end

  def checkout(pool, timeout \\ 5_000) do
    GenServer.call(pool, :checkout, timeout)
  end

  def checkin(pool, term) do
    GenServer.cast(pool, {:checkin, term})
  end

  def with_terminal(pool, fun) do
    term = checkout(pool)

    try do
      fun.(term)
    after
      checkin(pool, term)
    end
  end

  @impl true
  def init({size, terminal_opts}) do
    terminals =
      for _ <- 1..size do
        {:ok, term} = Ghostty.Terminal.start_link(terminal_opts)
        term
      end

    {:ok, %{available: terminals, terminal_opts: terminal_opts}}
  end

  @impl true
  def handle_call(:checkout, _from, %{available: [term | rest]} = state) do
    {:reply, term, %{state | available: rest}}
  end

  def handle_call(:checkout, _from, %{available: []} = state) do
    {:ok, term} = Ghostty.Terminal.start_link(state.terminal_opts)
    {:reply, term, state}
  end

  @impl true
  def handle_cast({:checkin, term}, state) do
    Ghostty.Terminal.reset(term)
    {:noreply, %{state | available: [term | state.available]}}
  end
end

{:ok, pool} = TerminalPool.start_link(size: 3, terminal: [cols: 80, rows: 24])

# Process multiple ANSI strings concurrently using the pool
inputs = [
  "\e[31mError:\e[0m something went wrong\r\n",
  "\e[33mWarning:\e[0m disk usage at 89%\r\n",
  "\e[32mOK:\e[0m all checks passed\r\n",
  "\e[36mInfo:\e[0m deploying to production\r\n",
  "\e[35mDebug:\e[0m cache miss for key=user:42\r\n"
]

results =
  inputs
  |> Task.async_stream(fn input ->
    TerminalPool.with_terminal(pool, fn term ->
      Ghostty.Terminal.write(term, input)
      {:ok, text} = Ghostty.Terminal.snapshot(term)
      String.trim(text)
    end)
  end)
  |> Enum.map(fn {:ok, text} -> text end)

IO.puts("Processed #{length(results)} inputs through pool of 3 terminals:\n")
Enum.each(results, &IO.puts("  #{&1}"))
