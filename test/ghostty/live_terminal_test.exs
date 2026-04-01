defmodule Ghostty.LiveTerminalTest do
  use ExUnit.Case, async: true

  alias Ghostty.LiveTerminal

  describe "terminal/1" do
    test "renders a div with the hook and data attributes" do
      assigns = %{id: "t1", cols: 80, rows: 24, class: ""}
      html = Phoenix.LiveViewTest.rendered_to_string(LiveTerminal.terminal(assigns))

      assert html =~ ~s(id="t1")
      assert html =~ ~s(phx-hook="GhosttyTerminal")
      assert html =~ ~s(data-cols="80")
      assert html =~ ~s(data-rows="24")
    end

    test "renders custom dimensions and class" do
      assigns = %{id: "t2", cols: 120, rows: 40, class: "my-term"}
      html = Phoenix.LiveViewTest.rendered_to_string(LiveTerminal.terminal(assigns))

      assert html =~ ~s(data-cols="120")
      assert html =~ ~s(data-rows="40")
      assert html =~ ~s(class="my-term")
    end
  end

  describe "handle_key/2" do
    setup do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
      %{term: term}
    end

    test "encodes a simple letter key", %{term: term} do
      params = %{"key" => "a", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
      assert {:ok, data} = LiveTerminal.handle_key(term, params)
      assert is_binary(data)
    end

    test "encodes Enter key", %{term: term} do
      params = %{"key" => "Enter", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
      assert {:ok, data} = LiveTerminal.handle_key(term, params)
      assert data == "\r"
    end

    test "encodes Escape key", %{term: term} do
      params = %{"key" => "Escape", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
      assert {:ok, data} = LiveTerminal.handle_key(term, params)
      assert data == "\e"
    end

    test "encodes arrow keys", %{term: term} do
      for js_key <- ~w(ArrowUp ArrowDown ArrowLeft ArrowRight) do
        params = %{"key" => js_key, "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
        assert {:ok, data} = LiveTerminal.handle_key(term, params)
        assert String.starts_with?(data, "\e")
      end
    end

    test "encodes Ctrl+C", %{term: term} do
      params = %{"key" => "c", "shiftKey" => false, "ctrlKey" => true, "altKey" => false, "metaKey" => false}
      assert {:ok, data} = LiveTerminal.handle_key(term, params)
      assert data == <<3>>
    end

    test "passes modifier flags through", %{term: term} do
      params = %{"key" => "a", "shiftKey" => true, "ctrlKey" => false, "altKey" => true, "metaKey" => false}
      assert {:ok, _data} = LiveTerminal.handle_key(term, params)
    end

    test "returns :none for unidentified keys", %{term: term} do
      params = %{"key" => "Unidentified", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
      assert :none = LiveTerminal.handle_key(term, params)
    end

    test "returns :none for exotic keys like Dead", %{term: term} do
      params = %{"key" => "Dead", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
      assert :none = LiveTerminal.handle_key(term, params)
    end

    test "encodes function keys", %{term: term} do
      for n <- 1..12 do
        params = %{"key" => "F#{n}", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
        assert {:ok, data} = LiveTerminal.handle_key(term, params), "F#{n} should encode"
        assert String.starts_with?(data, "\e")
      end
    end

    test "encodes space key", %{term: term} do
      params = %{"key" => " ", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
      assert {:ok, data} = LiveTerminal.handle_key(term, params)
      assert data == " "
    end

    test "encodes digit keys", %{term: term} do
      for d <- 0..9 do
        params = %{"key" => "#{d}", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
        assert {:ok, data} = LiveTerminal.handle_key(term, params), "digit #{d} should encode"
        assert is_binary(data)
      end
    end

    test "does not crash the terminal server on unknown keys", %{term: term} do
      params = %{"key" => "AudioVolumeUp", "shiftKey" => false, "ctrlKey" => false, "altKey" => false, "metaKey" => false}
      assert :none = LiveTerminal.handle_key(term, params)
      assert Process.alive?(term)
    end
  end
end
