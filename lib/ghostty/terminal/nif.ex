defmodule Ghostty.Terminal.Nif do
  @moduledoc false

  @version Mix.Project.config()[:version]

  @ghostty_vt_lib (case :os.type() do
                     {:unix, :darwin} -> "lib/libghostty-vt.dylib"
                     _ -> "lib/libghostty-vt.so"
                   end)

  use ZiglerPrecompiled,
    otp_app: :ghostty,
    base_url: "https://github.com/dannote/ghostty_ex/releases/download/v#{@version}",
    version: @version,
    force_build: System.get_env("GHOSTTY_BUILD") in ["1", "true"],
    targets: ~w(x86_64-linux-gnu aarch64-linux-gnu aarch64-macos-none),
    zig_code_path: "ghostty_nif.zig",
    c: [
      include_dirs: [{:priv, "include"}],
      link_lib: [{:priv, @ghostty_vt_lib}]
    ],
    resources: [:TerminalResource],
    nifs: [
      nif_new: 3,
      nif_vt_write: 2,
      nif_resize: 3,
      nif_reset: 1,
      nif_snapshot: 2,
      nif_scroll: 2,
      nif_get_cursor: 1,
      nif_set_effect_pid: 2,
      nif_encode_key: 6,
      nif_encode_mouse: 6,
      nif_encode_focus: 1,
      nif_render_cells: 1
    ]
end
