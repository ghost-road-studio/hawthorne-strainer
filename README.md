# Hawthorne Strainer: High-Performance Casbin for Elixir

A robust, distributed-ready implementation of the [Casbin Authorization Specification](https://casbin.org/docs/overview) for Elixir.

**Objective:** To provide an authorization engine capable of handling **millions of enforcement checks per second** in high-throughput, multi-node environments without becoming a system bottleneck.

## ⚡ The Performance Philosophy

In high-scale Elixir applications, authorization is often on the "hot path"—every HTTP request or socket message requires a permission check. If the authorization system relies on a single process (like a GenServer) for every check, that process becomes a sequential bottleneck, capping system throughput regardless of how many CPU cores you add.

This library is architected from the ground up to eliminate these bottlenecks using a **"Read-Local, Write-Global"** strategy.

### 1. Zero-Message Enforcement (Read-Local)
Standard GenServer architectures require passing messages between processes (`GenServer.call`). This introduces latency and serialization.
*   **Our Approach:** The `enforce` logic runs entirely within the **client process** (e.g., your Phoenix Controller or LiveView PID).
*   **Mechanism:** It reads directly from **ETS (Erlang Term Storage)** tables marked with `{:read_concurrency, true}`.
*   **Result:** Permission checks are wait-free, parallel, and limited only by memory speed, not process mailbox capacity.

### 2. Optimized Graph Traversal
RBAC (Role-Based Access Control) often requires traversing deep hierarchies (e.g., `User` -> `Team Lead` -> `Manager` -> `Admin`).
*   **Our Approach:** Instead of using flat lists or heavy graph libraries, we use a custom, ETS-backed implementation of **Depth-First Search (DFS)** optimized for Elixir's linked lists.
*   **Indexing:** We maintain dual indexes (`Subject -> Role` and `Role -> Subject`) to ensure O(1) complexity for direct lookups.

### 3. Fast Configuration via Persistent Terms
Casbin features "Matching Functions" (e.g., using Regex or wildcards in policy rules).
*   **Our Approach:** These static configurations are compiled into executable functions and stored in **`:persistent_term`**, a highly optimized storage mechanism in the BEAM virtual machine designed for constant-time access to data that is read frequently but updated rarely.

### 4. Distributed & Fault-Tolerant
*   **Consistency:** The database (e.g., Postgres) remains the Source of Truth.
*   **Synchronization:** Writes are serialized through a local coordinator to ensure safety, then broadcast via **PubSub** to all nodes in the cluster.
*   **Dynamic Registry:** Uses a local `Registry` to manage processes, preventing atom exhaustion and supporting high-cardinality multi-tenancy (e.g., 100,000s of isolated tenant instances).

## 📊 Benchmarks

Benchmarks performed on an Apple M1 Max (10 hops depth for transitive checks):

| Operation | IPS (Iterations Per Second) | Average Time |
| :--- | :--- | :--- |
| **Get Roles (Direct ETS)** | **5.42 M** | **0.18 μs** |
| **Has Link (Direct Hit)** | **4.67 M** | **0.21 μs** |
| **Has Link (Miss)** | **1.64 M** | **0.61 μs** |
| **Deep Transitive Check (10 Hops)** | **0.13 M** | **7.54 μs** |

## 🛠️ Usage

### Installation

Add `hawthorne_strainer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hawthorne_strainer, "~> 0.1.0"}
  ]
end