# bench/scale_bench.exs

alias Casbin.Engine.RoleManager.Server
alias Casbin.Engine.RoleManager

# 1. Start the Role Manager
{:ok, _pid} = Server.start_link(name: :scale_rm)
%{tid: tid} = RoleManager.get_metadata(:scale_rm)

# 2. Configuration
total_users = 500_000
total_subs = 50_000
users_per_sub = div(total_users, total_subs)

IO.puts """
=============================================================
Generating Data:
- #{total_users} Users
- #{total_subs} Subscriptions
- Hierarchy: owner > admin > editor > viewer
=============================================================
"""

# 3. Seed Hierarchy (The "g" graph)
# This simulates the static role definitions
# We use a global domain "*" for base roles or just define inheritance
# owner -> admin -> editor -> viewer
RoleManager.add_link(:scale_rm, "owner", "admin")
RoleManager.add_link(:scale_rm, "admin", "editor")
RoleManager.add_link(:scale_rm, "editor", "viewer")

# 4. Seed User Data
# We populate ETS with 500k entries.
# This might take a few seconds to insert, but we care about READ speed.
{time_us, _} = :timer.tc(fn ->
  1..total_subs
  |> Enum.each(fn sub_id ->
    domain = "sub_#{sub_id}"

    # Create 10 users per sub
    # User 1: Owner
    # User 2: Admin
    # User 3-10: Viewers
    base_idx = (sub_id - 1) * users_per_sub

    RoleManager.add_link(:scale_rm, "user_#{base_idx + 1}", "owner", domain)
    RoleManager.add_link(:scale_rm, "user_#{base_idx + 2}", "admin", domain)

    3..users_per_sub
    |> Enum.each(fn i ->
      RoleManager.add_link(:scale_rm, "user_#{base_idx + i}", "viewer", domain)
    end)
  end)
end)

IO.puts "Seeding completed in #{div(time_us, 1000)}ms"
IO.puts "ETS Table Info: #{inspect(:ets.info(tid))}"

# 5. Define Benchmarks
Benchee.run(
  %{
    # Scenario 1: The "Happy Path" (Direct Check)
    # Check if a specific user is a viewer in their subscription.
    # This hits the exact key {user, domain} -> viewer.
    "check_direct_role (viewer)" => fn ->
      # Pick a random user (e.g., user_500003 is a viewer in sub_50001)
      # We hardcode one for stability or generate randoms if desired.
      # User 15 is in sub 2 (index 10..19)
      RoleManager.has_link?(tid, "user_15", "viewer", "sub_2")
    end,

    # Scenario 2: The "Hierarchy Check" (Transitive)
    # Check if an OWNER is implicitly a VIEWER (requires traversing 3 hops).
    # owner -> admin -> editor -> viewer
    "check_transitive_role (owner -> viewer)" => fn ->
      # User 11 is owner of sub 2
      RoleManager.has_link?(tid, "user_11", "viewer", "sub_2")
    end,

    # Scenario 3: Cross-Tenant Miss (Security Check)
    # Check if User A (from Sub 1) has access to Sub 2.
    # This ensures our domain isolation doesn't slow down on misses.
    "check_cross_tenant_miss" => fn ->
      RoleManager.has_link?(tid, "user_1", "viewer", "sub_5000")
    end
  },
  time: 10,
  memory_time: 2,
  parallel: 4,
  formatters: [Benchee.Formatters.Console]
)
