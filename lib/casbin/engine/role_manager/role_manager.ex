defmodule Casbin.Engine.RoleManager do
  @moduledoc """
  The Client API and Logic Engine for the Casbin Role Manager.

  ## Architectural Significance: The "Read-Local" Strategy

  In high-throughput authorization systems, the **Enforcement** phase is the critical path.
  A standard `GenServer` approach (where every check sends a message to a central process)
  creates a sequential bottleneck, capping throughput at roughly 20k-50k ops/sec per node
  and increasing latency under load.

  This module implements a **Read-Local** architecture:

  1.  **Client-Side Execution:** All functions in this module run entirely within the
      calling process (e.g., your Phoenix Controller or Cowboy Handler).
  2.  **Shared Memory Access:** It reads directly from **ETS (Erlang Term Storage)**
      tables owned by `Casbin.Engine.RoleManager.Server`.
  3.  **Zero Message Passing:** For standard checks, no messages are sent between processes,
      allowing for **concurrent, wait-free reads** that scale with the number of CPU cores.

  ## Performance Characteristics

  *   **Direct Lookups (`get_roles/2`):** O(1) amortized time via ETS hash lookups.
  *   **Graph Traversal (`has_link?/3`):** Uses a Breadth-First Search (BFS). Performance
      depends on graph depth, but remains extremely fast (microseconds) due to in-memory
      ETS access.
  *   **Matching Functions:** If wildcards/patterns are used (e.g., `keyMatch`), the system
      gracefully degrades from O(1) hash lookups to O(N) scans (where N is the number of
      roles for the subject). This is optimized via `persistent_term` to keep configuration
      access fast.

  ## Domain Isolation vs. Digraph

  Unlike Erlang's native `:digraph` module, this implementation natively supports **Casbin Domains**.
  Instead of maintaining thousands of separate graph tables for multi-tenant systems, we use
  a composite key strategy (`{type, subject, domain}`) within a single highly-optimized ETS table.
  This ensures:
  1.  **Memory Efficiency:** One table for millions of users/tenants.
  2.  **Strict Isolation:** Traversal never "leaks" across domains.
  """
  @behaviour Casbin.Behaviour.RoleManager

  require Logger
  alias Casbin.Engine.RoleManager.Server, as: RoleManager

  # -- Write API (Delegates to Server) --

  @impl true
  def add_link(server, name1, name2, domain \\ nil) do
    GenServer.call(server, {:add_link, name1, name2, domain})
  end

  @impl true
  def delete_link(server, name1, name2, domain \\ nil) do
    GenServer.call(server, {:delete_link, name1, name2, domain})
  end

  @impl true
  def clear(server) do
    GenServer.call(server, :clear)
  end

  @impl true
  def add_matching_func(server, func) do
    GenServer.call(server, {:add_matching_func, func})
  end

  @impl true
  def add_domain_matching_func(server, func) do
    GenServer.call(server, {:add_domain_matching_func, func})
  end

  def get_metadata(server) do
    GenServer.call(server, :get_metadata)
  end

  # -- Read API (Executes locally via ETS) --

  @impl true
  def has_link?(tid, name1, name2, domain \\ nil) do
    if name1 == name2 do
      true
    else
      matchers = get_matchers(tid)

      # OPTIMIZATION 1: Fast Path
      # If no custom role matcher is defined, check direct links first.
      # This bypasses MapSet creation and recursion for the most common case (Depth 1).
      if is_nil(matchers.rn) and has_direct_role?(tid, name1, name2, domain, matchers) do
        true
      else
        # Fallback to Graph Traversal (DFS)
        check_link_dfs(tid, [name1], name2, domain, MapSet.new([name1]), matchers)
      end
    end
  end

  @impl true
  def get_roles(tid, name, domain \\ nil) do
    matchers = get_matchers(tid)

    if matchers.dom do
      get_roles_with_domain_matching(tid, name, domain, matchers.dom)
    else
      lookup_roles_direct(tid, name, domain)
    end
  end

  @impl true
  def get_users(tid, name, domain \\ nil) do
    lookup_users_direct(tid, name, domain)
  end

  @impl true
  def print_roles(tid) do
    roles =
      :ets.tab2list(tid)
      |> Enum.filter(fn {{type, _, _}, _} -> type == :g end)
      |> Enum.map(fn {{:g, subj, dom}, role} ->
        dom_str = if dom, do: " [#{dom}]", else: ""
        "#{subj} < #{role}#{dom_str}"
      end)

    Logger.info("RoleManager (#{inspect(tid)}) State:\n" <> Enum.join(roles, "\n"))
    :ok
  end

  # -- Private Logic (Graph Traversal) --

  defp get_matchers(tid) do
    :persistent_term.get({:casbin_rm_matchers, tid}, %{rn: nil, dom: nil})
  end

  defp has_direct_role?(table, subject, target, domain, matchers) do
    roles =
      if matchers.dom do
        get_roles_with_domain_matching(table, subject, domain, matchers.dom)
      else
        lookup_roles_direct(table, subject, domain)
      end

    target in roles
  end

  defp lookup_roles_direct(table, subject, domain) do
    case :ets.lookup(table, {:g, subject, domain}) do
      [] -> []
      results -> Enum.map(results, fn {_, role} -> role end)
    end
  end

  defp lookup_users_direct(table, role, domain) do
    case :ets.lookup(table, {:rev_g, role, domain}) do
      [] -> []
      results -> Enum.map(results, fn {_, subject} -> subject end)
    end
  end

  defp get_roles_with_domain_matching(table, subject, domain, dom_matcher) do
    :ets.match(table, {{:g, subject, :"$1"}, :"$2"})
    |> Enum.reduce([], fn [stored_dom, stored_role], acc ->
      if dom_matcher.(domain, stored_dom), do: [stored_role | acc], else: acc
    end)
  end

  # Use Depth-First Search. In Elixir (Linked Lists), prepending (DFS) is O(1)
  # while appending (BFS) is O(N). For reachability checks, DFS is superior.
  defp check_link_dfs(_table, [], _target, _domain, _visited, _matchers), do: false

  defp check_link_dfs(table, [current | rest], target, domain, visited, matchers) do
    # 1. Match Check
    is_match =
      if matchers.rn, do: matchers.rn.(current, target), else: current == target

    if is_match do
      true
    else
      # 2. Get Next Level
      direct_roles =
        if matchers.dom do
          get_roles_with_domain_matching(table, current, domain, matchers.dom)
        else
          lookup_roles_direct(table, current, domain)
        end

      # 3. Filter Visited
      # Note: We do this strictly to avoid cycles.
      new_roles = Enum.reject(direct_roles, &MapSet.member?(visited, &1))
      new_visited = Enum.reduce(new_roles, visited, &MapSet.put(&2, &1))

      # 4. DFS Recursion: Prepend `new_roles` to `rest`
      # Logic: [new_1, new_2] ++ [stack_rest...]
      # This is significantly faster than `rest ++ new_roles`
      check_link_dfs(table, new_roles ++ rest, target, domain, new_visited, matchers)
    end
  end
end
