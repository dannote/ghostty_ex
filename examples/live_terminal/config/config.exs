import Config

config :live_terminal, LiveTerminalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: String.duplicate("a", 64),
  render_errors: [formats: [html: LiveTerminalWeb.ErrorHTML]],
  pubsub_server: LiveTerminal.PubSub,
  live_view: [signing_salt: "ghostty_live"]

config :esbuild,
  version: "0.25.0",
  live_terminal: [
    args: ~w(js/app.js --bundle --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.1.10",
  live_terminal: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :console, format: "$time $metadata[$level] $message\n"
config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
