defmodule Ghostty.LiveTerminalInstallerTest do
  use ExUnit.Case, async: true

  alias Ghostty.LiveTerminal.Installer

  test "patch_app_js/1 adds import and hook to colocated hooks setup" do
    content = """
    import \"phoenix_html\"
    import {Socket} from \"phoenix\"
    import {LiveSocket} from \"phoenix_live_view\"
    import topbar from \"../vendor/topbar\"
    import {hooks as colocatedHooks} from \"phoenix-colocated/my_app\"

    let csrfToken = document.querySelector(\"meta[name='csrf-token']\").getAttribute(\"content\")
    let liveSocket = new LiveSocket(\"/live\", Socket, {
      longPollFallbackMs: 2500,
      params: {_csrf_token: csrfToken},
      hooks: {...colocatedHooks},
    })
    """

    patched = Installer.patch_app_js(content)

    assert patched =~ ~s(import {GhosttyTerminal} from "../vendor/ghostty")
    assert patched =~ ~s(hooks: {...colocatedHooks, GhosttyTerminal},)
  end

  test "patch_app_js/1 adds import and hook to Hooks object setup" do
    content = """
    import \"phoenix_html\"
    import {Socket} from \"phoenix\"
    import {LiveSocket} from \"phoenix_live_view\"
    import topbar from \"../vendor/topbar\"

    let Hooks = {}

    let csrfToken = document.querySelector(\"meta[name='csrf-token']\").getAttribute(\"content\")
    let liveSocket = new LiveSocket(\"/live\", Socket, {
      params: {_csrf_token: csrfToken},
      hooks: Hooks,
    })
    """

    patched = Installer.patch_app_js(content)

    assert patched =~ ~s(import {GhosttyTerminal} from "../vendor/ghostty")
    assert patched =~ ~s(Hooks.GhosttyTerminal = GhosttyTerminal)
    assert patched =~ ~s(hooks: Hooks,)
  end

  test "patch_app_js/1 adds hooks option when none exists" do
    content = """
    import \"phoenix_html\"
    import {Socket} from \"phoenix\"
    import {LiveSocket} from \"phoenix_live_view\"
    import topbar from \"../vendor/topbar\"

    let csrfToken = document.querySelector(\"meta[name='csrf-token']\").getAttribute(\"content\")
    let liveSocket = new LiveSocket(\"/live\", Socket, {
      longPollFallbackMs: 2500,
      params: {_csrf_token: csrfToken},
    })
    """

    patched = Installer.patch_app_js(content)

    assert patched =~ ~s(import {GhosttyTerminal} from "../vendor/ghostty")
    assert patched =~ ~s(params: {_csrf_token: csrfToken},)
    assert patched =~ ~s(hooks: {GhosttyTerminal},)
  end

  test "patch_app_js/1 is idempotent" do
    content = """
    import \"phoenix_html\"
    import {Socket} from \"phoenix\"
    import {LiveSocket} from \"phoenix_live_view\"
    import {GhosttyTerminal} from \"../vendor/ghostty\"

    let csrfToken = document.querySelector(\"meta[name='csrf-token']\").getAttribute(\"content\")
    let liveSocket = new LiveSocket(\"/live\", Socket, {
      params: {_csrf_token: csrfToken},
      hooks: {GhosttyTerminal},
    })
    """

    assert Installer.patch_app_js(content) == content
  end
end
