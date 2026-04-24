defmodule Ghostty.TTY.Backend do
  @moduledoc false

  alias Ghostty.Terminal.Nif

  @reader_start_timeout_ms 1_000

  @type name :: :auto | :otp_raw | :nif
  @type state ::
          %{type: :none}
          | %{type: :otp_raw, reader: pid()}
          | %{type: :nif, terminal: term(), otp_reader: term()}

  @spec start([Ghostty.TTY.option()], pid()) :: state()
  def start(opts, owner) do
    if Keyword.get(opts, :raw, true) do
      opts
      |> resolve()
      |> start_raw(opts, owner)
    else
      %{type: :none}
    end
  end

  @spec write(state(), binary()) :: :ok
  def write(%{type: :nif, terminal: terminal}, data) do
    Nif.nif_tty_write(terminal, data)
    :ok
  end

  def write(_backend, data) do
    IO.write(data)
    :ok
  end

  @spec close(state() | nil) :: :ok
  def close(%{type: :nif, terminal: terminal, otp_reader: otp_reader}) do
    Nif.nif_tty_close(terminal)
    restore_otp_reader(otp_reader)
  end

  def close(%{type: :otp_raw, reader: reader}) when is_pid(reader) do
    Process.exit(reader, :shutdown)
    :ok
  end

  def close(_backend), do: :ok

  defp resolve(opts) do
    case Keyword.get(opts, :backend, :auto) do
      :auto -> if otp_raw_available?(), do: :otp_raw, else: :nif
      backend when backend in [:otp_raw, :nif] -> backend
      backend -> raise ArgumentError, "invalid TTY backend: #{inspect(backend)}"
    end
  end

  defp start_raw(:otp_raw, _opts, owner) do
    unless otp_raw_available?() do
      raise "OTP raw terminal backend requires OTP 28 or later"
    end

    start_interactive = Function.capture(:shell, :start_interactive, 1)

    case start_interactive.({:noshell, :raw}) do
      :ok -> :ok
      {:error, reason} -> raise "could not start OTP raw terminal backend: #{inspect(reason)}"
      other -> raise "could not start OTP raw terminal backend: #{inspect(other)}"
    end

    reader = spawn_link(fn -> otp_raw_read_loop(owner) end)
    %{type: :otp_raw, reader: reader}
  end

  defp start_raw(:nif, opts, owner) do
    takeover? = Keyword.get(opts, :takeover, Keyword.get(opts, :disable_otp_reader, false))
    otp_reader = handle_otp_reader_for_nif(takeover?)
    signals = Keyword.get(opts, :signals, false)
    terminal = Nif.nif_tty_open(owner, signals)
    wait_until_reader_ready()
    %{type: :nif, terminal: terminal, otp_reader: otp_reader}
  end

  defp otp_raw_available? do
    case Integer.parse(System.otp_release()) do
      {release, _suffix} -> release >= 28
      :error -> false
    end
  end

  defp otp_raw_read_loop(owner) do
    case IO.getn("", 1024) do
      :eof ->
        send(owner, {:tty_eof})

      data when is_binary(data) or is_list(data) ->
        send(owner, {:tty_data, IO.iodata_to_binary(data)})
        otp_raw_read_loop(owner)
    end
  end

  defp handle_otp_reader_for_nif(false) do
    case Process.whereis(:user_drv_reader) do
      pid when is_pid(pid) ->
        raise "OTP terminal reader is active; use backend: :otp_raw on OTP 28+ or pass takeover: true"

      _ ->
        nil
    end
  end

  defp handle_otp_reader_for_nif(true) do
    case Process.whereis(:user_drv_reader) do
      pid when is_pid(pid) -> stop_otp_reader(pid)
      _ -> nil
    end
  end

  defp stop_otp_reader(pid) do
    case user_drv_tty_state() do
      {:ok, tty} ->
        _tty_without_reader = :prim_tty.reader_stop(tty)
        {:stopped, pid}

      {:error, reason} ->
        raise "could not stop OTP terminal reader: #{inspect(reason)}"
    end
  end

  defp user_drv_tty_state do
    case :sys.get_state(:user_drv) do
      {_callback, {:state, tty, _write, _read, _shell_started, _editor, _user, _group, _groups, _queue}} ->
        {:ok, tty}

      other ->
        {:error, {:unexpected_user_drv_state, other}}
    end
  catch
    :exit, reason -> {:error, reason}
  end

  defp restore_otp_reader(_otp_reader), do: :ok

  defp wait_until_reader_ready do
    receive do
      {:tty_ready} -> :ok
    after
      @reader_start_timeout_ms -> raise "TTY reader did not start"
    end
  end
end
