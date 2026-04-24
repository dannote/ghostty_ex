defmodule Ghostty.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/dannote/ghostty_ex"

  def project do
    [
      app: :ghostty,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:ex_unit, :mix], ignore_warnings: ".dialyzer_ignore.exs"],
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
      compile: [&compile_with_ghostty_priv/1],
      lint: [
        "format --check-formatted",
        "credo --strict",
        "ex_dna",
        "cmd zlint lib/ghostty/terminal/ghostty_nif.zig lib/ghostty/pty_nif.zig"
      ],
      "fuzz.sanity": "cmd --cd fuzz zig build test",
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

  defp compile_with_ghostty_priv(args) do
    sync_build_priv_if_needed()
    Mix.Tasks.Compile.run(args)
    bundle_typescript()
  end

  defp sync_build_priv_if_needed do
    if System.get_env("GHOSTTY_BUILD") in ["1", "true"] do
      root = Path.dirname(Mix.Project.project_file())
      src_priv = Path.join(root, "priv")
      src_lib = Path.join(src_priv, "lib")
      src_include = Path.join(src_priv, "include")

      if File.dir?(src_lib) do
        env = to_string(Mix.env())
        dest_priv = Path.join([root, "_build", env, "lib", "ghostty", "priv"])
        dest_lib = Path.join(dest_priv, "lib")
        dest_include = Path.join(dest_priv, "include")

        File.mkdir_p!(dest_lib)

        src_lib
        |> File.ls!()
        |> Enum.filter(&String.contains?(&1, "ghostty-vt"))
        |> Enum.each(fn file ->
          File.cp!(Path.join(src_lib, file), Path.join(dest_lib, file))
        end)

        if File.dir?(src_include) do
          File.rm_rf!(dest_include)
          File.mkdir_p!(Path.dirname(dest_include))
          File.cp_r!(src_include, dest_include)
        end

        fix_dylib_install_name(dest_lib)
      end
    end
  end

  defp fix_dylib_install_name(lib_dir) do
    case :os.type() do
      {:unix, :darwin} ->
        dylib = Path.join(lib_dir, "libghostty-vt.dylib")

        if File.exists?(dylib) do
          absolute_id = Path.expand(dylib)

          for file <- File.ls!(lib_dir), String.ends_with?(file, ".dylib") do
            path = Path.join(lib_dir, file)
            _ = System.cmd("install_name_tool", ["-id", absolute_id, path], stderr_to_stdout: true)
          end
        end

      _ ->
        :ok
    end
  end

  defp bundle_typescript do
    if Code.ensure_loaded?(OXC) do
      Mix.Compilers.GhosttyJS.run([])
    end
  end

  defp deps do
    [
      {:zigler_precompiled, "~> 0.1.3"},
      {:zigler, "~> 0.15.2", runtime: false, optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.2", only: [:dev, :test], runtime: false},
      {:oxc, "~> 0.5"},
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
        lib/ghostty/tty.ex
        lib/ghostty/key_decoder.ex
        lib/ghostty/key_event.ex
        lib/ghostty/mouse_event.ex
        lib/ghostty/pty.ex
        lib/ghostty/test.ex
        lib/ghostty/pty_nif.ex
        lib/ghostty/pty_nif.zig
        lib/ghostty/live_terminal.ex
        lib/ghostty/live_terminal/component.ex
        lib/ghostty/mods.ex
        lib/ghostty.ex
        lib/mix
        priv/ts
        examples/*.exs
        mix.exs README.md LICENSE CHANGELOG.md .formatter.exs
        checksum-Ghostty.Terminal.Nif.exs
        checksum-Ghostty.PTY.Nif.exs
      ]
    ]
  end

  defp docs do
    [
      main: "Ghostty",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      groups_for_modules: [
        Core: [Ghostty, Ghostty.Terminal, Ghostty.PTY, Ghostty.TTY],
        "Cell & Events": [Ghostty.Terminal.Cell, Ghostty.KeyEvent, Ghostty.MouseEvent, Ghostty.KeyDecoder],
        Testing: [Ghostty.Test],
        LiveView: [Ghostty.LiveTerminal, Ghostty.LiveTerminal.Component],
        Internal: [Ghostty.Terminal.Nif, Ghostty.PTY.Nif]
      ]
    ]
  end
end
