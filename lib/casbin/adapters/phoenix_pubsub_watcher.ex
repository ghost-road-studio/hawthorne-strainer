defmodule Casbin.Adapters.Watcher.PhoenixPubSub do
  @moduledoc """
  WatcherEx implementation using Phoenix.PubSub.
  """
  @behaviour Casbin.Behaviour.Watcher
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # -- Behaviour Implementation --

  @impl true
  def close() do
    GenServer.stop(__MODULE__, :normal)
  end

  @impl true
  def update(), do: broadcast({:casbin_update, :full_reload})

  @impl true
  def update_for_add_policy(sec, ptype, rule) do
    broadcast({:casbin_update, :add_policy, sec, ptype, rule})
  end

  @impl true
  def update_for_remove_policy(sec, ptype, rule) do
    broadcast({:casbin_update, :remove_policy, sec, ptype, rule})
  end

  @impl true
  def update_for_remove_filtered_policy(sec, ptype, idx, values) do
    broadcast({:casbin_update, :remove_filtered_policy, sec, ptype, idx, values})
  end

  @impl true
  def update_for_save_policy(_rules), do: update()

  @impl true
  def update_for_add_policies(sec, ptype, rules) do
    broadcast({:casbin_update, :add_policies, sec, ptype, rules})
  end

  @impl true
  def update_for_remove_policies(sec, ptype, rules) do
    broadcast({:casbin_update, :remove_policies, sec, ptype, rules})
  end

  @impl true
  def set_update_callback(callback) do
    GenServer.call(__MODULE__, {:set_callback, callback})
  end

  # -- Internals --

  defp broadcast(msg) do
    GenServer.cast(__MODULE__, {:broadcast, msg})
  end

  # -- GenServer Callbacks --

  @impl true
  def init(opts) do
    pubsub = Keyword.fetch!(opts, :pubsub)
    topic = Keyword.get(opts, :topic, "casbin:updates")
    Phoenix.PubSub.subscribe(pubsub, topic)
    {:ok, %{pubsub: pubsub, topic: topic, callback: nil}}
  end

  @impl true
  def handle_cast({:broadcast, msg}, state) do
    Phoenix.PubSub.broadcast(state.pubsub, state.topic, msg)
    {:noreply, state}
  end

  @impl true
  def handle_call({:set_callback, callback}, _from, state) do
    {:reply, :ok, %{state | callback: callback}}
  end

  @impl true
  def handle_info({:casbin_update, _type, _args} = event, state) do
    if state.callback, do: state.callback.(event)
    {:noreply, state}
  end

  @impl true
  def handle_info({:casbin_update, :full_reload} = event, state) do
    if state.callback, do: state.callback.(event)
    {:noreply, state}
  end

  # Handle Batch events
  @impl true
  def handle_info({:casbin_update, _op, _sec, _ptype, _rules} = event, state) do
    if state.callback, do: state.callback.(event)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:casbin_update, :remove_filtered_policy, _sec, _ptype, _idx, _values} = event,
        state
      ) do
    if state.callback, do: state.callback.(event)
    {:noreply, state}
  end
end
