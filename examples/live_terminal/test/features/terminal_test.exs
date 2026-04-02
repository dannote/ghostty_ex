defmodule Features.TerminalTest do
  use PhoenixTest.Playwright.Case,
    async: false,
    headless: true

  import PhoenixTest.Playwright, only: [screenshot: 2]

  test "bash terminal renders prompt, command output, and colors", %{conn: conn} do
    conn
    |> visit("/?banner=1&cmd=echo%20hello")
    |> assert_has("#term[phx-hook='GhosttyTerminal']")
    |> assert_has("#term pre", text: "$", timeout: 30_000)
    |> assert_has("#term pre", text: "hello", timeout: 30_000)
    |> assert_has("#term pre", text: "Welcome to Ghostty!", timeout: 30_000)
    |> assert_has("#term pre span[style*='color']")
    |> screenshot("01-bash-terminal.png")
  end
end
