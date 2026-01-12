defmodule Casbin.Engine.MatcherCompilerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias Casbin.Engine.MatcherCompiler
  alias Casbin.Model
  alias Casbin.Engine.RoleManager
  alias Casbin.Engine.RoleManager.Server

  describe "simple equality matchers" do
    test "compiles r.sub == p.sub" do
      model = build_model("r.sub == p.sub")
      {:ok, func} = MatcherCompiler.compile(model)

      # r = [sub, obj, act]
      assert func.(["alice", "d1", "read"], ["alice", "d2", "write"])
      refute func.(["bob", "d1", "read"], ["alice", "d2", "write"])
    end

    test "compiles boolean logic (&&)" do
      model = build_model("r.sub == p.sub && r.act == p.act")
      {:ok, func} = MatcherCompiler.compile(model)

      # Match
      assert func.(["alice", "d1", "read"], ["alice", "d1", "read"])
      # Sub mismatch
      refute func.(["bob", "d1", "read"], ["alice", "d1", "read"])
      # Act mismatch
      refute func.(["alice", "d1", "read"], ["alice", "d1", "write"])
    end
  end

  describe "built-in operators" do
    test "compiles keyMatch" do
      model = build_model("keyMatch(r.obj, p.obj)")
      {:ok, func} = MatcherCompiler.compile(model)

      # Wildcard match
      assert func.(["_", "/data/1", "_"], ["_", "/data/*", "_"])
      # Mismatch
      refute func.(["_", "/api/1", "_"], ["_", "/data/*", "_"])
    end

    test "compiles keyMatch2 (:param syntax)" do
      model = build_model("keyMatch2(r.obj, p.obj)")
      {:ok, func} = MatcherCompiler.compile(model)

      assert func.(["_", "/resource/123", "_"], ["_", "/resource/:id", "_"])
    end
  end

  describe "RBAC (g functions)" do
    setup do
      # Start a real RoleManager for the compiled function to call
      rm_name = :test_rm_compiler
      start_supervised!({Server, name: rm_name})

      %{tid: tid} = RoleManager.get_metadata(rm_name)
      {:ok, rm: rm_name, tid: tid}
    end

    test "injects RoleManager calls correctly", %{rm: rm_name, tid: tid} do
      # Setup Hierarchy: alice -> admin
      RoleManager.add_link(rm_name, "alice", "admin")

      model = build_model("g(r.sub, p.sub)")

      # We provide the mapping: "g" in string -> :test_rm_compiler process
      rm_map = %{"g" => tid}
      {:ok, func} = MatcherCompiler.compile(model, rm_map)

      # Test: does alice have admin role?
      # r.sub = "alice", p.sub = "admin"
      assert func.(["alice", "_", "_"], ["admin", "_", "_"])

      # Test: does bob have admin role?
      refute func.(["bob", "_", "_"], ["admin", "_", "_"])
    end

    test "fails compilation if RoleManager not mapped", %{rm: _rm} do
      model = build_model("g(r.sub, p.sub)")

      capture_log(fn ->
        # Passing empty map -> should fail because 'g' is not mapped
        assert {:error, message} = MatcherCompiler.compile(model, %{})
        assert message =~ "RoleManager for 'g' not found"
      end) =~ ~r/\[error\] Matcher Compilation Failed: (?<context>.*)/s
    end
  end

  # Basic Model structure helper
  defp build_model(matcher_str) do
    %Model{
      request: %{"r" => "sub, obj, act"},
      policy: %{"p" => "sub, obj, act"},
      role: %{"g" => "_, _"},
      matchers: %{"m" => matcher_str}
    }
  end
end
