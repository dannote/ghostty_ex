Application.put_env(:phoenix_test, :base_url, LiveTerminalWeb.Endpoint.url())
{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
ExUnit.start()
