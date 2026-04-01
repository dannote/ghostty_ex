defmodule Features.TerminalTest do
  use PhoenixTest.Playwright.Case,
    async: false,
    headless: true

  import PhoenixTest.Playwright, only: [evaluate: 2, evaluate: 3, screenshot: 2]

  test "terminal mounts and renders welcome text", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("#term[phx-hook='GhosttyTerminal']")
    |> assert_has("#term pre", text: "Welcome", timeout: 5_000)
    |> screenshot("01-welcome.png")
  end

  test "keypress updates terminal content", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("#term pre", text: "$ ", timeout: 5_000)
    |> evaluate("""
      const el = document.querySelector('#term');
      el.focus();
      ['h', 'i'].forEach(key =>
        el.dispatchEvent(new KeyboardEvent('keydown', {key, bubbles: true}))
      );
    """)
    |> assert_has("#term pre", text: "hi", timeout: 5_000)
    |> screenshot("02-keypress.png")
  end

  test "terminal renders colored text with styled spans", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("#term pre", timeout: 5_000)
    |> evaluate("!!document.querySelector('#term pre span[style]')", fn result ->
      assert result == true, "Expected styled spans for colored text"
    end)
    |> screenshot("03-colors.png")
  end

  test "terminal hook sets up keyboard focus", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("#term pre", timeout: 5_000)
    |> evaluate("document.querySelector('#term').tabIndex", fn result ->
      assert result == 0, "Expected tabIndex=0 for keyboard focus"
    end)
  end
end
