defmodule PlugDrawerTest do
  use ExUnit.Case

  test "hello world" do
    fun = fn(conn) ->
      conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "Hello world")
    end
    {:ok, pid} = PlugDrawerTest.Pool.start_link(fun)
    {:ok, {ip, port}} = sockname(pid)
    url = String.to_char_list("http://#{:inet.ntoa(ip)}:#{port}/")
    {:ok, {status, _, body}} =  :httpc.request(url)
    assert status === {'HTTP/1.1', 200, 'OK'}
    assert body === 'Hello world'
  end

  test "error" do
    fun = fn(_) -> raise "hello" end
    {:ok, pid} = PlugDrawerTest.Pool.start_link(fun)
    {:ok, {ip, port}} = sockname(pid)
    url = String.to_char_list("http://#{:inet.ntoa(ip)}:#{port}/")
    {:ok, {status, _, _}} = :httpc.request(url)
    assert status === {'HTTP/1.1', 500, 'Internal Server Error'}
  end

  defp sockname(pid) do
    id = :sock_drawer.id(pid)
    {:ok, lsocket} = :sd_agent.find(id, :socket)
    :inet.sockname(lsocket)
  end

end
