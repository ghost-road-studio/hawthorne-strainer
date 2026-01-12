defmodule Casbin.Engine.RoleManager.Server do
  @moduledoc """
  The Process Owner and consistency guardian for the Role Manager.

  ## Architectural Significance: The Write Coordinator

  While the `Casbin.Engine.RoleManager` module handles reads in the client process, this
  `GenServer` acts as the **Single Source of Truth** for a specific Casbin instance.

  Its responsibilities are:
  1.  **Ownership:** It owns the ETS table. If this process dies, the table is automatically
      cleaned up by the VM.
  2.  **Serialization:** It processes write operations (`add_link`, `delete_link`) sequentially.
  3.  **Lifecycle Management:** It cleans up `:persistent_term` entries on termination.

  ## Storage Internals

  *   **Dynamic Registry:** Uses `Casbin.Registry` to allow multiple instances.
  *   **Table ID (TID):** We use the reference returned by `:ets.new/2`. This TID is
      passed to `Casbin.Core` and stored in configuration for readers.
  *   **Bag Storage:** Uses `:bag` to support Many-to-Many RBAC relationships.
  """
  use GenServer

  @type start_opts :: [name: {:via, module(), any()}]

  @spec start_link(start_opts()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # -- GenServer Callbacks --

  @impl true
  def init(_opts) do
    # We use a reference (TID) instead of a name to support infinite dynamic tenants.
    tid = :ets.new(:casbin_rm, [:bag, :public, {:read_concurrency, true}])

    # We use the TID as the key because it is unique to this process instance.
    :persistent_term.put({:casbin_rm_matchers, tid}, %{rn: nil, dom: nil})

    {:ok, %{tid: tid}}
  end

  @impl true
  def handle_call(:get_metadata, _from, %{tid: _tid} = state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:add_matching_func, func}, _from, %{tid: tid} = state) do
    update_matchers(tid, :rn, func)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:add_domain_matching_func, func}, _from, %{tid: tid} = state) do
    update_matchers(tid, :dom, func)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:add_link, name1, name2, domain}, _from, %{tid: tid} = state) do
    # Deduplication check
    unless has_direct_link?(tid, name1, name2, domain) do
      :ets.insert(tid, {{:g, name1, domain}, name2})
      :ets.insert(tid, {{:rev_g, name2, domain}, name1})
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete_link, name1, name2, domain}, _from, %{tid: tid} = state) do
    :ets.delete_object(tid, {{:g, name1, domain}, name2})
    :ets.delete_object(tid, {{:rev_g, name2, domain}, name1})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:clear, _from, %{tid: tid} = state) do
    :ets.delete_all_objects(tid)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, %{tid: tid} = _state) do
    # CRITICAL: Clean up persistent_term to prevent memory leaks when tenants shut down.
    # ETS tables are cleaned up automatically by the VM when the process dies,
    # but persistent_term is global and permanent unless explicitly erased.
    :persistent_term.erase({:casbin_rm_matchers, tid})
    :ok
  end

  # -- Internal Helpers --

  defp update_matchers(tid, key, func) do
    current = :persistent_term.get({:casbin_rm_matchers, tid})
    :persistent_term.put({:casbin_rm_matchers, tid}, Map.put(current, key, func))
  end

  defp has_direct_link?(tid, n1, n2, dom) do
    :ets.match_object(tid, {{:g, n1, dom}, n2}) != []
  end
end
