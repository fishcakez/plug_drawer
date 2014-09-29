Application.ensure_all_started(:inets)
ExUnit.start()

defmodule PlugDrawerTest.Pool do

  @behaviour :sock_drawer

  def start_link(opts) do
    PlugDrawer.start_link(__MODULE__, opts, [])
  end

  def init(opts) do
    http = {:http, {{127,0,0,1}, 0}, [], [], 1, 2}
    {:ok, {http, PlugDrawerTest.Plug, opts, []}}
  end

end

defmodule PlugDrawerTest.Plug do

  def init(fun) when is_function(fun, 1), do: fun

  def call(conn, fun), do: fun.(conn)
end
