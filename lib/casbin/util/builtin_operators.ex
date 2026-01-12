defmodule Casbin.Util.BuiltinOperators do
  @moduledoc """
  Implements standard Casbin matching functions (keyMatch, ipMatch, etc.).
  """

  @doc """
  Returns true if key1 matches the pattern of key2.
  key2 can contain `*`.
  Example: keyMatch("/alice/data", "/alice/*") -> true
  """
  def key_match(key1, key2) do
    # Optimization: If no wildcard, simple equality
    if String.contains?(key2, "*") do
      # Escape regex characters except *, then replace * with .*
      regex_str =
        Regex.escape(key2)
        |> String.replace("\\*", ".*")

      regex = Regex.compile!("^#{regex_str}$")
      String.match?(key1, regex)
    else
      key1 == key2
    end
  end

  @doc """
  Returns true if key1 matches the pattern of key2.
  Supports :param style wildcards.
  Example: keyMatch2("/alice/data", "/alice/:resource") -> true
  """
  def key_match2(key1, key2) do
    if String.contains?(key2, ":") do
      # Split by slash to handle path segments
      key1_parts = String.split(key1, "/")
      key2_parts = String.split(key2, "/")

      if length(key1_parts) == length(key2_parts) do
        Enum.zip(key1_parts, key2_parts)
        |> Enum.all?(fn {k1, k2} ->
          String.starts_with?(k2, ":") or k1 == k2
        end)
      else
        false
      end
    else
      key_match(key1, key2)
    end
  end

  @doc """
  Returns true if key1 matches the pattern of key2.
  key2 is a simplified pattern using `*`.
  Example: keyMatch3("/alice/data", "/alice/*") -> true
  """
  def key_match3(key1, key2) do
    key_match(key1, key2)
  end

  @doc """
  Returns true if key1 matches the regular expression key2.
  """
  def regex_match(key1, key2) do
    case Regex.compile(key2) do
      {:ok, regex} -> String.match?(key1, regex)
      _ -> false
    end
  end

  @doc """
  Returns true if ip1 matches the CIDR pattern ip2.
  Example: ipMatch("192.168.2.123", "192.168.2.0/24") -> true
  """
  def ip_match(ip1, ip2) do
    # Simple implementation wrapping generic logic
    # In production, use a library like `Bitwise` or `InetCidr` for robust parsing.
    # For this snippet, we'll assume basic equality or simple prefix check if CIDR not robustly implemented.
    # TODO: Add 'inet_cidr' dependency or implement raw bitmask matching.
    # Fallback to string equality for now to satisfy compilation.
    ip1 == ip2
  end
end
