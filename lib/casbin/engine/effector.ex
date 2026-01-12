defmodule Casbin.Engine.Effector do
  @moduledoc """
  The logic engine for the `[policy_effect]` definition.

  In the **PERM** model (Policy, Effect, Request, Matchers), the Effector decides the
  final result of an authorization request based on the results of individual policy rules.

  ## Architecture: Stream-Based Reduction

  To support high throughput, the Enforcer produces a **lazy Stream** of policy results
  (e.g., `:allow`, `:deny`, `:indeterminate`). This module provides reducer functions that
  consume this stream.

  This approach is efficient because it allows **short-circuiting**. For example, in an
  `allow-override` strategy, the reducer stops processing as soon as the first `:allow`
  is found, avoiding unnecessary computation for the remaining policies.

  ## Supported Effects

  1.  **Allow Override** (`some(where (p.eft == allow))`)
      *   If *any* policy returns allow, the result is `true`.
      *   Otherwise, `false`.

  2.  **Deny Override** (`some(where (p.eft == allow)) && !some(where (p.eft == deny))`)
      *   If *any* policy returns deny, the result is `false` (immediately).
      *   If there is at least one allow and NO deny, the result is `true`.
      *   Otherwise, `false`.

  3.  **Priority** (`priority(p.eft) || deny`)
      *   The order of policies determines the result.
      *   The first policy to return `:allow` or `:deny` (non-indeterminate) wins.
      *   If no match is found, defaults to deny (`false`).
  """

  @type effect :: :allow | :deny | :indeterminate
  @type effector_func :: (Enumerable.t(effect) -> boolean)

  @doc """
  Compiles the policy effect string into an executable reducer function.
  """
  @spec get_effector(String.t()) :: effector_func()
  def get_effector(expr) do
    # Normalize: Remove spaces/tabs to handle minor formatting differences
    expr
    |> String.replace([" ", "\t", "\n"], "")
    |> match_expression()
  end

  defp match_expression("some(where(p.eft==allow))"), do: &allow_override/1

  defp match_expression("some(where(p.eft==allow))&&!some(where(p.eft==deny))"),
    do: &allow_and_deny_override/1

  defp match_expression("priority(p.eft)||deny"), do: &priority/1

  defp match_expression(expr),
    do:
      raise(
        ArgumentError,
        "Casbin.Engine.Effector: Unsupported Policy Effect expression: '#{expr}'"
      )

  # -- Strategy Implementations --

  # Allow-Override: Short-circuit on first allow
  defp allow_override(effects) do
    Enum.any?(effects, fn e -> e == :allow end)
  end

  # Deny-Override: Short-circuit on first deny, but must track if we saw an allow
  defp allow_and_deny_override(effects) do
    Enum.reduce_while(effects, :indeterminate, fn effect, acc ->
      case effect do
        # Stop immediately, Deny wins
        :deny -> {:halt, :deny}
        # Record allow, but keep checking for deny
        :allow -> {:cont, :allow}
        # Ignore indeterminate
        _ -> {:cont, acc}
      end
    end) == :allow
  end

  # Priority: Short-circuit on first definitive result
  defp priority(effects) do
    # Default is :deny if stream is empty or all indeterminate
    Enum.find(effects, :deny, fn e -> e != :indeterminate end) == :allow
  end
end
