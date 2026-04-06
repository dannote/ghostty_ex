defmodule Features.TerminalTest do
  use PhoenixTest.Playwright.Case,
    async: false,
    headless: true

  import PhoenixTest.Playwright, only: [drag: 3, evaluate: 3, evaluate: 4, screenshot: 2]

  test "fit mode renders a flush-left prompt on startup", %{conn: conn} do
    conn
    |> visit("/?fit=1")
    |> assert_has("#term[phx-hook='GhosttyTerminal']")
    |> evaluate(
      ~S"""
      (() => new Promise((resolve) => {
        const started = performance.now()

        const poll = () => {
          const term = document.querySelector("#term")
          const pre = term?.querySelector("pre")
          const lines = (pre?.innerText || "").split("\n")
          const promptLine = lines.find((line) => line.includes("ghostty$"))

          if (promptLine) {
            resolve({promptIndex: promptLine.indexOf("ghostty$"), promptLine})
            return
          }

          if (performance.now() - started > 5000) {
            resolve({promptIndex: null, promptLine: null, lines: lines.slice(0, 4)})
            return
          }

          setTimeout(poll, 50)
        }

        poll()
      }))()
      """,
      [timeout: 6_000],
      fn result ->
        assert result["promptIndex"] == 0
      end
    )
  end

  test "fit mode renders a visible terminal and disables local selection during mouse reporting",
       %{
         conn: conn
       } do
    encoded_cmd = URI.encode_www_form("printf '\\033[?1000h\\033[?1006h'; echo hello")

    conn
    |> visit("/?banner=1&fit=1&cmd=#{encoded_cmd}")
    |> assert_has("#term[phx-hook='GhosttyTerminal']")
    |> evaluate(
      ~S"""
      (() => new Promise((resolve) => {
        const started = performance.now()

        const poll = () => {
          const term = document.querySelector("#term")
          const pre = term?.querySelector("pre")
          const text = pre?.innerText || ""

          if (pre && text.includes("Welcome to Ghostty!") && text.includes("hello")) {
            resolve({
              hasPre: true,
              width: pre.getBoundingClientRect().width,
              hasColor: !!pre.querySelector("span[style*='color']"),
            })
            return
          }

          if (performance.now() - started > 10000) {
            resolve({
              hasPre: !!pre,
              width: pre ? pre.getBoundingClientRect().width : 0,
              hasColor: !!pre?.querySelector("span[style*='color']"),
              text,
            })
            return
          }

          setTimeout(poll, 100)
        }

        poll()
      }))()
      """,
      [timeout: 12_000],
      fn result ->
        assert result["hasPre"]
        assert result["width"] > 0
        assert result["hasColor"]
      end
    )
    |> evaluate(
      ~S"""
      (() => new Promise((resolve) => {
        const started = performance.now()

        const poll = () => {
          const term = document.querySelector("#term")
          const active = document.activeElement
          const activeInsideTerm = term?.contains(active) ?? false
          const activeIsTerminal = active?.tagName === "TEXTAREA" || active === term

          if (activeInsideTerm && activeIsTerminal) {
            resolve({activeIsTerminal, activeInsideTerm})
            return
          }

          if (performance.now() - started > 3000) {
            resolve({activeIsTerminal, activeInsideTerm, activeTag: active?.tagName ?? null})
            return
          }

          setTimeout(poll, 50)
        }

        poll()
      }))()
      """,
      [timeout: 4_000],
      fn result ->
        assert result["activeIsTerminal"]
        assert result["activeInsideTerm"]
      end
    )
    |> drag("#term",
      to: "#term",
      playwright: [sourcePosition: %{x: 24, y: 20}, targetPosition: %{x: 140, y: 20}]
    )
    |> evaluate(
      ~S"""
      (() => {
        const term = document.querySelector("#term")
        return {
          selectionRects: term.querySelector("[data-ghostty-selection-layer]").childElementCount,
        }
      })()
      """,
      fn result ->
        assert result["selectionRects"] == 0
      end
    )
    |> screenshot("01-bash-terminal-fit.png")
  end
end
