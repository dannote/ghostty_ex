# Record command output as a styled HTML file.
# Preserves all colors, bold, italic, underline, 24-bit color, etc.
#
#   mix run examples/html_recorder.exs "ls -la --color=always"
#   mix run examples/html_recorder.exs "mix test --color"
#   open output.html

[cmd | _] = System.argv()

{:ok, term} = Ghostty.Terminal.start_link(cols: 120, rows: 50)

{output, _status} = System.cmd("bash", ["-c", cmd], stderr_to_stdout: true, env: [{"TERM", "xterm-256color"}])
Ghostty.Terminal.write(term, output)

{:ok, html_body} = Ghostty.Terminal.snapshot(term, :html)

html = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>#{cmd}</title>
  <style>
    body {
      background: #1e1e2e;
      padding: 20px;
      margin: 0;
    }
    pre {
      font-family: 'JetBrains Mono', 'SF Mono', 'Fira Code', monospace;
      font-size: 14px;
      line-height: 1.4;
      color: #cdd6f4;
    }
  </style>
</head>
<body>
  <pre>#{html_body}</pre>
</body>
</html>
"""

File.write!("output.html", html)
IO.puts("Wrote output.html (#{byte_size(html)} bytes)")
