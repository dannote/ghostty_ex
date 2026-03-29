# Demonstrate text reflow on terminal resize.
# libghostty-vt rewraps long lines automatically — just like a real terminal.
#
#   mix run examples/reflow.exs

{:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 10)

long_line = "The quick brown fox jumps over the lazy dog. " |> String.duplicate(3)
Ghostty.Terminal.write(term, long_line <> "\r\n")

{:ok, wide} = Ghostty.Terminal.snapshot(term)
IO.puts("=== 80 columns ===")
IO.puts(wide)

Ghostty.Terminal.resize(term, 40, 10)
{:ok, narrow} = Ghostty.Terminal.snapshot(term)
IO.puts("\n=== 40 columns (reflowed) ===")
IO.puts(narrow)

Ghostty.Terminal.resize(term, 120, 10)
{:ok, wider} = Ghostty.Terminal.snapshot(term)
IO.puts("\n=== 120 columns (reflowed back) ===")
IO.puts(wider)
