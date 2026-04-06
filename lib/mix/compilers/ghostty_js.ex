defmodule Mix.Compilers.GhosttyJS do
  @moduledoc false

  @ts_dir "priv/ts"
  @output "priv/static/ghostty.js"

  def run(_argv) do
    if Code.ensure_loaded?(OXC) do
      compile()
    else
      :noop
    end
  end

  defp compile do
    ts_dir = Path.join(Mix.Project.project_file() |> Path.dirname(), @ts_dir)
    output = Path.join(Mix.Project.project_file() |> Path.dirname(), @output)

    ts_files = Path.wildcard(Path.join(ts_dir, "*.ts"))

    if ts_files == [] do
      :noop
    else
      newest_ts = ts_files |> Enum.map(&File.stat!(&1).mtime) |> Enum.max()

      needs_rebuild? =
        not File.exists?(output) or
          File.stat!(output).mtime < newest_ts

      if needs_rebuild? do
        do_bundle(ts_dir, output)
      else
        :noop
      end
    end
  end

  defp do_bundle(ts_dir, output) do
    files =
      ts_dir
      |> Path.join("*.ts")
      |> Path.wildcard()
      |> Enum.map(fn path ->
        {Path.basename(path), File.read!(path)}
      end)

    case OXC.bundle(files, entry: "hook.ts") do
      {:ok, js} ->
        File.mkdir_p!(Path.dirname(output))
        esm = iife_to_esm(js, "GhosttyTerminal")
        File.write!(output, esm)
        Mix.shell().info("Compiled #{length(files)} TypeScript modules → #{@output}")
        :ok

      {:error, errors} ->
        Mix.raise("TypeScript bundle failed: #{inspect(errors)}")
    end
  end

  defp iife_to_esm(js, export_name) do
    # OXC outputs: (function(exports) { ... exports.Foo = Foo; return exports; })({});
    # We convert to: const _m = (function(exports) { ... })({});\nexport const Foo = _m.Foo;
    "const _m = #{js}\nconst #{export_name} = _m.#{export_name}\nexport { #{export_name} }\n"
  end
end
