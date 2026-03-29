# Strip ANSI escape sequences from command output.
# Useful for CI pipelines, log processors, or test output parsing.
#
#   echo -e "\e[31mred\e[0m \e[1mbold\e[0m normal" | mix run examples/ansi_stripper.exs
#   mix test --color 2>&1 | mix run examples/ansi_stripper.exs

{:ok, term} = Ghostty.Terminal.start_link(cols: 200, rows: 500)

IO.stream(:stdio, :line)
|> Stream.each(fn line ->
  Ghostty.Terminal.write(term, line)
end)
|> Stream.run()

{:ok, text} = Ghostty.Terminal.snapshot(term)
IO.write(text)
