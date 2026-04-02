defmodule Features.TerminalTest do
  use PhoenixTest.Playwright.Case,
    async: false,
    headless: true

  import PhoenixTest.Playwright, only: [evaluate: 3, screenshot: 2]

  test "bash terminal demo renders output and disables local selection during mouse reporting", %{
    conn: conn
  } do
    encoded_cmd = URI.encode_www_form("printf '\\033[?1000h\\033[?1006h'; echo hello")

    conn
    |> visit("/?banner=1&cmd=#{encoded_cmd}")
    |> assert_has("#term[phx-hook='GhosttyTerminal']")
    |> assert_has("#term pre", text: "$", timeout: 30_000)
    |> assert_has("#term pre", text: "hello", timeout: 30_000)
    |> assert_has("#term pre", text: "Welcome to Ghostty!", timeout: 30_000)
    |> assert_has("#term pre span[style*='color']")
    |> screenshot("01-bash-terminal.png")
    |> evaluate(
      ~S"""
      (() => {
        const term = document.querySelector("#term")
        const pre = term.querySelector("pre")
        const rect = pre.getBoundingClientRect()
        const startX = rect.left + 24
        const endX = rect.left + 140
        const y = rect.top + 20

        term.dispatchEvent(new MouseEvent("mousedown", {
          bubbles: true,
          button: 0,
          buttons: 1,
          clientX: startX,
          clientY: y,
        }))

        window.dispatchEvent(new MouseEvent("mousemove", {
          bubbles: true,
          button: 0,
          buttons: 1,
          clientX: endX,
          clientY: y,
        }))

        window.dispatchEvent(new MouseEvent("mouseup", {
          bubbles: true,
          button: 0,
          buttons: 0,
          clientX: endX,
          clientY: y,
        }))

        return {
          selectionRects: term.querySelector("[data-ghostty-selection-layer]").childElementCount,
        }
      })()
      """,
      fn result ->
        assert result["selectionRects"] == 0
      end
    )
  end
end
