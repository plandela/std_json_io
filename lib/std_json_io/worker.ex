defmodule StdJsonIo.Worker do
  use GenServer
  alias Porcelain.Process, as: Proc
  alias Porcelain.Result

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts[:script], opts)
  end

  def init(script) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, %{js_proc: start_io_server(script)}}
  end

  def handle_call({:json, blob}, _from, state) do
    case Poison.encode(blob) do
      nil -> {:error, :json_error}
      {:error, reason} -> {:error, reason}
      {:ok, json} ->
        Proc.send_input(state.js_proc, json)
        do_receive(state)
    end
  end

  defp do_receive(already_read \\ "", state) do
    receive do
      {_js_pid, :data, :out, msg} ->
        case String.last(msg) do
          "\n" -> {:reply, {:ok, already_read <> msg}, state}
          _ ->
            do_receive(already_read <> msg, state)
        end
      response ->
        {:reply, {:error, response}, state}
    end
  end

  def handle_call(:stop, _from, state), do: {:stop, :normal, :ok, state}

  # The js server has stopped
  def handle_info({_js_pid, :result, %Result{err: _, status: _status}}, state) do
    {:stop, :normal, state}
  end

  def terminate(_reason, %{js_proc: server}) do
    Proc.signal(server, :kill)
    Proc.stop(server)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp start_io_server(script) do
    Porcelain.spawn_shell(script, in: :receive, out: {:send, self()})
  end
end
