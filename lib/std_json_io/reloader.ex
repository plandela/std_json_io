defmodule StdJsonIo.Reloader do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init([mod, files]) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: files)
    FileSystem.subscribe(watcher_pid)

    {:ok, %{files: files, mod: mod, watcher_pid: watcher_pid}}
  end

  def handle_info({:file_event, _watcher_pid, {path, _events}}, %{files: files, mod: mod} = state) do
    if Enum.member?(files, path |> to_string) do
      mod.restart_io_workers!()
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
