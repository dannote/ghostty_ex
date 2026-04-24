Mix.install([
  {:ghostty, path: Path.expand("..", __DIR__)}
])

{:ok, tty} = Ghostty.TTY.start_link()
Ghostty.TTY.write(tty, [IO.ANSI.clear(), IO.ANSI.home(), "Press keys; Ctrl-C exits.\r\n"])

loop = fn loop ->
  receive do
    {Ghostty.TTY, ^tty, {:key, %Ghostty.KeyEvent{key: :c, mods: [:ctrl]}}} ->
      Ghostty.TTY.write(tty, "\r\nbye\r\n")

    {Ghostty.TTY, ^tty, {:key, event}} ->
      Ghostty.TTY.write(tty, ["\r\nkey: ", inspect(event), "\r\n"])
      loop.(loop)

    {Ghostty.TTY, ^tty, {:data, data}} ->
      Ghostty.TTY.write(tty, ["\r\ndata: ", inspect(data), "\r\n"])
      loop.(loop)

    {Ghostty.TTY, ^tty, {:resize, cols, rows}} ->
      Ghostty.TTY.write(tty, ["\r\nresize: ", to_string(cols), "x", to_string(rows), "\r\n"])
      loop.(loop)
  end
end

loop.(loop)
