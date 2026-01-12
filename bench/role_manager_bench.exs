# bench/role_manager_bench.exs

alias Casbin.Engine.RoleManager.Server
alias Casbin.Engine.RoleManager

# 1. Setup the Environment
# We start the RoleManager GenServer with a local name.
{:ok, _pid} = Server.start_link(name: :bench_rm)

# CRITICAL: Retrieve the ETS Table ID (TID)
# The Read API (has_link?, get_roles) requires direct memory access via this TID.
%{tid: tid} = RoleManager.get_metadata(:bench_rm)

IO.puts("Seeding Role Hierarchy...")

# 2. Seed Data (Writes use the GenServer Name/PID)
# Scenario A: Broad / Flat (Common SaaS)
# User X has Role "admin"
1..1_000
|> Enum.each(fn i ->
  RoleManager.add_link(:bench_rm, "user_#{i}", "role_#{i}")
end)

# Scenario B: Deep Inheritance (The "Stress Test")
# deep_user -> level_1 -> level_2 ... -> level_10 -> root
RoleManager.add_link(:bench_rm, "deep_user", "level_1")
1..9
|> Enum.each(fn i ->
  RoleManager.add_link(:bench_rm, "level_#{i}", "level_#{i + 1}")
end)
RoleManager.add_link(:bench_rm, "level_10", "root")

IO.puts("Seeding Complete. Starting Benchmarks...")

# 3. Define the Benchmarks
# Note: All READ operations here must use `tid`.
Benchee.run(
  %{
    # 1. O(1) Lookup - The most common operation
    "direct_has_link (Flat)" => fn ->
      RoleManager.has_link?(tid, "user_500", "role_500")
    end,

    # 2. O(1) Lookup - Miss Case (Verifies hashing speed on fail)
    "direct_has_link (Miss)" => fn ->
      RoleManager.has_link?(tid, "user_500", "non_existent_role")
    end,

    # 3. DFS Traversal - 10 Hops Deep
    # Tests the cost of deep RBAC hierarchies using the optimized DFS approach
    "transitive_has_link (Deep - 10 hops)" => fn ->
      RoleManager.has_link?(tid, "deep_user", "root")
    end,

    # 4. Get Roles (List retrieval)
    "get_roles (Direct)" => fn ->
      RoleManager.get_roles(tid, "user_500")
    end
  },
  time: 10,
  memory_time: 2,
  parallel: 4, # Simulate 4 concurrent requests (like Phoenix)
  formatters: [
    Benchee.Formatters.Console
  ]
)
