defmodule Ghostty.LiveTerminal.Installer do
  @moduledoc false

  @import_line ~s(import {GhosttyTerminal} from "../vendor/ghostty")
  @vendor_path "assets/vendor/ghostty.js"
  @app_js_path "assets/js/app.js"

  def vendor_path, do: @vendor_path
  def app_js_path, do: @app_js_path

  def hook_asset_contents do
    :ghostty
    |> :code.priv_dir()
    |> to_string()
    |> then(&Path.join([&1, "static", "ghostty.js"]))
    |> File.read!()
  end

  def patch_app_js(content) do
    content
    |> ensure_import()
    |> ensure_hook_registration()
  end

  def hook_installed?(content) do
    String.contains?(content, @import_line) and
      Enum.any?(
        [
          String.contains?(content, "Hooks.GhosttyTerminal = GhosttyTerminal"),
          String.contains?(content, "hooks: {GhosttyTerminal}"),
          String.contains?(content, "hooks: {GhosttyTerminal},"),
          String.contains?(content, "hooks: {...colocatedHooks, GhosttyTerminal}"),
          String.contains?(content, "hooks: {...colocatedHooks, GhosttyTerminal},"),
          Regex.match?(~r/(?:let|const)\s+Hooks\s*=\s*\{[^}]*GhosttyTerminal/s, content)
        ],
        & &1
      )
  end

  defp ensure_import(content) do
    if String.contains?(content, @import_line) do
      content
    else
      case Regex.run(~r/(import\s+\{\s*LiveSocket\s*\}\s+from\s+["']phoenix_live_view["']\s*\n)/, content) do
        [match] -> String.replace(content, match, match <> @import_line <> "\n", global: false)
        _ -> @import_line <> "\n" <> content
      end
    end
  end

  defp ensure_hook_registration(content) do
    if hook_installed?(content) do
      content
    else
      content =
        content
        |> replace_first([
          {"hooks: {...colocatedHooks},", "hooks: {...colocatedHooks, GhosttyTerminal},"},
          {"hooks: {...colocatedHooks}", "hooks: {...colocatedHooks, GhosttyTerminal}"},
          {"hooks: {},", "hooks: {GhosttyTerminal},"},
          {"hooks: {}", "hooks: {GhosttyTerminal}"}
        ])
        |> ensure_hooks_object_if_needed()

      if String.contains?(content, "hooks:") do
        content
      else
        replace_first(content, [
          {"params: {_csrf_token: csrfToken},", "params: {_csrf_token: csrfToken},\n  hooks: {GhosttyTerminal},"},
          {"params: {_csrf_token: csrfToken}", "params: {_csrf_token: csrfToken},\n  hooks: {GhosttyTerminal}"}
        ])
      end
    end
  end

  defp ensure_hooks_object_if_needed(content) do
    if String.contains?(content, "hooks: Hooks") do
      ensure_hooks_object(content)
    else
      content
    end
  end

  defp ensure_hooks_object(content) do
    cond do
      String.contains?(content, "Hooks.GhosttyTerminal = GhosttyTerminal") ->
        content

      Regex.match?(~r/(?:let|const)\s+Hooks\s*=\s*\{\s*\}/, content) ->
        Regex.replace(
          ~r/((?:let|const)\s+Hooks\s*=\s*\{\s*\})/,
          content,
          "\\1\nHooks.GhosttyTerminal = GhosttyTerminal",
          global: false
        )

      Regex.match?(~r/(?:let|const)\s+Hooks\s*=\s*\{/, content) ->
        Regex.replace(
          ~r/((?:let|const)\s+Hooks\s*=\s*\{)/,
          content,
          "\\1\n  GhosttyTerminal,",
          global: false
        )

      true ->
        Regex.replace(
          ~r/(let\s+csrfToken\s*=)/,
          content,
          "let Hooks = {GhosttyTerminal}\n\n\\1",
          global: false
        )
    end
  end

  defp replace_first(content, replacements) do
    Enum.reduce_while(replacements, content, fn {old, new}, content ->
      updated = String.replace(content, old, new, global: false)

      if updated == content do
        {:cont, content}
      else
        {:halt, updated}
      end
    end)
  end
end

Code.ensure_compiled(Igniter)

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Ghostty.Install do
    use Igniter.Mix.Task

    alias Ghostty.LiveTerminal.Installer

    @example "mix igniter.install ghostty"
    @shortdoc "Installs Ghostty LiveView assets. Invoke with `mix igniter.install ghostty`"

    @moduledoc """
    #{@shortdoc}

    Vendors `ghostty.js` into `assets/vendor/ghostty.js` and wires
    `GhosttyTerminal` into `assets/js/app.js`.

    ## Example

    ```bash
    #{@example}
    ```
    """

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{example: @example, group: :ghostty}
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      if Igniter.exists?(igniter, Installer.app_js_path()) do
        install_live_view_assets(igniter)
      else
        Igniter.add_warning(
          igniter,
          "Could not find assets/js/app.js. Run `mix igniter.install ghostty` inside a Phoenix project to install the LiveView hook."
        )
      end
    end

    defp install_live_view_assets(igniter) do
      ghostty_js = Installer.hook_asset_contents()

      igniter
      |> Igniter.mkdir("assets/vendor")
      |> Igniter.create_or_update_file(Installer.vendor_path(), ghostty_js, fn source ->
        Rewrite.Source.update(source, :content, fn _ -> ghostty_js end)
      end)
      |> Igniter.update_file(Installer.app_js_path(), fn source ->
        Rewrite.Source.update(source, :content, &Installer.patch_app_js/1)
      end)
      |> maybe_warn_about_app_js()
    end

    defp maybe_warn_about_app_js(igniter) do
      app_js = Installer.app_js_path()
      source = Rewrite.source!(igniter.rewrite, app_js)
      content = Rewrite.Source.get(source, :content)

      if Installer.hook_installed?(content) do
        igniter
      else
        Igniter.add_warning(
          igniter,
          "Updated #{app_js}, but could not confidently wire `GhosttyTerminal` into your LiveSocket. Please review assets/js/app.js manually."
        )
      end
    end
  end
else
  defmodule Mix.Tasks.Ghostty.Install do
    @moduledoc "Installs Ghostty LiveView assets. Invoke with `mix igniter.install ghostty`"
    @shortdoc @moduledoc

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'ghostty.install' requires igniter.

      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
