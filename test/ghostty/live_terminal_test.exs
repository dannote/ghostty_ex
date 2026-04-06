defmodule Ghostty.LiveTerminalTest do
  use ExUnit.Case, async: true

  alias Ghostty.LiveTerminal
  import Phoenix.LiveViewTest, only: [render_component: 2]

  defp key_params(key, opts \\ []) do
    %{
      "key" => key,
      "shiftKey" => Keyword.get(opts, :shift, false),
      "ctrlKey" => Keyword.get(opts, :ctrl, false),
      "altKey" => Keyword.get(opts, :alt, false),
      "metaKey" => Keyword.get(opts, :meta, false)
    }
  end

  describe "terminal/1" do
    test "renders a div with the hook and data attributes" do
      html = render_component(&LiveTerminal.terminal/1, id: "t1", cols: 80, rows: 24)

      assert html =~ ~s(id="t1")
      assert html =~ ~s(phx-hook="GhosttyTerminal")
      assert html =~ ~s(data-cols="80")
      assert html =~ ~s(data-rows="24")
    end

    test "renders custom dimensions and class" do
      html = render_component(&LiveTerminal.terminal/1, id: "t2", cols: 120, rows: 40, class: "my-term")

      assert html =~ ~s(data-cols="120")
      assert html =~ ~s(data-rows="40")
      assert html =~ ~s(class="my-term")
    end

    test "renders fit flag when enabled" do
      html = render_component(&LiveTerminal.terminal/1, id: "t-fit", fit: true)

      assert html =~ ~s(data-fit="true")
    end

    test "renders autofocus flag when enabled" do
      html = render_component(&LiveTerminal.terminal/1, id: "t-focus", autofocus: true)

      assert html =~ ~s(data-autofocus="true")
    end

    test "passes through global attributes" do
      html = render_component(&LiveTerminal.terminal/1, id: "t3", "data-test": "yes")

      assert html =~ ~s(data-test="yes")
    end
  end

  describe "key_event_from_params/1" do
    test "parses a letter key" do
      assert %Ghostty.KeyEvent{key: :a, action: :press, utf8: "a"} =
               LiveTerminal.key_event_from_params(key_params("a"))
    end

    test "parses Enter" do
      assert %Ghostty.KeyEvent{key: :enter} = LiveTerminal.key_event_from_params(key_params("Enter"))
    end

    test "parses arrow keys" do
      assert %Ghostty.KeyEvent{key: :arrow_up} = LiveTerminal.key_event_from_params(key_params("ArrowUp"))
    end

    test "parses modifiers" do
      event = LiveTerminal.key_event_from_params(key_params("a", shift: true, ctrl: true))
      assert :shift in event.mods
      assert :ctrl in event.mods
    end

    test "parses digits" do
      assert %Ghostty.KeyEvent{key: :digit_5} = LiveTerminal.key_event_from_params(key_params("5"))
    end

    test "parses function keys" do
      assert %Ghostty.KeyEvent{key: :f1} = LiveTerminal.key_event_from_params(key_params("F1"))
    end

    test "returns :none for unrecognized keys" do
      assert :none = LiveTerminal.key_event_from_params(key_params("Dead"))
      assert :none = LiveTerminal.key_event_from_params(key_params("Unidentified"))
      assert :none = LiveTerminal.key_event_from_params(key_params("AudioVolumeUp"))
    end
  end

  describe "handle_key/2" do
    setup do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
      %{term: term}
    end

    test "encodes Enter", %{term: term} do
      assert {:ok, "\r"} = LiveTerminal.handle_key(term, key_params("Enter"))
    end

    test "encodes Escape", %{term: term} do
      assert {:ok, "\e"} = LiveTerminal.handle_key(term, key_params("Escape"))
    end

    test "encodes Ctrl+C", %{term: term} do
      assert {:ok, <<3>>} = LiveTerminal.handle_key(term, key_params("c", ctrl: true))
    end

    test "encodes arrow keys", %{term: term} do
      for js_key <- ~w(ArrowUp ArrowDown ArrowLeft ArrowRight) do
        assert {:ok, data} = LiveTerminal.handle_key(term, key_params(js_key))
        assert String.starts_with?(data, "\e")
      end
    end

    test "encodes function keys", %{term: term} do
      for n <- 1..12 do
        assert {:ok, data} = LiveTerminal.handle_key(term, key_params("F#{n}"))
        assert String.starts_with?(data, "\e")
      end
    end

    test "encodes space", %{term: term} do
      assert {:ok, " "} = LiveTerminal.handle_key(term, key_params(" "))
    end

    test "encodes digit keys", %{term: term} do
      for d <- 0..9 do
        assert {:ok, data} = LiveTerminal.handle_key(term, key_params("#{d}"))
        assert is_binary(data)
      end
    end

    test "returns :none for unrecognized keys", %{term: term} do
      assert :none = LiveTerminal.handle_key(term, key_params("Dead"))
    end

    test "does not crash server on unknown keys", %{term: term} do
      assert :none = LiveTerminal.handle_key(term, key_params("AudioVolumeUp"))
      assert Process.alive?(term)
    end
  end

  describe "mouse_event_from_params/1" do
    test "parses mouse params" do
      assert %Ghostty.MouseEvent{
               action: :press,
               button: :left,
               x: 15.0,
               y: 30.0,
               mods: [:shift]
             } =
               LiveTerminal.mouse_event_from_params(%{
                 "action" => "press",
                 "button" => "left",
                 "x" => 15,
                 "y" => "30.0",
                 "shiftKey" => true
               })
    end

    test "returns :none for invalid mouse params" do
      assert :none = LiveTerminal.mouse_event_from_params(%{"action" => "drag"})
    end
  end

  describe "handle_mouse/2" do
    test "encodes mouse events when mouse reporting is enabled" do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 80, rows: 24)
      Ghostty.Terminal.write(term, "\e[?1000h\e[?1006h")

      assert {:ok, data} =
               LiveTerminal.handle_mouse(term, %{
                 "action" => "press",
                 "button" => "left",
                 "x" => 15,
                 "y" => 30,
                 "shiftKey" => false,
                 "ctrlKey" => false,
                 "altKey" => false,
                 "metaKey" => false
               })

      assert String.starts_with?(data, "\e[<")
    end
  end

  describe "handle_text/2" do
    test "writes committed text input to the terminal" do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 10, rows: 2)

      assert :ok = LiveTerminal.handle_text(term, "hello")
      assert {:ok, text} = Ghostty.Terminal.snapshot(term)
      assert text =~ "hello"
    end
  end

  describe "handle_resize/4" do
    test "resizes the terminal" do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 10, rows: 2)

      assert :ok = LiveTerminal.handle_resize(term, 20, 5)
      assert {20, 5} = Ghostty.Terminal.size(term)
    end
  end

  describe "handle_focus/1" do
    test "encodes focus gained and lost events" do
      assert {:ok, "\e[I"} = LiveTerminal.handle_focus(true)
      assert {:ok, "\e[O"} = LiveTerminal.handle_focus(false)
    end
  end

  describe "cells_payload/1" do
    test "returns JSON-safe nested lists" do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 10, rows: 2)
      Ghostty.Terminal.write(term, "Hi\r\n")

      payload = LiveTerminal.cells_payload(term)

      assert is_list(payload)
      assert length(payload) == 2

      [[char, fg, bg, flags] | _] = hd(payload)
      assert char == "H"
      assert is_nil(fg) or is_list(fg)
      assert is_nil(bg) or is_list(bg)
      assert is_integer(flags)
    end

    test "converts color tuples to lists" do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 10, rows: 2)
      Ghostty.Terminal.write(term, "\e[31mR\e[0m\r\n")

      [[_char, fg, _bg, _flags] | _] = hd(LiveTerminal.cells_payload(term))
      assert is_list(fg) or is_nil(fg)
    end
  end

  describe "cursor_payload/1" do
    test "returns JSON-safe cursor metadata" do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 10, rows: 2)
      Ghostty.Terminal.write(term, "Hi")

      assert %{
               x: 2,
               y: 0,
               visible: true,
               blinking: false,
               style: :block,
               wide_tail: false,
               color: color
             } = LiveTerminal.cursor_payload(term)

      assert is_nil(color) or is_list(color)
    end
  end

  describe "mouse_payload/1" do
    test "returns JSON-safe mouse mode metadata" do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 10, rows: 2)
      Ghostty.Terminal.write(term, "\e[?1000h\e[?1006h")

      assert %{tracking: true, normal: true, sgr: true} = LiveTerminal.mouse_payload(term)
    end
  end

  describe "render_payload/2" do
    test "returns map with id, cells, cursor, and mouse state" do
      {:ok, term} = Ghostty.Terminal.start_link(cols: 10, rows: 2)
      payload = LiveTerminal.render_payload("my-term", term)

      assert %{id: "my-term", cells: cells, cursor: cursor, mouse: mouse} = payload
      assert is_list(cells)
      assert is_map(cursor)
      assert Map.has_key?(cursor, :style)
      assert is_map(mouse)
      assert Map.has_key?(mouse, :tracking)
    end
  end
end
