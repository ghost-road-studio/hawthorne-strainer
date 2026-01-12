defmodule Casbin.Engine.RoleManagerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog, only: [capture_log: 1]
  alias Casbin.Engine.RoleManager
  alias Casbin.Engine.RoleManager.Server

  # We use a unique name per test to ensure isolation
  setup context do
    name = String.to_atom("rm_#{context.test}")
    start_supervised!({Server, name: name})

    %{tid: tid} = RoleManager.get_metadata(name)
    {:ok, server: name, tid: tid}
  end

  describe "Basic RBAC (No Domain)" do
    test "add_link and has_link? (direct)", %{server: s, tid: tid} do
      assert :ok == RoleManager.add_link(s, "alice", "admin")
      assert RoleManager.has_link?(tid, "alice", "admin")
      refute RoleManager.has_link?(tid, "alice", "user")
    end

    test "transitive inheritance (BFS)", %{server: s, tid: tid} do
      RoleManager.add_link(s, "alice", "editor")
      RoleManager.add_link(s, "editor", "admin")
      RoleManager.add_link(s, "admin", "root")

      assert RoleManager.has_link?(tid, "alice", "root")
      assert RoleManager.has_link?(tid, "editor", "root")
      refute RoleManager.has_link?(tid, "root", "alice")
    end

    test "get_roles and get_users", %{server: s, tid: tid} do
      RoleManager.add_link(s, "alice", "admin")
      RoleManager.add_link(s, "bob", "admin")

      assert RoleManager.get_roles(tid, "alice") == ["admin"]
      # Order is not guaranteed in ETS bag, so we sort
      assert Enum.sort(RoleManager.get_users(tid, "admin")) == ["alice", "bob"]
      assert RoleManager.get_users(tid, "bogus") == []
    end

    test "delete_link", %{server: s, tid: tid} do
      RoleManager.add_link(s, "alice", "admin")
      RoleManager.delete_link(s, "alice", "admin")

      refute RoleManager.has_link?(tid, "alice", "admin")
      assert RoleManager.get_roles(tid, "alice") == []
    end
  end

  describe "RBAC with Domains" do
    test "domain isolation", %{server: s, tid: tid} do
      RoleManager.add_link(s, "alice", "admin", "domain1")

      assert RoleManager.has_link?(tid, "alice", "admin", "domain1")
      refute RoleManager.has_link?(tid, "alice", "admin", "domain2")
      # No domain
      refute RoleManager.has_link?(tid, "alice", "admin", nil)
    end

    test "transitivity within domain", %{server: s, tid: tid} do
      RoleManager.add_link(s, "u1", "r1", "d1")
      RoleManager.add_link(s, "r1", "r2", "d1")
      # Break chain in different domain
      RoleManager.add_link(s, "r2", "r3", "d2")

      assert RoleManager.has_link?(tid, "u1", "r2", "d1")
      refute RoleManager.has_link?(tid, "u1", "r3", "d1")
    end
  end

  describe "Matching Functions (Wildcards)" do
    test "add_matching_func (Role Wildcards)", %{server: s, tid: tid} do
      # Matcher: "*" matches everything
      matcher = fn p, t -> t == "*" or p == t end
      RoleManager.add_matching_func(s, matcher)

      RoleManager.add_link(s, "alice", "group_1")

      # alice -> group_1. Does alice have group_*?
      # Logic: current(group_1) == target(*) ? Yes.
      assert RoleManager.has_link?(tid, "alice", "*")
    end

    test "add_domain_matching_func (Domain Wildcards)", %{server: s, tid: tid} do
      # Matcher: Pattern matches Target if Target starts with Pattern
      matcher = fn req_domain, stored_domain ->
        String.starts_with?(req_domain, stored_domain)
      end

      RoleManager.add_domain_matching_func(s, matcher)

      # Policy: alice is admin in "base"
      RoleManager.add_link(s, "alice", "admin", "base")

      # Request: Is alice admin in "base_sub1"?
      # stored="base", requested="base_sub1". matcher("base_sub1", "base") -> true
      assert RoleManager.has_link?(tid, "alice", "admin", "base_sub1")
    end
  end

  describe "Edge Cases" do
    test "circular dependencies", %{server: s, tid: tid} do
      RoleManager.add_link(s, "A", "B")
      RoleManager.add_link(s, "B", "C")
      # Cycle
      RoleManager.add_link(s, "C", "A")

      assert RoleManager.has_link?(tid, "A", "C")
      # Should return false and not hang
      refute RoleManager.has_link?(tid, "A", "D")
    end

    test "clear", %{server: s, tid: tid} do
      RoleManager.add_link(s, "A", "B")
      RoleManager.clear(s)
      refute RoleManager.has_link?(tid, "A", "B")
      assert RoleManager.get_roles(tid, "A") == []
    end
  end

  describe "Observability" do
    test "print_roles/1 outputs graph to logger", %{server: s, tid: tid} do
      RoleManager.add_link(s, "alice", "admin")
      RoleManager.add_link(s, "bob", "editor", "domain1")

      assert capture_log(fn ->
               assert :ok == RoleManager.print_roles(tid)
             end) =~ ~r/\[info\] RoleManager \((?<context>.*)\) State:\n(?<state>[\s\S]*)/s
    end
  end

  describe "Advanced Domain Matching" do
    test "get_roles/3 with domain matching function", %{server: s, tid: tid} do
      # 1. Define a domain matcher (e.g., standard Casbin behavior where stored domain can be a pattern)
      # Matcher returns true if the requested domain matches the stored pattern.
      # fn(requested, stored_pattern)
      matcher = fn req, stored ->
        stored == "*" or req == stored
      end

      RoleManager.add_domain_matching_func(s, matcher)

      # 2. Setup Policies
      # "alice" is "global_admin" in ALL domains ("*")
      RoleManager.add_link(s, "alice", "global_admin", "*")
      # "alice" is "local_admin" only in "domain1"
      RoleManager.add_link(s, "alice", "local_admin", "domain1")
      # "alice" is "tenant_user" in "domain2"
      RoleManager.add_link(s, "alice", "tenant_user", "domain2")

      # 3. Test: Request roles for "domain1"
      # Should match:
      # - "global_admin" (because stored "*" matches req "domain1")
      # - "local_admin"  (because stored "domain1" matches req "domain1")
      # Should NOT match: "tenant_user"
      roles_d1 = RoleManager.get_roles(tid, "alice", "domain1")
      assert length(roles_d1) == 2
      assert "global_admin" in roles_d1
      assert "local_admin" in roles_d1
      refute "tenant_user" in roles_d1

      # 4. Test: Request roles for "domain3" (unknown domain)
      # Should match: "global_admin" only (due to wildcard)
      roles_d3 = RoleManager.get_roles(tid, "alice", "domain3")
      assert roles_d3 == ["global_admin"]
    end
  end
end
