defmodule Casbin.Model do
  @moduledoc """
  Represents a parsed Casbin Model (PERM).
  """
  alias Casbin.Model.Parser

  defstruct [
    # Map of key -> definition string
    # e.g., request: %{"r" => "sub, obj, act"}
    request: %{},
    policy: %{},
    role: %{},
    effect: %{},
    matchers: %{}
  ]

  @doc "Creates a new empty model."
  def new, do: %__MODULE__{}

  @doc "Loads a model from a file."
  def new(path) do
    Parser.parse_file(path)
  end

  @doc "Loads a model from a string."
  def new_from_text(text) do
    Parser.parse_text(text)
  end
end
