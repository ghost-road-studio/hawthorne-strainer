defmodule Casbin.Adapters.Watcher.PhoenixPubSubTest do
  use ExUnit.Case
  alias Casbin.Adapters.Watcher.PhoenixPubSub
  alias Phoenix.PubSub

  setup do
    # Start a PubSub server specifically for this test
    pubsub_name = :test_pubsub
    start_supervised!({Phoenix.PubSub.Supervisor, name: pubsub_name})
    {:ok, pubsub: pubsub_name}
  end

  describe "broadcasts" do
    test "sends basic update events to the topic", %{pubsub: ps} do
      topic = "policy_updates"

      # Start the watcher with a specific name
      start_supervised!({PhoenixPubSub, pubsub: ps, topic: topic})

      # Subscribe manually to verify what gets sent
      PubSub.subscribe(ps, topic)

      # 1. Add Policy
      PhoenixPubSub.update_for_add_policy("p", "p", ["alice", "data1", "read"])
      assert_receive {:casbin_update, :add_policy, "p", "p", ["alice", "data1", "read"]}, 500

      # 2. Remove Policy
      PhoenixPubSub.update_for_remove_policy("p", "p", ["bob", "data2", "write"])
      assert_receive {:casbin_update, :remove_policy, "p", "p", ["bob", "data2", "write"]}, 500

      # 3. Remove Filtered Policy
      # Example: Remove all rules where v0 == "alice" (index 0)
      PhoenixPubSub.update_for_remove_filtered_policy("p", "p", 0, ["alice"])
      assert_receive {:casbin_update, :remove_filtered_policy, "p", "p", 0, ["alice"]}, 500

      PhoenixPubSub.update()
      assert_receive {:casbin_update, :full_reload}, 500
    end

    test "save_policy triggers a full reload broadcast", %{pubsub: ps} do
      topic = "policy_save"
      start_supervised!({PhoenixPubSub, pubsub: ps, topic: topic})
      PubSub.subscribe(ps, topic)

      # Calling save_policy should default to requesting a full update/reload
      PhoenixPubSub.update_for_save_policy([])
      assert_receive {:casbin_update, :full_reload}, 500
    end
  end

  describe "batch operations" do
    test "broadcasts update_for_add_policies (batch add)", %{pubsub: ps} do
      topic = "policy_batch_add"
      start_supervised!({PhoenixPubSub, pubsub: ps, topic: topic})
      PubSub.subscribe(ps, topic)

      rules = [
        ["alice", "data1", "read"],
        ["bob", "data2", "write"]
      ]

      # 1. Trigger Batch Add
      PhoenixPubSub.update_for_add_policies("p", "p", rules)

      # 2. Assert Message
      assert_receive {:casbin_update, :add_policies, "p", "p", ^rules}, 500
    end

    test "broadcasts update_for_remove_policies (batch remove)", %{pubsub: ps} do
      topic = "policy_batch_remove"
      start_supervised!({PhoenixPubSub, pubsub: ps, topic: topic})
      PubSub.subscribe(ps, topic)

      rules = [["alice", "data1", "read"]]

      # 1. Trigger Batch Remove
      PhoenixPubSub.update_for_remove_policies("p", "p", rules)

      # 2. Assert Message
      assert_receive {:casbin_update, :remove_policies, "p", "p", ^rules}, 500
    end
  end

  describe "generic event handling" do
    test "handle_info triggers callback for generic 3-element tuples", %{pubsub: ps} do
      topic = "policy_generic"
      start_supervised!({PhoenixPubSub, pubsub: ps, topic: topic})

      # 1. Setup Callback to trap the event
      test_pid = self()
      callback = fn event -> send(test_pid, {:callback_fired, event}) end
      PhoenixPubSub.set_update_callback(callback)

      # 2. Broadcast a custom 3-element tuple that matches {:casbin_update, _type, _args}
      # This targets the specific code path you highlighted.
      custom_event = {:casbin_update, :custom_operation, %{reason: "manual_trigger"}}
      PubSub.broadcast(ps, topic, custom_event)

      # 3. Verify the handle_info clause caught it and fired the callback
      assert_receive {:callback_fired, ^custom_event}, 500
    end
  end

  describe "lifecycle" do
    test "executes callback when update received", %{pubsub: ps} do
      topic = "policy_sync"
      start_supervised!({PhoenixPubSub, pubsub: ps, topic: topic})

      test_pid = self()
      callback = fn event -> send(test_pid, {:callback_triggered, event}) end

      # Register the callback
      PhoenixPubSub.set_update_callback(callback)

      # Simulate an incoming message
      event = {:casbin_update, :add_policy, "p", "p", ["alice", "domain1"]}
      PubSub.broadcast(ps, topic, event)

      assert_receive {:callback_triggered, ^event}, 500
    end

    test "close/1 stops the watcher process", %{pubsub: ps} do
      topic = "policy_close"

      # Start the watcher
      {:ok, pid} = start_supervised({PhoenixPubSub, pubsub: ps, topic: topic})

      # Monitor the process to verify termination
      ref = Process.monitor(pid)

      # Call close
      PhoenixPubSub.close()

      # Assert the process goes down with :normal reason
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
      refute Process.alive?(pid)
    end
  end
end
