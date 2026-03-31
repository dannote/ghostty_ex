defmodule Ghostty.PTY.Nif do
  @moduledoc false

  use Zig,
    otp_app: :ghostty,
    zig_code_path: "pty_nif.zig",
    resources: [:PtyResource],
    nifs: [
      nif_pty_open: [],
      nif_pty_write: [],
      nif_pty_resize: [],
      nif_pty_close: []
    ]
end
