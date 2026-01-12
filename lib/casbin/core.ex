defmodule Casbin.Core do
  @moduledoc """
  The Central Coordinator.
  1. Parses Model & Compiles Matchers/Effectors.
  2. Stores compiled logic in `:persistent_term`.
  3. Owns the PolicyStore and RoleManager GenServers.
  4. Manages the Watcher.
  """
  use GenServer
  require Logger

  alias Casbin.Model
  alias Casbin.Engine.{MatcherCompiler, Effector, RoleManager, PolicyStore}
  alias Casbin.Engine.RoleManager.Server

  # -- API --

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # -- Callbacks --

  @impl true
  def init(opts) do
    model_path = Keyword.fetch!(opts, :model_path)
    # The Adapter should be an implementation module, e.g., Casbin.Adapters.Ecto
    adapter = Keyword.get(opts, :adapter)
    # Optional Watcher config
    watcher_conf = Keyword.get(opts, :watcher)

    # 1. Start Internal Components (RoleManager & PolicyStore)
    # We use the Core name to namespace the sub-components
    rm_name = Module.concat(opts[:name], RoleManager)
    ps_name = Module.concat(opts[:name], PolicyStore)

    # Note: In a real supervision tree, you might want these supervised separately.
    # For simplicity, we link them here or assume they are started.
    # Better: Start them here dynamically.
    {:ok, _} = Server.start_link(name: rm_name)
    {:ok, _} = PolicyStore.start_link(name: ps_name)

    # 2. Parse Model
    model = Model.new(model_path)

    # 3. Compile Matcher
    # We map "g" to our specific RoleManager name
    rm_map = %{"g" => rm_name}
    {:ok, matcher_func} = MatcherCompiler.compile(model, rm_map)

    # 4. Get Effector
    effect_expr = model.effect["e"]
    effector_func = Effector.get_effector(effect_expr)

    # 5. Store Configuration in Persistent Term
    # This enables the "Read-Local" architecture for the Enforcer
    config = %{
      matcher: matcher_func,
      effector: effector_func,
      policy_store: ps_name,
      role_manager: rm_name,
      model: model
    }
    :persistent_term.put(opts[:name], config)

    # 6. Load Policies (Cold Start)
    if adapter do
      load_policies(adapter, ps_name, rm_name)
    end

    # 7. Start Watcher (if any)
    # (Watcher setup logic from previous step goes here)

    {:ok, %{name: opts[:name], adapter: adapter, rm: rm_name, ps: ps_name}}
  end

  defp load_policies(adapter, ps, rm) do
    # Call adapter.load_policy()
    # Iterate results.
    # If ptype == "p", add to PolicyStore.
    # If ptype == "g", add to RoleManager.
    # (Implementation details depend on Adapter return format)
    :ok
  end
end
