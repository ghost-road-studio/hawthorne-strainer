defmodule Casbin.Behaviour.Watcher do
  @moduledoc """
  The contract for Casbin Watchers, strictly adhering to the WatcherEx interface.
  Supports incremental and batch synchronization of policy changes.
  """

  @type rule :: [String.t()]
  @type ptype :: String.t()
  # e.g., "p" or "g"
  @type section :: String.t()

  # -- 1. Lifecycle --

  @doc "Closes the watcher and releases resources."
  @callback close() :: :ok

  # -- 2. Notification Methods (Called by Enforcer) --

  @doc "Notifies the cluster that a full policy reload is needed."
  @callback update() :: :ok | {:error, term()}

  @doc "Notifies the cluster that a specific policy rule was added."
  @callback update_for_add_policy(section, ptype, rule) :: :ok | {:error, term()}

  @doc "Notifies the cluster that a specific policy rule was removed."
  @callback update_for_remove_policy(section, ptype, rule) :: :ok | {:error, term()}

  @doc "Notifies the cluster that a specific filtered policy was removed."
  @callback update_for_remove_filtered_policy(
              section,
              ptype,
              field_index :: integer(),
              field_values :: [String.t()]
            ) :: :ok | {:error, term()}

  @doc "Notifies the cluster that the policy was saved."
  @callback update_for_save_policy(rules :: [map()]) :: :ok | {:error, term()}

  # -- 3. Batch Notification (WatcherEx) --

  @doc "Notifies the cluster that multiple policy rules were added (Batch)."
  @callback update_for_add_policies(section, ptype, rules :: [rule]) :: :ok | {:error, term()}

  @doc "Notifies the cluster that multiple policy rules were removed (Batch)."
  @callback update_for_remove_policies(section, ptype, rules :: [rule]) :: :ok | {:error, term()}

  # -- 4. Callback Registration --

  @doc "Sets the callback to handle incoming updates from the network."
  @callback set_update_callback(callback :: (term() -> :ok)) :: :ok
end
