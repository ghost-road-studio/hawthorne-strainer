defmodule Casbin.Supervisor do
  @moduledoc """
  The main Supervisor for a Casbin instance.

  It manages the lifecycle of:
  1.  **Registry:** Local process registry for this instance (or shared).
  2.  **RoleManager:** Graph database for RBAC (GenServer + ETS).
  3.  **PolicyStore:** Storage for policy rules (GenServer + ETS).
  4.  **Watcher:** (Optional) Syncs policies across nodes.
  5.  **Core:** Coordinator that loads policies and manages `persistent_term`.

  ## Architecture
  This supervisor uses a **Dynamic Naming Strategy**.
  If you start it with `name: :my_app`, it registers children in `Casbin.Registry` using keys
  like `{:role_manager, :my_app}`. This allows you to run multiple isolated Casbin instances
  (e.g., per-tenant) in the same VM without name collisions.
  """
  use Supervisor
  alias Casbin.Engine.RoleManager.Server, as: RoleManager


  def start_link(instance_name) do
    Supervisor.start_link(__MODULE__, instance_name, name: Module.concat(__MODULE__, instance_name), strategy: :one_for_one)
  end

  def init(instance_name) do
    # [
    #   {Registry, keys: :unique, name: Casbin.Registry},
    #   RoleManager
    # ]
    # |> Supervisor.init(strategy: :one_for_one)

    children = [
      {Registry, keys: :unique, name: Casbin.Registry},
      {RoleManager, name: via(instance_name, :role_manager)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # def start_link(opts) do
  #   # Name is mandatory to ensure we can registry components
  #   name = Keyword.fetch!(opts, :name)
  #   Supervisor.start_link(__MODULE__, opts, name: name)
  # end

  # @impl true
  # def init(opts) do
  #   name = Keyword.fetch!(opts, :name)

  #   # 1. Derive names for internal components
  #   # We use Module.concat to create safe, unique atoms based on the main name
  #   # e.g. :my_casbin -> Casbin.Engine.RoleManager.my_casbin
  #   # Actually, simpler atoms are easier to debug: :my_casbin_rm
  #   rm_name = String.to_atom("#{name}_rm")
  #   ps_name = String.to_atom("#{name}_ps")

  #   # 2. Build Child Specs

  #   # RoleManager (ETS Graph)
  #   role_manager_spec = {Casbin.Engine.RoleManager, name: rm_name}

  #   # PolicyStore (ETS Rules)
  #   policy_store_spec = {Casbin.Engine.PolicyStore, name: ps_name}

  #   # Watcher (Optional)
  #   # The user passes {Module, [opts]}, we need to inject the name
  #   watcher_conf = Keyword.get(opts, :watcher)
  #   watcher_spec = build_watcher_spec(watcher_conf, name)
  #   watcher_pid_ref = if watcher_conf, do: String.to_atom("#{name}_watcher"), else: nil

  #   # Core (Coordinator)
  #   # Core needs to know the names of the components we just defined
  #   core_opts =
  #     opts
  #     |> Keyword.put(:role_manager_name, rm_name)
  #     |> Keyword.put(:policy_store_name, ps_name)
  #     |> Keyword.put(:watcher_pid_ref, watcher_pid_ref)

  #   core_spec = {Casbin.Core, core_opts}

  #   # 3. Define Strategy
  #   # Order matters: Storage first, then Watcher, then Core (which loads data)
  #   children =
  #     [
  #       role_manager_spec,
  #       policy_store_spec,
  #       watcher_spec,
  #       core_spec
  #     ]
  #     |> Enum.reject(&is_nil/1)

  #   Supervisor.init(children, strategy: :one_for_one)
  # end

  # defp build_watcher_spec(nil, _), do: nil
  # defp build_watcher_spec({module, opts}, parent_name) do
  #   # We construct the name for the watcher so Core can find it
  #   watcher_name = String.to_atom("#{parent_name}_watcher")
  #   updated_opts = Keyword.put(opts, :name, watcher_name)

  #   %{
  #     id: module,
  #     start: {module, :start_link, [updated_opts]},
  #     type: :worker
  #   }
  # end

  defp via(instance, component) do
    {:via, Registry, {Casbin.Registry, {component, instance}}}
  end
end
