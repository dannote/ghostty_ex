# Terminal-aware diff — compare two ANSI outputs by their visual content.
# Strips escape codes, handles cursor movement, carriage returns, etc.
#
#   mix run examples/diff.exs

defmodule TermDiff do
  def to_plain(ansi, cols \\ 120) do
    {:ok, term} = Ghostty.Terminal.start_link(cols: cols, rows: 50)
    Ghostty.Terminal.write(term, ansi)
    {:ok, text} = Ghostty.Terminal.snapshot(term)
    GenServer.stop(term)
    String.trim_trailing(text)
  end
end

before = "\e[32m  3 tests, 0 failures\e[0m\r\n\r\nFinished in 0.04 seconds\r\n"
after_ = "\e[31m  3 tests, 1 failure\e[0m\r\n\r\nFinished in 0.08 seconds\r\n"

plain_before = TermDiff.to_plain(before)
plain_after = TermDiff.to_plain(after_)

IO.puts("Before: #{inspect(plain_before)}")
IO.puts("After:  #{inspect(plain_after)}")

diff = String.myers_difference(plain_before, plain_after)

IO.puts("\nMyers diff:")

for {op, text} <- diff do
  case op do
    :eq -> IO.write(text)
    :del -> IO.write(IO.ANSI.red() <> IO.ANSI.crossed_out() <> text <> IO.ANSI.reset())
    :ins -> IO.write(IO.ANSI.green() <> IO.ANSI.underline() <> text <> IO.ANSI.reset())
  end
end

IO.puts("")
