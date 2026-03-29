# Basic terminal usage — write text, read it back.
#
#   mix run examples/hello.exs

{:ok, term} = Ghostty.Terminal.start_link(cols: 60, rows: 10)

Ghostty.Terminal.write(term, "Hello, \e[1;32mGhostty\e[0m!\r\n")
Ghostty.Terminal.write(term, "This is \e[38;2;255;128;0morange\e[0m via 24-bit color.\r\n")
Ghostty.Terminal.write(term, "\e[4mUnderlined\e[0m and \e[1mbold\e[0m text.\r\n")

{col, row} = Ghostty.Terminal.cursor(term)
IO.puts("Cursor at col=#{col}, row=#{row}")

{:ok, plain} = Ghostty.Terminal.snapshot(term)
IO.puts("\n--- Plain text ---")
IO.puts(plain)

{:ok, html} = Ghostty.Terminal.snapshot(term, :html)
IO.puts("--- HTML (#{byte_size(html)} bytes) ---")
IO.puts(String.slice(html, 0, 200) <> "...")

GenServer.stop(term)
