defmodule PlugDrawer do
  use Behaviour
  import Supervisor.Spec

  @behaviour :sock_drawer

  @type ssloption :: {:accept_timeout, timeout()} | :ssl.ssloption()

  @type acceptors() :: non_neg_integer()

  @type max_sockets() :: non_neg_integer() | :infinity

  @type http() :: {:http, {:inet.ip_address(), :inet.port_number()},
    [:gen_tcp.listen_option()], [:gen_tcp.option()], acceptors(),
    max_sockets()}

  @type https() :: {:https, {:inet.ip_address(), :inet.port_number()},
    [:gen_tcp.listen_option()], [:gen_tcp.option()], [ssloption()],
    acceptors(), max_sockets()}

  defcallback init(term) ::
    {:ok, {http() | https(), module(), Keyword.t(), :cowboy_protocol.opts()}} |
    :ignore

  @spec start_link(module(), term(), GenServer.options()) ::
    {:ok, pid()} | {:error, term()}
  def start_link(mod, args, opts) do
    start_opts = [debug: Keyword.get(opts, :debug, [])]
    case Keyword.get(opts, :name) do
      nil ->
        :sock_drawer.start_link(__MODULE__, {mod, args}, start_opts)
      name when is_atom(name) ->
        name = {:local, name}
       :sock_drawer.start_link(name, __MODULE__, {mod, args}, start_opts)
      name ->
       :sock_drawer.start_link(name, __MODULE__, {mod, args}, start_opts)
    end
  end

  def init({mod, args}) do
    case apply(mod, :init, [args]) do
      {:ok,
        {{:http, target, lopts, copts, creators, manager_info},
          plug, opts, cbopts}} ->
        childspecs = [manager(manager_info), targeter(lopts), creator(copts),
          handler(plug, opts, cbopts, :no_ssl)]
        {:ok, {{{:sd_tcp, :accept, target}, creators, 1, 5}, childspecs}}
      {:ok, {{:https, target, lopts, copts, sslopts, creators, manager_info},
          plug, opts, cbopts, creators}} ->
        childspecs = [manager(manager_info), targeter(lopts), creator(copts),
          handler(plug, opts, cbopts, sslopts)]
        {:ok, {{{:sd_tcp, :accept, target}, creators, 1, 5}, childspecs}}
      :ignore ->
        :ignore
    end
  end

  defp manager({mod, args}) do
    worker(PlugDrawer.Manager, [mod, args],
      [id: :manager, modules: [mod, :sd_simple]])
  end

  defp manager(max_sockets) do
    manager({PlugDrawer.Manager, max_sockets})
  end

  defp targeter(lopts) do
    lopts = ranch_defaults() ++ lopts ++ ranch_enforces()
    worker(:sd_targeter, [lopts, 5000], [id: :targeter])
  end

  defp ranch_defaults() do
    [backlog: 1024, send_timeout: 30000, send_timeout_close: true]
  end

  defp ranch_enforces() do
    [mode: :binary, active: false, packet: :raw, reuseaddr: true, nodelay: true]
  end

  defp creator(copts) do
    # Must not be active!
    false = Keyword.has_key?(copts, :active)
    worker(:sd_creator, [copts, 5000, {0,0}, {0, 100}],
      [id: :creator, restart: :transient])
  end

  def handler(plug, opts, cbopts, sslopts) do
    opts = apply(plug, :init, [opts])
    worker(PlugDrawer.Handler, [plug, opts, cbopts, sslopts],
      [id: :handler, restart: :temporary,
        modules: [plug, PlugDrawer.Handler, :cowboy_protocol]])
  end
end
