defmodule Casbin.Engine.MatcherCompiler do
  @moduledoc """
  Compiles Casbin matcher configuration strings into high-performance, executable Elixir functions.

  ## Architectural Significance

  In many Casbin implementations, the matcher expression (e.g., `m = g(r.sub, p.sub) && r.obj == p.obj`)
  is interpreted at runtime using an expression evaluator. This is flexible but slow, often becoming
  the bottleneck in high-throughput systems (ops/sec < 50k).

  This module takes a **Transpilation approach**:
  1.  **Parse:** It parses the matcher string into Elixir AST (Abstract Syntax Tree).
  2.  **Transform:** It walks the AST to replace Casbin DSL elements with native Elixir calls.
  3.  **Compile:** It generates an anonymous function `fn(r, p) -> boolean` and compiles it using the BEAM.

  ## Transformations

  ### 1. Field Access
  Casbin uses `r.sub`, `p.obj`, etc. These are mapped to list indices based on the `[request_definition]`.
  *   **Source:** `r.sub == p.sub`
  *   **Compiled:** `Enum.at(r, 0) == Enum.at(p, 0)` (Assuming `sub` is at index 0).

  ### 2. Role Manager Injection
  Casbin uses `g(user, role)` checks. These are mapped to specific, named `RoleManager` processes.
  *   **Source:** `g(r.sub, p.sub)`
  *   **Compiled:** `Casbin.Engine.RoleManager.has_link?(:casbin_rm_roles, Enum.at(r, 0), Enum.at(p, 0))`
  *   *Note:* The mapping of `g` -> `:casbin_rm_roles` is provided during compilation.

  ### 3. Built-in Operators
  Casbin standard functions are mapped to `Casbin.Util.BuiltinOperators`.
  *   **Source:** `keyMatch(r.obj, p.obj)`
  *   **Compiled:** `Casbin.Util.BuiltinOperators.key_match(...)`

  ## Performance

  The resulting function is native BEAM bytecode. It executes at the speed of raw Elixir code,
  enabling millions of checks per second.
  """
  alias Casbin.Model
  require Logger

  @doc """
  Compiles the matcher string from the Model into an anonymous function.

  Returns `{:ok, fn(request_vals, policy_vals) -> boolean}`.

  ## Arguments
  * `model`: The loaded `Casbin.Model` struct containing definitions and the matcher string.
  * `rm_map`: A map linking matcher functions to registered RoleManager names.
    *   Example: `%{"g" => :casbin_rm_roles, "g2" => :casbin_rm_domains}`

  ## Runtime Inputs
  The generated function expects two arguments:
  1.  `r` (List): The request values (e.g., `["alice", "data1", "read"]`).
  2.  `p` (List): The policy rule values (e.g., `["alice", "data1", "read"]`).
  """
  def compile(%Model{request: request, policy: policy, matchers: matchers}, rm_map \\ %{}) do
    matcher_str = matchers["m"]

    # 1. Map fields to indices (e.g., r.sub -> 0)
    r_def_str = Map.get(request, "r", "")
    p_def_str = Map.get(policy, "p", "")

    r_def = parse_keys(r_def_str)
    p_def = parse_keys(p_def_str)

    # 2. Parse string to AST
    ast = Code.string_to_quoted!(matcher_str)

    # 3. Create Clean Variables for the function arguments
    # Macro.var/2 with `nil` context ensures the variables are hygienic/global
    # within the context of the generated function.
    r_var = Macro.var(:r, nil)
    p_var = Macro.var(:p, nil)
    {bindings, var_lookup_map} = prepare_bindings(rm_map)

    # 4. Walk and Transform AST
    transformed_ast =
      Macro.prewalk(ast, fn node ->
        transform_node(node, r_def, p_def, var_lookup_map, r_var, p_var)
      end)

    # 5. Wrap in anonymous function definition using `quote`
    # This is safer than manual {:fn, ...} construction as it handles metadata and structure automatically.
    final_ast =
      quote do
        fn unquote(r_var), unquote(p_var) ->
          unquote(transformed_ast)
        end
      end

    # 6. Compile
    {func, _bindings} = Code.eval_quoted(final_ast, bindings)
    {:ok, func}
  rescue
    e in RuntimeError ->
      Logger.error("Matcher Compilation Failed: #{inspect(e)}")
      {:error, "Failed to compile matcher: #{e.message}"}
  end

  # -- AST Transformations --

  # 1. Handle Field Access: r.sub -> Enum.at(r, index)
  # We construct the AST manually: {{:., [], [{:__aliases__, ..., [:Enum]}, :at]}, [], [r_var, idx]}
  defp transform_node({{:., _, [{:r, _, _}, field]}, _, _}, r_def, _, _, r_var, _) do
    idx = Map.fetch!(r_def, Atom.to_string(field))

    # Equivalent to: Enum.at(r, idx)
    {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :at]}, [], [r_var, idx]}
  end

  defp transform_node({{:., _, [{:p, _, _}, field]}, _, _}, _, p_def, _, _, p_var) do
    idx = Map.fetch!(p_def, Atom.to_string(field))

    # Equivalent to: Enum.at(p, idx)
    {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :at]}, [], [p_var, idx]}
  end

  # 2. Handle Role Manager calls: g(u, r) -> RoleManager.has_link?(name, u, r)
  defp transform_node({function_name, _meta, args}, _, _, var_lookup_map, _, _) when function_name in [:g, :g2, :g3] do
    # Look up the AST variable associated with this function name
    tid_var_ast = Map.get(var_lookup_map, Atom.to_string(function_name))

    if tid_var_ast do
      quote do
        # We unquote the VARIABLE AST (e.g., var_g), not the Reference itself.
        # At runtime, Elixir looks up var_g in the closure and finds the TID.
        Casbin.Engine.RoleManager.has_link?(unquote(tid_var_ast), unquote_splicing(args))
      end
    else
      raise "RoleManager for '#{function_name}' not found in configuration."
    end
  end

  # 3. Handle Built-in Operators
  defp transform_node({:keyMatch, _, args}, _, _, _, _, _) do
    quote do: Casbin.Util.BuiltinOperators.key_match(unquote_splicing(args))
  end

  defp transform_node({:keyMatch2, _, args}, _, _, _, _, _) do
    quote do: Casbin.Util.BuiltinOperators.key_match2(unquote_splicing(args))
  end

  defp transform_node({:keyMatch3, _, args}, _, _, _, _, _) do
    quote do: Casbin.Util.BuiltinOperators.key_match3(unquote_splicing(args))
  end

  defp transform_node({:regexMatch, _, args}, _, _, _, _, _) do
    quote do: Casbin.Util.BuiltinOperators.regex_match(unquote_splicing(args))
  end

  defp transform_node({:ipMatch, _, args}, _, _, _, _, _) do
    quote do: Casbin.Util.BuiltinOperators.ip_match(unquote_splicing(args))
  end

  # 4. Pass-through everything else
  defp transform_node(node, _, _, _, _, _), do: node

  # -- Helpers --

  defp parse_keys(def_str) do
    def_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.with_index()
    |> Map.new(fn {k, i} -> {k, i} end)
  end

  defp prepare_bindings(rm_map) do
    # Input: %{"g" => #Ref<...>}
    # Output:
    #   bindings: [var_g: #Ref<...>]
    #   map:      %{"g" => Macro.var(:var_g, nil)}

    Enum.reduce(rm_map, {[], %{}}, fn {key, tid}, {bind_acc, map_acc} ->
      # Create a unique atom name for the variable
      var_name = String.to_atom("casbin_rm_var_#{key}")

      # Create the AST node for that variable
      var_ast = Macro.var(var_name, nil)

      # Add to keyword list of bindings
      new_binds = [{var_name, tid} | bind_acc]

      # Add to lookup map
      new_map = Map.put(map_acc, key, var_ast)

      {new_binds, new_map}
    end)
  end
end
