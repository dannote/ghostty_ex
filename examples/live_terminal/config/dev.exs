import Config

config :live_terminal, LiveTerminalWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  debug_errors: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:live_terminal, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:live_terminal, ~w(--watch)]}
  ]
