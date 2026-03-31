defmodule Ghostty.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dannote/ghostty_ex"

  def project do
    [
      app: :ghostty,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: []],
      name: "Ghostty",
      description: "Terminal emulator library for the BEAM — libghostty-vt NIFs with OTP integration.",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp aliases do
    [
      lint: [
        "format --check-formatted",
        "credo --strict",
        "ex_dna"
      ],
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "ex_dna",
        "test"
      ]
    ]
  end

  defp deps do
    [
      {:zigler_precompiled, "~> 0.1.2"},
      {:zigler, "~> 0.15.2", runtime: false, optional: true},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w[
        lib/ghostty/terminal/nif.ex
        lib/ghostty/terminal/ghostty_nif.zig
        lib/ghostty/terminal/cell.ex
        lib/ghostty/terminal.ex
        lib/ghostty/key_event.ex
        lib/ghostty/mouse_event.ex
        lib/ghostty/port.ex
        lib/ghostty/mods.ex
        lib/ghostty.ex
        lib/mix
        examples
        mix.exs README.md LICENSE CHANGELOG.md .formatter.exs
        checksum-Ghostty.Terminal.Nif.exs
      ]
    ]
  end

  defp docs do
    [
      main: "Ghostty",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      groups_for_modules: [
        Core: [Ghostty, Ghostty.Terminal, Ghostty.Port],
        "Cell & Events": [Ghostty.Terminal.Cell, Ghostty.KeyEvent, Ghostty.MouseEvent],
        Internal: [Ghostty.Terminal.Nif]
      ]
    ]
  end
end
