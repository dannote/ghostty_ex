defmodule Mix.Tasks.Ghostty.Setup do
  @shortdoc "Build libghostty-vt and install into priv/"

  @moduledoc """
  Clones the Ghostty source, builds libghostty-vt, and installs the
  shared library and headers into `priv/`.

  This only needs to run once. After that, `GHOSTTY_BUILD=1 mix compile`
  will find the library in `priv/` and build the NIF from source.

  Set `GHOSTTY_SOURCE_DIR` to skip cloning and use a local checkout.

  ## Examples

      mix ghostty.setup
      GHOSTTY_SOURCE_DIR=~/code/ghostty mix ghostty.setup

  """

  use Mix.Task

  @ghostty_repo "https://github.com/ghostty-org/ghostty.git"
  @ghostty_ref "baad0aa6669dc576872831752be0f30debecbfd1"

  @impl true
  def run(_args) do
    source_dir = source_dir()
    ensure_source(source_dir)
    build(source_dir)
    install(source_dir)
    install_to_build()
    Mix.shell().info("Done. Run: GHOSTTY_BUILD=1 mix compile")
  end

  defp source_dir do
    System.get_env("GHOSTTY_SOURCE_DIR") ||
      Path.join(System.tmp_dir!(), "ghostty-src")
  end

  defp ensure_source(dir) do
    if System.get_env("GHOSTTY_SOURCE_DIR") do
      unless File.dir?(dir) do
        Mix.raise("GHOSTTY_SOURCE_DIR=#{dir} does not exist")
      end

      Mix.shell().info("Using local Ghostty source: #{dir}")
    else
      if File.dir?(Path.join(dir, ".git")) do
        Mix.shell().info("Ghostty source already cloned at #{dir}")
      else
        Mix.shell().info("Cloning ghostty (#{short_ref()})...")
        cmd!("git", ["clone", "--depth", "1", @ghostty_repo, dir])
        cmd!("git", ["-C", dir, "fetch", "--depth", "1", "origin", @ghostty_ref])
        cmd!("git", ["-C", dir, "checkout", @ghostty_ref])
      end
    end
  end

  defp build(source_dir) do
    zig_out = Path.join(source_dir, "zig-out")

    if File.dir?(Path.join(zig_out, "lib")) do
      Mix.shell().info("libghostty-vt already built (delete #{zig_out} to rebuild)")
    else
      Mix.shell().info("Building libghostty-vt...")
      cmd!("zig", ["build", "-Demit-lib-vt", "-Doptimize=ReleaseFast"], cd: source_dir)
    end
  end

  defp install(source_dir) do
    zig_out = Path.join(source_dir, "zig-out")
    priv_dir = Path.join(project_root(), "priv")
    lib_dir = Path.join(priv_dir, "lib")
    include_dir = Path.join(priv_dir, "include")

    File.rm_rf!(lib_dir)
    File.rm_rf!(include_dir)
    File.mkdir_p!(lib_dir)
    File.mkdir_p!(include_dir)

    copy_libs(Path.join(zig_out, "lib"), lib_dir)
    copy_include_tree(Path.join([zig_out, "include", "ghostty"]), Path.join(include_dir, "ghostty"))
    fix_dylib_install_name(lib_dir)
  end

  defp install_to_build do
    src_priv = Path.join(project_root(), "priv")

    for env <- ["dev", "test"] do
      dest_priv = Path.join([project_root(), "_build", env, "lib", "ghostty", "priv"])
      dest_lib = Path.join(dest_priv, "lib")
      dest_include = Path.join(dest_priv, "include")

      File.rm_rf!(dest_priv)
      File.mkdir_p!(dest_lib)
      File.mkdir_p!(dest_include)

      copy_libs(Path.join(src_priv, "lib"), dest_lib)
      copy_include_tree(Path.join(src_priv, "include"), dest_include)
      fix_dylib_install_name(dest_lib)
    end
  end

  defp copy_libs(src_dir, dest_dir) do
    src_dir
    |> File.ls!()
    |> Enum.filter(&String.contains?(&1, "ghostty-vt"))
    |> Enum.each(fn file ->
      src = Path.join(src_dir, file)
      dest = Path.join(dest_dir, file)
      File.cp!(src, dest)
      Mix.shell().info("  #{dest}")
    end)
  end

  defp copy_include_tree(src, dest) do
    unless File.dir?(src) do
      Mix.raise("missing include directory: #{src}")
    end

    File.rm_rf!(dest)
    File.mkdir_p!(Path.dirname(dest))
    File.cp_r!(src, dest)
    Mix.shell().info("  #{dest}/")
  end

  defp fix_dylib_install_name(lib_dir) do
    case :os.type() do
      {:unix, :darwin} ->
        dylib = Path.join(lib_dir, "libghostty-vt.dylib")
        absolute_id = Path.expand(dylib)

        for file <- File.ls!(lib_dir), String.ends_with?(file, ".dylib") do
          path = Path.join(lib_dir, file)
          System.cmd("install_name_tool", ["-id", absolute_id, path], stderr_to_stdout: true)
        end

      _ ->
        :ok
    end
  end

  defp cmd!(cmd, args, opts \\ []) do
    {output, status} = System.cmd(cmd, args, [{:stderr_to_stdout, true} | opts])

    if status != 0 do
      Mix.raise("#{cmd} #{Enum.join(args, " ")} failed:\n#{output}")
    end
  end

  defp project_root do
    Mix.Project.project_file()
    |> Path.dirname()
  end

  defp short_ref, do: String.slice(@ghostty_ref, 0, 7)
end
