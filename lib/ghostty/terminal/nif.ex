defmodule Ghostty.Terminal.Nif do
  @moduledoc false

  # Phase 1 stub — replaced with Zigler NIFs once libghostty-vt builds.
  #
  # The real implementation uses:
  #
  #     use Zig,
  #       otp_app: :ghostty,
  #       c: [
  #         include_dirs: [{:priv, "include"}],
  #         link_lib: [{:priv, "lib/libghostty-vt"}]
  #       ],
  #       resources: [:TerminalResource],
  #       nifs: [
  #         nif_new:        [:dirty_cpu],
  #         nif_free:       [:dirty_cpu],
  #         nif_vt_write:   [:dirty_cpu],
  #         nif_resize:     [:dirty_cpu],
  #         nif_reset:      [:dirty_cpu],
  #         nif_snapshot:   [:dirty_cpu],
  #         nif_scroll:     [:dirty_cpu],
  #         nif_get_cursor: [:dirty_cpu],
  #       ]

  def nif_new(_cols, _rows, _max_scrollback) do
    raise "libghostty-vt NIF not loaded — build requires Zig 0.15+ with macOS SDK support"
  end

  def nif_free(_ref), do: :ok

  def nif_vt_write(_ref, _data) do
    raise "libghostty-vt NIF not loaded"
  end

  def nif_resize(_ref, _cols, _rows) do
    raise "libghostty-vt NIF not loaded"
  end

  def nif_reset(_ref) do
    raise "libghostty-vt NIF not loaded"
  end

  def nif_snapshot(_ref, _format) do
    raise "libghostty-vt NIF not loaded"
  end

  def nif_scroll(_ref, _delta) do
    raise "libghostty-vt NIF not loaded"
  end

  def nif_get_cursor(_ref) do
    raise "libghostty-vt NIF not loaded"
  end
end
