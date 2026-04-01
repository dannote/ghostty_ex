defmodule LiveTerminalWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :live_terminal

  @session_options [
    store: :cookie,
    key: "_live_terminal_key",
    signing_salt: "ghostty_test"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :live_terminal,
    gzip: false,
    only: ~w(assets)

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.Session, @session_options
  plug LiveTerminalWeb.Router
end
