defmodule StdJsonIo.Worker do
  use GenServer
  alias Porcelain.Process, as: Proc
  alias Porcelain.Result

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts[:script], opts)
  end

  def init(script) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, %{io_proc: start_io_server(script)}}
  end

  def handle_call({:json, blob}, _from, state) do
    case Jason.encode(blob) do
      nil ->
        {:error, :json_error}

      {:error, reason} ->
        {:error, reason}

      {:ok, json} ->
        Proc.send_input(state.io_proc, json)
        do_receive(state)
    end
  end

  def handle_call(:stop, _from, state), do: {:stop, :normal, :ok, state}

  defp do_receive(already_read \\ [], state) do
    receive do
      {_js_pid, :data, :out, msg} ->
        case String.ends_with?(msg, "\n") do
          true ->
            {:reply, {:ok, [msg | already_read] |> Enum.reverse()}, state}

          _ ->
            do_receive([msg | already_read], state)
        end

      {:EXIT, _pid, :shutdown} = response ->
        terminate(:EXIT, state)
        {:reply, {:error, response}, state}

      response ->
        {:reply, {:error, response}, state}
    end
  end

  # The io server has stopped
  def handle_info({_js_pid, :result, %Result{err: _, status: _status}} = _msg, state) do
    {:stop, :normal, state}
  end

  def terminate(_reason, %{io_proc: server} = _state) do
    Proc.signal(server, :kill)
    Proc.stop(server)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp start_io_server(script) do
    script_path = path(script)
    dir = Path.dirname(script_path)
    Porcelain.spawn_shell(script_path, in: :receive, out: {:send, self()}, dir: dir)
  end

  defp path({app, script}) do
    Application.app_dir(app) |> Path.join(script) |> Path.expand()
  end

  defp path(script), do: script
end
