defmodule Casbin.Model.Parser do
  @moduledoc """
  Parses Casbin configuration files (.conf) into `Casbin.Model` structs.

  This module handles the standard Casbin INI-style format. It processes the text
  line-by-line, organizing definitions into the standard PERM (Policy, Effect, Request, Matchers)
  sections.

  ## Supported Sections
  *   `[request_definition]` - Defines arguments (e.g., `r = sub, obj, act`)
  *   `[policy_definition]` - Defines policy columns (e.g., `p = sub, obj, act`)
  *   `[role_definition]`   - Defines role graph keys (e.g., `g = _, _`)
  *   `[policy_effect]`     - Defines allow/deny logic (e.g., `e = some(where (p.eft == allow))`)
  *   `[matchers]`          - Defines the matching expression (e.g., `m = r.sub == p.sub`)

  ## Behavior
  *   Lines starting with `#` are treated as comments and ignored.
  *   Empty lines are ignored.
  *   Invalid lines (lines inside a section not containing `=`) are logged as warnings and skipped.
  """
  alias Casbin.Model
  require Logger

  @doc "Reads a file from the given path and parses it."
  def parse_file(path) do
    path
    |> File.read!()
    |> parse_text()
  end

  @doc "Parses a raw string representing the model configuration."
  def parse_text(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.reduce({%Model{}, nil}, &process_line/2)
    |> elem(0)
  end

  defp process_line(line, {model, current_section}) do
    if String.starts_with?(line, "[") and String.ends_with?(line, "]") do
      section =
        line
        |> String.slice(1..-2//1)
        |> String.trim()

      {model, section}
    else
      parse_definition(line, model, current_section)
    end
  end

  defp parse_definition(line, model, section) do
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)
        update_model(model, section, key, value)

      _ ->
        Logger.warning("[Casbin.Model.Parser] Skipping invalid line: #{inspect(line)}")
        {model, section}
    end
  end

  defp update_model(model, section, key, value) do
    updated_model =
      case section do
        "request_definition" ->
          %{model | request: Map.put(model.request, key, value)}

        "policy_definition" ->
          %{model | policy: Map.put(model.policy, key, value)}

        "role_definition" ->
          %{model | role: Map.put(model.role, key, value)}

        "policy_effect" ->
          %{model | effect: Map.put(model.effect, key, value)}

        "matchers" ->
          %{model | matchers: Map.put(model.matchers, key, value)}

        _ ->
          # Unknown section, ignore data
          model
      end

    {updated_model, section}
  end
end
