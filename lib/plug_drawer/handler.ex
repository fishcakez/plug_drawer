defmodule PlugDrawer.Handler do
  require Record

  @behaviour :cowboy_middleware

  Record.defrecord(:state,
    [socket: :undefined, transport: :undefined, middlewares: [__MODULE__],
      compress: false, env: :undefined, onrequest: :undefined,
      onresponse: :undefined, max_empty_lines: 5, req_keepalive: 1,
      max_keepalive: 100, max_request_line_length: 4096,
      max_header_name_length: 100, max_header_value_length: 4096,
      max_headers: 100, timeout: 5000, until: :undefined])

  def start_link(plug, opts, cbopts, sslopts, {:sd_tcp, _, _}, id, pref) do
    pid = spawn_link(__MODULE__, :init, [id, pref, plug, opts, cbopts, sslopts])
    {:ok, pid}
  end

  def init(id, pref, plug, opts, cbopts, sslopts) do
    compress = Keyword.get(cbopts, :compress, false)
    on_request = Keyword.get(cbopts, :onrequest, :undefined)
    on_resp = Keyword.get(cbopts, :onresponse, :undefined)
    empty_lines = Keyword.get(cbopts, :max_empty_lines, 5)
    keepalive = Keyword.get(cbopts, :max_keepalive, 100)
    request_line = Keyword.get(cbopts, :max_request_line_length, 4096)
    header_name = Keyword.get(cbopts, :max_header_name_length, 64)
    header_value = Keyword.get(cbopts, :max_header_value_length, 4096)
    header_count = Keyword.get(cbopts, :max_headers, 100)
    timeout = Keyword.get(cbopts, :timeout, 5000)
    until = parse_until(timeout)
    {transport, socket} = await_socket(pref, sslopts)
    env = [plug: {plug, opts}, transport: transport, socket: socket,
      sock_drawer: id]
    case apply(transport, :recv, [socket, 0, timeout]) do
      {:ok, buffer} ->
        cb_state = state([socket: socket, transport: transport, env: env,
          compress: compress, env: [sock_drawer: id], onrequest: on_request,
          onresponse: on_resp, max_empty_lines: empty_lines,
          max_keepalive: keepalive, max_request_line_length: request_line,
          max_header_name_length: header_name,
          max_header_value_length: header_value, max_headers: header_count,
          timeout: timeout, until: until])
        :cowboy_protocol.parse_request(buffer, cb_state, 0)
      {:error, _reason} ->
        :ok = apply(transport, :close, [socket])
        exit(:normal)
    end
  end

  defp parse_until(:infinty) do
    :infinity
  end

  defp parse_until(timeout) do
    {mega, sec, micro} = :os.timestamp()
    sec = (mega * 1_000_000 + sec)
    now = sec * 1_000 + div(micro, 1_000)
    now + timeout
  end

  defp await_socket(pref, :no_ssl) do
    receive do
      {:socket, ^pref, socket} ->
        {:ranch_tcp, socket}
    end
  end

  defp await_socket(pref, sslopts) do
    {timeout, sslopts} = Keyword.pop(sslopts, :accept_timeout, 30000)
    receive do
      {:socket, ^pref, socket} ->
        ssl_accept(socket, sslopts, timeout)
    end
  end

  defp ssl_accept(socket, sslopts, timeout) do
    case :ssl.ssl_accept(socket, sslopts, timeout) do
      {:ok, ssl_socket} ->
        {:ranch_ssl, ssl_socket}
      {:error, reason} ->
        exit({:ssl_accept, reason})
    end
  end

  def execute(req, env) do
    conn = make_conn(req, env)
    {plug, opts} = Keyword.fetch!(env, :plug)
    try do
      apply(plug, :call, [conn, opts])
    else
      %Plug.Conn{adapter: {Plug.Adapters.Cowboy.Conn, req}} ->
        {:ok, req, [{:result, :ok} | env]}
    catch
      class, reason ->
        stack = System.stacktrace()
        close_socket(stack, req, env)
        report_error(class, reason, stack, conn, env)
        terminate(class, reason, stack)
    end
  end

  defp make_conn(req, env) do
    case Keyword.fetch!(env, :transport) do
      :ranch_tcp ->
        Plug.Adapters.Cowboy.Conn.conn(req, :tcp)
      :ranch_ssl ->
        Plug.Adapters.Cowboy.Conn.conn(req, :ssl)
    end
  end

  defp close_socket(stack, req, env) do
    try do
      :ok = :cowboy_req.maybe_reply(stack, req)
    catch
      _, _ ->
        :ok
    after
      transport = Keyword.fetch!(env, :transport)
      socket = Keyword.fetch!(env, :socket)
      apply(transport, :close, [socket])
    end
  end

  defp report_error(:exit, :normal, _stack, _conn, _env), do: :ok
  defp report_error(:exit, :shutdown, _stack, _conn, _env), do: :ok
  defp report_error(:exit, {:shutdown, _}, _stack, _conn, _env), do: :ok

  defp report_error(class, reason, stack, conn, env) do
    sock_drawer = Keyword.fetch!(env, :sock_drawer)
    {plug, opts} = Keyword.fetch!(env, :plug)
    report = [pid: self(), initial_call: {plug, :call, [conn, opts]},
      error_info: {class, reason, stack}, sock_drawer: sock_drawer]
    :error_logger.error_report({PlugDrawer, :crash_report}, report)
  end

  defp terminate(:exit, reason, _stack), do: exit(reason)
  defp terminate(:error, reason, stack), do: exit({reason, stack})
  defp terminate(:throw, reason, stack), do: exit({{:nocatch, reason}, stack})

end
