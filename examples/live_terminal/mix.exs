defmodule LiveTerminal.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_terminal,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {LiveTerminal.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ghostty, path: "../.."},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:phoenix_test, "~> 0.10", only: :test, runtime: false},
      {:phoenix_test_playwright, "~> 0.13", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind live_terminal", "esbuild live_terminal"],
      "assets.deploy": ["tailwind live_terminal --minify", "esbuild live_terminal --minify"]
    ]
  end
end
