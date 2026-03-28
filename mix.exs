defmodule Ghostty.MixProject do
  use Mix.Project

  def project do
    [
      app: :ghostty,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: [:ghostty_vt] ++ Mix.compilers(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:zigler, "~> 0.15.2", runtime: false}
    ]
  end
end
