import Config

config :live_terminal, LiveTerminalWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: true,
  check_origin: false

config :phoenix_test,
  otp_app: :live_terminal,
  playwright: [js_logger: false]
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
