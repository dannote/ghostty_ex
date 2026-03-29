defmodule Ghostty.Terminal.Nif do
  @moduledoc false

  @version Mix.Project.config()[:version]

  use ZiglerPrecompiled,
    otp_app: :ghostty,
    base_url: "https://github.com/dannote/ghostty_ex/releases/download/v#{@version}",
    version: @version,
    force_build: System.get_env("GHOSTTY_BUILD") in ["1", "true"],
    targets: ~w(x86_64-linux-gnu aarch64-linux-gnu aarch64-macos-none),
    zig_code_path: "ghostty_nif.zig",
    c: [
      include_dirs: [{:priv, "include"}],
      link_lib: [{:priv, "lib/libghostty-vt.dylib"}]
    ],
    resources: [:TerminalResource],
    nifs: [
      nif_new: 3,
      nif_vt_write: 2,
      nif_resize: 3,
      nif_reset: 1,
      nif_snapshot: 2,
      nif_scroll: 2,
      nif_get_cursor: 1
    ]
end
