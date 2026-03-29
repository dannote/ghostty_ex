defmodule Mix.Tasks.Compile.GhosttyVt do
  @moduledoc """
  Builds libghostty-vt from the Ghostty source tree.

  Set GHOSTTY_SOURCE_DIR to point at a local checkout.
  Otherwise clones the pinned commit automatically.
  """
  use Mix.Task.Compiler

  @ghostty_repo "https://github.com/ghostty-org/ghostty.git"
  @ghostty_ref "baad0aa6669dc576872831752be0f30debecbfd1"

  @impl true
  def run(_args) do
    source_dir = ghostty_source_dir()
    ensure_source(source_dir)
    build_lib(source_dir)
    {:ok, []}
  end

  defp ghostty_source_dir do
    System.get_env("GHOSTTY_SOURCE_DIR") ||
      Path.join([Mix.Project.build_path(), "ghostty-src"])
  end

  defp ensure_source(dir) do
    if System.get_env("GHOSTTY_SOURCE_DIR") do
      unless File.dir?(dir) do
        Mix.raise("GHOSTTY_SOURCE_DIR=#{dir} does not exist")
      end
    else
      unless File.dir?(Path.join(dir, ".git")) do
        Mix.shell().info("Cloning ghostty (#{String.slice(@ghostty_ref, 0, 7)})...")

        System.cmd("git", ["clone", @ghostty_repo, dir], stderr_to_stdout: true)
        |> check_cmd!("git clone")

        System.cmd("git", ["checkout", @ghostty_ref], cd: dir, stderr_to_stdout: true)
        |> check_cmd!("git checkout")
      end
    end
  end

  defp build_lib(source_dir) do
    lib_dir = lib_output_dir()
    include_dir = include_output_dir()
    lib_name = lib_filename()

    if File.exists?(Path.join(lib_dir, lib_name)) do
      Mix.shell().info("libghostty-vt already built, skipping (delete #{lib_dir} to rebuild)")
      :ok
    else
      Mix.shell().info("Building libghostty-vt (ReleaseFast)...")
      File.mkdir_p!(lib_dir)
      File.mkdir_p!(include_dir)

      {output, status} =
        System.cmd("zig", ["build", "-Demit-lib-vt", "-Doptimize=ReleaseFast"],
          cd: source_dir,
          stderr_to_stdout: true
        )

      if status != 0 do
        Mix.raise("zig build failed:\n#{output}")
      end

      zig_out = Path.join(source_dir, "zig-out")

      Path.join(zig_out, "lib")
      |> File.ls!()
      |> Enum.filter(&String.contains?(&1, "ghostty-vt"))
      |> Enum.each(fn file ->
        File.cp!(Path.join([zig_out, "lib", file]), Path.join(lib_dir, file))
      end)

      src_include = Path.join([source_dir, "include", "ghostty"])

      if File.dir?(src_include) do
        dest_include = Path.join(include_dir, "ghostty")
        File.mkdir_p!(dest_include)
        copy_recursive(src_include, dest_include)
      end

      # Also check zig-out/include
      zig_include = Path.join([zig_out, "include", "ghostty"])

      if File.dir?(zig_include) do
        dest_include = Path.join(include_dir, "ghostty")
        File.mkdir_p!(dest_include)
        copy_recursive(zig_include, dest_include)
      end

      Mix.shell().info("libghostty-vt built successfully")
    end
  end

  defp copy_recursive(src, dest) do
    File.ls!(src)
    |> Enum.each(fn entry ->
      src_path = Path.join(src, entry)
      dest_path = Path.join(dest, entry)

      if File.dir?(src_path) do
        File.mkdir_p!(dest_path)
        copy_recursive(src_path, dest_path)
      else
        File.cp!(src_path, dest_path)
      end
    end)
  end

  defp check_cmd!({_output, 0}, _label), do: :ok

  defp check_cmd!({output, _status}, label) do
    Mix.raise("#{label} failed:\n#{output}")
  end

  def lib_output_dir, do: Path.join(priv_dir(), "lib")
  def include_output_dir, do: Path.join(priv_dir(), "include")

  defp priv_dir, do: Path.join(Mix.Project.app_path(), "priv")

  defp lib_filename do
    case :os.type() do
      {:unix, :darwin} -> "libghostty-vt.dylib"
      {:unix, _} -> "libghostty-vt.so"
      {:win32, _} -> "ghostty-vt.dll"
    end
  end
end
