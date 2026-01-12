defmodule Casbin.Behaviour.RoleManager do
  @moduledoc """
  The behaviour specification for a Casbin RoleManager.
  """

  @type server :: GenServer.server()
  @type name :: String.t()
  @type domain :: String.t() | nil

  # A matching function takes (arg1, arg2) and returns boolean
  @type matching_func :: (String.t(), String.t() -> boolean())

  # -- Core Graph API --
  @callback clear(server) :: :ok | {:error, term()}
  @callback add_link(server, name1 :: name, name2 :: name, domain :: domain) ::
              :ok | {:error, term()}
  @callback delete_link(server, name1 :: name, name2 :: name, domain :: domain) ::
              :ok | {:error, term()}
  @callback has_link?(server, name1 :: name, name2 :: name, domain :: domain) :: boolean()
  @callback get_roles(server, name :: name, domain :: domain) :: [name]
  @callback get_users(server, name :: name, domain :: domain) :: [name]
  @callback print_roles(server) :: :ok

  # -- Matching Function API --
  # These allow supporting wildcards (e.g. keyMatch) in role or domain names
  @callback add_matching_func(server, func :: matching_func()) :: :ok
  @callback add_domain_matching_func(server, func :: matching_func()) :: :ok
end
