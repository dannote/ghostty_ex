# Multiple supervised terminals — crash one, supervisor restarts it.
#
#   mix run examples/supervised.exs

defmodule Demo.Application do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Ghostty.Terminal, name: :console, id: :console, cols: 80, rows: 24},
      {Ghostty.Terminal, name: :logs, id: :logs, cols: 200, rows: 100, max_scrollback: 50_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

{:ok, sup} = Demo.Application.start_link([])

Ghostty.Terminal.write(:console, "Hello from \e[1mconsole\e[0m!\r\n")
Ghostty.Terminal.write(:logs, "Log entry 1\r\nLog entry 2\r\nLog entry 3\r\n")

{:ok, console_text} = Ghostty.Terminal.snapshot(:console)
{:ok, logs_text} = Ghostty.Terminal.snapshot(:logs)

IO.puts("Console: #{String.trim(console_text)}")
IO.puts("Logs: #{String.trim(logs_text)}")

# Show that terminals survive crashes
IO.puts("\nKilling :console...")
Process.exit(Process.whereis(:console), :kill)
Process.sleep(50)

IO.puts("Console restarted: #{is_pid(Process.whereis(:console))}")
Ghostty.Terminal.write(:console, "I'm back!\r\n")
{:ok, text} = Ghostty.Terminal.snapshot(:console)
IO.puts("Console says: #{String.trim(text)}")

# Logs terminal was unaffected
{:ok, logs_text} = Ghostty.Terminal.snapshot(:logs)
IO.puts("Logs still has: #{String.trim(logs_text)}")

Supervisor.stop(sup)
