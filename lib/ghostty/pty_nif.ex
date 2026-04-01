defmodule Ghostty.PTY.Nif do
  @moduledoc false

  @version Mix.Project.config()[:version]

  use ZiglerPrecompiled,
    otp_app: :ghostty,
    base_url: "https://github.com/dannote/ghostty_ex/releases/download/v#{@version}",
    version: @version,
    force_build: System.get_env("GHOSTTY_BUILD") in ["1", "true"],
    targets: ~w(x86_64-linux-gnu aarch64-linux-gnu aarch64-macos-none),
    zig_code_path: "pty_nif.zig",
    resources: [:PtyResource],
    nifs: [
      nif_pty_open: 5,
      nif_pty_write: 2,
      nif_pty_resize: 3,
      nif_pty_close: 1
    ]
end
