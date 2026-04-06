defmodule Features.TerminalTest do
  use PhoenixTest.Playwright.Case,
    async: false,
    headless: true

  import PhoenixTest.Playwright,
    only: [drag: 3, evaluate: 3, evaluate: 4, screenshot: 2]

  test "fit mode renders a flush-left prompt on startup", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("#term-1[phx-hook='GhosttyTerminal']")
    |> evaluate(
      ~S"""
      (() => new Promise((resolve) => {
        const started = performance.now()

        const poll = () => {
          const term = document.querySelector("#term-1")
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

  test "demo controls drive a colorized mouse-reporting session", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("#demo-controls")
    |> evaluate(
      ~S"""
      (() => new Promise((resolve) => {
        const input = document.getElementById("startup-command")
        input?.focus()

        setTimeout(() => {
          resolve({activeId: document.activeElement?.id ?? null})
        }, 400)
      }))()
      """,
      [timeout: 2_000],
      fn result ->
        assert result["activeId"] == "startup-command"
      end
    )
    |> PhoenixTest.fill_in("#startup-command", "Startup command",
      with:
        "printf '\\033[31mred\\033[0m \\033[32mgreen\\033[0m \\033[34mblue\\033[0m\\n\\033[?1000h\\033[?1006h'; echo hello"
    )
    |> PhoenixTest.click_button("#demo-controls", "Restart session")
    |> assert_has("#term-2[phx-hook='GhosttyTerminal']")
    |> evaluate(
      ~S"""
      (() => new Promise((resolve) => {
        const started = performance.now()

        const poll = () => {
          const term = document.querySelector("#term-2")
          const pre = term?.querySelector("pre")
          const text = pre?.innerText || ""

          if (pre && text.includes("hello") && text.includes("red") && text.includes("green") && text.includes("blue")) {
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
          const term = document.querySelector("#term-2")
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
    |> drag("#term-2",
      to: "#term-2",
      playwright: [sourcePosition: %{x: 24, y: 20}, targetPosition: %{x: 140, y: 20}]
    )
    |> evaluate(
      ~S"""
      (() => {
        const term = document.querySelector("#term-2")
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
