# Demonstrate that Ghostty correctly handles carriage returns and overwrites —
# the terminal state always reflects what you'd actually *see* on screen.
#
#   mix run examples/progress_bar.exs

{:ok, term} = Ghostty.Terminal.start_link(cols: 60, rows: 5)

# Simulate a progress bar that overwrites itself with \r
for i <- 1..100 do
  bar_width = 40
  filled = div(i * bar_width, 100)
  empty = bar_width - filled
  bar = String.duplicate("█", filled) <> String.duplicate("░", empty)

  Ghostty.Terminal.write(term, "\r\e[K\e[1;36m#{bar}\e[0m #{i}%")
  Process.sleep(10)
end

Ghostty.Terminal.write(term, "\r\n\e[1;32m✓ Done!\e[0m\r\n")

{:ok, text} = Ghostty.Terminal.snapshot(term)
IO.puts("Final screen state:")
IO.puts(text)

# The plain text shows just the final state — not 100 intermediate frames
IO.puts("(Notice: only the final progress bar is shown, not all 100 frames)")
