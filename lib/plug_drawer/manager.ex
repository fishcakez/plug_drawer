defmodule PlugDrawer.Manager do
  @behaviour :sd_simple

  def start_link(mod, args, id) do
    :sd_simple.start_link(id, mod, args, [])
  end

  def init(max_sockets) do
    {:ok, max_sockets}
  end

end
