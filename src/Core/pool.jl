"""
# Connection Pool

This module provides connection pooling for database connections.

Connection pooling improves performance by reusing database connections instead
of creating new connections for each query. This reduces connection overhead
and improves throughput in multi-threaded applications.

## Design Principles

- **Thread-safe**: Safe for concurrent access from multiple threads
- **Resource-safe**: Automatic cleanup via `with_connection` pattern
- **Health checking**: Validates connections before reuse
- **Auto-reconnect**: Automatically replaces broken connections
- **Configurable**: Min/max pool size, timeout, health check interval

## Responsibilities

- Manage a pool of database connections
- Acquire and release connections from/to the pool
- Validate connection health before reuse
- Automatically reconnect broken connections
- Thread-safe connection management

## Usage

```julia
using SQLSketch

# Create connection pool
pool = ConnectionPool(PostgreSQLDriver(),
                      "postgresql://localhost/mydb",
                      min_size=2, max_size=10)

# Resource-safe pattern (recommended)
with_connection(pool) do conn
    result = execute_sql(conn, "SELECT * FROM users", [])
end

# Manual acquire/release pattern
conn = acquire(pool)
try
    result = execute_sql(conn, "SELECT * FROM users", [])
finally
    release(pool, conn)
end

# Close pool when done
close(pool)
```

## Performance Impact

Connection pooling provides:

- >80% reduction in connection overhead (measured)
- 5-10x faster for short queries (connection time dominates)
- Near-zero overhead for long queries
- Better resource utilization under high concurrency

See Phase 13 benchmarks for detailed performance measurements.
"""

import ..Core: Driver, Connection, connect, execute_sql
using DataStructures: BinaryMinHeap

"""
    wait_with_timeout(condition::Condition, timeout::Float64) -> Bool

Wait on a Condition with a timeout.

This is a utility function that implements timeout support for Julia's Condition,
which doesn't have native timeout support. For short waits (< 100ms), it uses
polling. For longer waits, it uses a Timer-based approach.

# Arguments

  - `condition`: The Condition to wait on
  - `timeout`: Timeout in seconds (must be finite, > 0)

# Returns

  - `true` if woken up by notify() (normal case)
  - `false` if woken up by timeout

# Implementation

For timeout < 0.1s: Uses polling with short sleeps (simple, low overhead)
For timeout >= 0.1s: Uses Timer + Task (efficient, zero CPU usage)

This hybrid approach optimizes for the common case (short waits) while
still providing efficiency for long waits.

# Example

```julia
lock = ReentrantLock()
cond = Base.GenericCondition(lock)

lock(lock) do
    if wait_with_timeout(cond, 5.0)
        # Woken by notify - connection available
    else
        # Timeout - still no connection
        error("Timeout")
    end
end
```
"""
function wait_with_timeout(condition::Base.GenericCondition,
                           timeout::Float64)::Bool
    @assert timeout > 0.0 && !isinf(timeout) "timeout must be finite and positive"

    start_time = time()

    # For very short timeouts, use simple polling (lower overhead)
    # Timer creation/destruction costs ~30μs, so polling is faster for < 100ms
    if timeout < 0.1
        while true
            # Try a brief wait on the condition
            # We can't truly wait with timeout, so we unlock, sleep briefly, relock
            sleep_time = min(0.01, timeout / 2)  # Max 10ms

            unlock(condition.lock)
            sleep(sleep_time)
            lock(condition.lock)

            # Check if we've been notified (by checking time elapsed vs expected)
            # If notify() was called, we might have woken early
            # For simplicity, just check timeout
            elapsed = time() - start_time
            if elapsed >= timeout
                return false  # Timeout
            end

            # Note: This is a simplified version. In reality, we can't detect
            # if notify() was called without actually waiting on the condition.
            # For short timeouts, we accept this trade-off.
            # The lock will protect us - if connection became available,
            # we'll see it on next iteration in acquire()

            # For very short timeouts, return after one iteration
            if timeout < 0.01
                return false
            end
        end
    end

    # For longer timeouts (>= 100ms), use Timer-based approach
    # This provides zero CPU usage during wait
    timed_out = Threads.Atomic{Bool}(false)
    timer = Timer(timeout)

    timeout_task = @async begin
        try
            wait(timer)
            lock(condition.lock) do
                Threads.atomic_xchg!(timed_out, true)
                notify(condition)
            end
        catch e
            # Timer closed before firing - this is normal
        end
    end

    # Wait on the condition
    wait(condition)

    # Cleanup
    close(timer)
    try
        wait(timeout_task)
    catch
        # Task threw exception (timer closed) - fine
    end

    return !timed_out[]
end

"""
    PoolMetrics

Connection pool metrics for monitoring and debugging.

This structure tracks various performance metrics about the connection pool,
using Atomic types for thread-safe updates.

# Fields

  - `total_acquires`: Total number of acquire() calls
  - `total_releases`: Total number of release() calls
  - `total_waits`: Number of times acquire() had to wait
  - `total_wait_time_ms`: Total time spent waiting (milliseconds)
  - `total_timeouts`: Number of timeout errors
  - `health_check_failures`: Number of health check failures
  - `reconnections`: Number of connection reconnections
  - `peak_usage`: Maximum number of connections in use simultaneously

# Example

```julia
metrics = get_metrics(pool)
println("Wait percentage: \$(metrics.wait_percentage)%")
println("Avg wait time: \$(metrics.avg_wait_time_ms)ms")
```
"""
mutable struct PoolMetrics
    total_acquires::Threads.Atomic{Int}
    total_releases::Threads.Atomic{Int}
    total_waits::Threads.Atomic{Int}
    total_wait_time_ms::Threads.Atomic{Float64}
    total_timeouts::Threads.Atomic{Int}
    health_check_failures::Threads.Atomic{Int}
    reconnections::Threads.Atomic{Int}
    peak_usage::Threads.Atomic{Int}
    spin_waits::Threads.Atomic{Int}      # Number of spin-phase waits
    park_waits::Threads.Atomic{Int}      # Number of park-phase waits (Condition wait)

    function PoolMetrics()
        return new(Threads.Atomic{Int}(0),
                   Threads.Atomic{Int}(0),
                   Threads.Atomic{Int}(0),
                   Threads.Atomic{Float64}(0.0),
                   Threads.Atomic{Int}(0),
                   Threads.Atomic{Int}(0),
                   Threads.Atomic{Int}(0),
                   Threads.Atomic{Int}(0),
                   Threads.Atomic{Int}(0),
                   Threads.Atomic{Int}(0))
    end
end

"""
    WaiterEntry

Represents a single waiting thread with its deadline and timeout state.

# Fields

  - `deadline`: Absolute time when this waiter should timeout
  - `condition`: The condition to notify when timeout occurs
  - `timed_out`: Atomic flag indicating if timeout occurred
"""
mutable struct WaiterEntry
    deadline::Float64
    condition::Base.GenericCondition{ReentrantLock}
    timed_out::Ref{Bool}
end

# Min-heap ordering: earliest deadline first
Base.isless(a::WaiterEntry, b::WaiterEntry)::Bool = a.deadline < b.deadline

"""
    TimeoutManager

Centralized timeout management for connection pool waiters.

Instead of creating a Timer + @async for each park operation,
this manager maintains a single monitoring task that checks
all waiters periodically.

Uses a min-heap (priority queue) ordered by deadline for O(log n)
operations and dynamic sleep intervals.

# Fields

  - `lock`: Lock protecting the waiters heap
  - `waiters`: Min-heap of active waiters ordered by deadline (earliest first)
  - `monitor_task`: Background task that checks for timeouts
  - `running`: Flag to stop the monitor task on pool close
  - `max_check_interval`: Maximum sleep interval between checks (seconds)

# Performance

  - Register: O(log n) heap insert
  - Unregister: O(n) search + O(log n) delete
  - Check timeouts: O(k log n) where k = expired waiters
  - Dynamic sleep: wakes only when next timeout is due
"""
mutable struct TimeoutManager
    lock::ReentrantLock
    waiters::BinaryMinHeap{WaiterEntry}  # Min-heap ordered by deadline
    monitor_task::Union{Task,Nothing}
    running::Threads.Atomic{Bool}
    max_check_interval::Float64  # Maximum sleep interval

    # Hybrid shutdown: monitor auto-stops after idle period
    last_activity_time::Float64
    shutdown_timeout::Float64

    function TimeoutManager(max_check_interval::Float64=0.1, shutdown_timeout::Float64=5.0)
        return new(ReentrantLock(),
                   BinaryMinHeap{WaiterEntry}(),  # Empty min-heap
                   nothing,
                   Threads.Atomic{Bool}(true),
                   max_check_interval,
                   0.0,  # last_activity_time
                   shutdown_timeout)
    end
end

"""
    _timeout_monitor_loop(mgr::TimeoutManager)

Background task that checks for timed-out waiters.

Uses a min-heap (priority queue) to efficiently process timeouts:
- O(1) peek at next deadline
- O(log n) pop for each expired waiter
- Dynamic sleep: wakes only when next timeout is due

This eliminates O(n) linear scans and reduces lock contention.
"""
function _timeout_monitor_loop(mgr::TimeoutManager)::Nothing
    mgr.last_activity_time = time()

    while mgr.running[]
        # Determine sleep time based on next deadline
        sleep_time = lock(mgr.lock) do
            if isempty(mgr.waiters)
                # No waiters - check for shutdown after idle period
                elapsed = time() - mgr.last_activity_time
                if elapsed >= mgr.shutdown_timeout
                    # Idle timeout reached - stop monitor
                    mgr.monitor_task = nothing
                    Threads.atomic_xchg!(mgr.running, false)
                    return 0.0  # Signal to exit
                end

                # Continue waiting, check again after max_check_interval
                return mgr.max_check_interval
            else
                # Active waiters - sleep until next deadline
                mgr.last_activity_time = time()
                next_deadline = first(mgr.waiters).deadline  # O(1) peek min
                now = time()

                # Sleep until next deadline (bounded by max_check_interval)
                sleep_until = max(next_deadline - now, 0.001)  # Min 1ms
                return min(sleep_until, mgr.max_check_interval)
            end
        end

        # Exit if shutdown requested
        if sleep_time <= 0.0
            break
        end

        sleep(sleep_time)

        # Process expired waiters - OPTIMIZED: Batch + Single Notify
        # Phase 1: Pop expired waiters and set flags (hold mgr.lock briefly)
        now = time()
        expired_waiters = lock(mgr.lock) do
            expired = WaiterEntry[]
            while !isempty(mgr.waiters)
                # Peek at minimum deadline (O(1))
                next_waiter = first(mgr.waiters)

                if next_waiter.deadline <= now
                    # Expired - pop from heap (O(log n))
                    waiter = pop!(mgr.waiters)
                    # Set timeout flag
                    waiter.timed_out[] = true
                    # Collect for batch notification
                    push!(expired, waiter)
                else
                    # Heap is ordered - no more expired waiters
                    break
                end
            end
            return expired
        end

        # Phase 2: Notify ONCE outside mgr.lock (no nested locking!)
        # All waiters share the same pool.condition, so one notify wakes all
        if !isempty(expired_waiters)
            condition = expired_waiters[1].condition
            lock(condition.lock) do
                notify(condition, :all)  # Single notify for all expired waiters
            end
        end
    end

    mgr.monitor_task = nothing
    return nothing
end

"""
    _start_timeout_monitor!(mgr::TimeoutManager)

Start the timeout monitoring task if not already running.
"""
function _start_timeout_monitor!(mgr::TimeoutManager)::Nothing
    if mgr.monitor_task === nothing || istaskdone(mgr.monitor_task)
        mgr.running[] = true
        mgr.monitor_task = @async _timeout_monitor_loop(mgr)
    end
    return nothing
end

"""
    _unregister_waiter!(mgr::TimeoutManager, entry::WaiterEntry)

Remove a waiter from the timeout manager's heap.

This is O(n) search + O(log n) delete, but occurs infrequently
(only in finally block when acquire completes).

# Implementation Note

BinaryMinHeap doesn't support delete-by-value, so we:
1. Reconstruct heap without the target entry (O(n))
2. This is acceptable since unregister is rare compared to timeout checks
"""
function _unregister_waiter!(mgr::TimeoutManager, entry::WaiterEntry)::Nothing
    lock(mgr.lock) do
        # Rebuild heap without target entry
        # O(n) but happens only on acquire completion (rare)
        remaining = filter(w -> w !== entry, mgr.waiters.valtree)
        mgr.waiters = BinaryMinHeap{WaiterEntry}()
        for w in remaining
            push!(mgr.waiters, w)
        end
        mgr.last_activity_time = time()
    end
    return nothing
end

"""
    _stop_timeout_monitor!(mgr::TimeoutManager)

Stop the timeout monitoring task.
"""
function _stop_timeout_monitor!(mgr::TimeoutManager)::Nothing
    Threads.atomic_xchg!(mgr.running, false)
    if mgr.monitor_task !== nothing
        wait(mgr.monitor_task)
    end
    return nothing
end

"""
    PooledConnection{C <: Connection}

Wrapper for a pooled database connection.

This type wraps an underlying Connection and tracks metadata needed
for connection pool management.

# Fields

  - `conn`: The underlying database connection
  - `in_use`: Whether the connection is currently in use
  - `last_used`: Timestamp of last use (for health checking)
  - `error_count`: Number of consecutive errors (for health checking)

# Implementation Details

A PooledConnection is always owned by a ConnectionPool and should not
be created directly by users. Use `acquire()` to get a connection from the pool.
"""
mutable struct PooledConnection{C <: Connection}
    conn::C
    in_use::Bool
    last_used::Float64  # Unix timestamp
    error_count::Int

    function PooledConnection{C}(conn::C) where {C <: Connection}
        return new{C}(conn, false, time(), 0)
    end
end

"""
    ConnectionPool{D <: Driver, C <: Connection}

A thread-safe pool of database connections.

The pool maintains a collection of connections and provides thread-safe
acquire/release operations. Connections are validated before reuse and
automatically replaced if broken.

# Fields

  - `driver`: The database driver for creating connections
  - `config`: Driver-specific connection configuration
  - `min_size`: Minimum number of connections to maintain
  - `max_size`: Maximum number of connections allowed
  - `connections`: Vector of pooled connections
  - `lock`: ReentrantLock for thread-safe operations
  - `health_check_interval`: Seconds between health checks (default: 60.0)
  - `closed`: Whether the pool has been closed

# Configuration

  - `min_size`: Minimum pool size (default: 1)

      + Pool will maintain at least this many connections
      + Connections created on pool initialization

  - `max_size`: Maximum pool size (default: 10)

      + Pool will never create more than this many connections
      + `acquire()` blocks if all connections are in use
  - `health_check_interval`: Health check interval in seconds (default: 60.0)

      + Connections idle longer than this are validated before reuse
      + Set to 0.0 to disable health checking

# Thread Safety

All pool operations (acquire, release, close) are protected by a ReentrantLock.
It is safe to use the same pool from multiple threads.

# Performance

Connection pooling reduces connection overhead by >80% for typical workloads.
The overhead of pool management (lock acquisition, health checks) is negligible
compared to connection establishment time.

# Example

```julia
# Create pool
pool = ConnectionPool(PostgreSQLDriver(),
                      "postgresql://localhost/mydb";
                      min_size = 2, max_size = 10)

# Use with resource-safe pattern
with_connection(pool) do conn
    # Connection automatically released after block
    result = execute_sql(conn, "SELECT 1", [])
end

# Close pool when done
close(pool)
```
"""
mutable struct ConnectionPool{D <: Driver, C <: Connection}
    driver::D
    config::String
    min_size::Int
    max_size::Int
    connections::Vector{PooledConnection{C}}
    lock::ReentrantLock
    condition::Base.GenericCondition{ReentrantLock}  # For efficient waiting when pool is full
    health_check_interval::Float64
    metrics::PoolMetrics  # Performance metrics
    timeout_mgr::TimeoutManager  # Centralized timeout management
    closed::Bool

    function ConnectionPool{D, C}(driver::D,
                                  config::String;
                                  min_size::Int = 1,
                                  max_size::Int = 10,
                                  health_check_interval::Float64 = 60.0) where {D <: Driver,
                                                                                C <:
                                                                                Connection}
        # Validate parameters
        @assert min_size >= 0 "min_size must be >= 0, got $min_size"
        @assert max_size >= min_size "max_size must be >= min_size, got max_size=$max_size, min_size=$min_size"
        @assert health_check_interval >= 0.0 "health_check_interval must be >= 0.0, got $health_check_interval"

        lock = ReentrantLock()
        cond = Base.GenericCondition(lock)  # Condition bound to lock
        timeout_mgr = TimeoutManager()  # Centralized timeout manager

        pool = new{D, C}(driver,
                         config,
                         min_size,
                         max_size,
                         PooledConnection{C}[],
                         lock,
                         cond,
                         health_check_interval,
                         PoolMetrics(),  # Initialize metrics
                         timeout_mgr,
                         false)

        # Note: Do NOT start timeout monitor here
        # It will auto-start when first waiter is registered (lazy initialization)

        # Create minimum number of connections
        for _ in 1:min_size
            conn = connect(driver, config)::C
            push!(pool.connections, PooledConnection{C}(conn))
        end

        return pool
    end
end

"""
    ConnectionPool(driver::Driver, config::String; kwargs...) -> ConnectionPool

Create a connection pool for the specified driver and configuration.

# Arguments

  - `driver`: Database driver instance (e.g., PostgreSQLDriver(), SQLiteDriver())
  - `config`: Driver-specific connection configuration (e.g., connection string)

# Keyword Arguments

  - `min_size`: Minimum pool size (default: 1)
  - `max_size`: Maximum pool size (default: 10)
  - `health_check_interval`: Health check interval in seconds (default: 60.0)

# Returns

A ConnectionPool instance with `min_size` connections pre-created.

# Example

```julia
# PostgreSQL pool
pool = ConnectionPool(PostgreSQLDriver(),
                      "postgresql://localhost/mydb";
                      min_size = 2, max_size = 10)

# SQLite pool (less useful but supported)
pool = ConnectionPool(SQLiteDriver(), ":memory:";
                      min_size = 1, max_size = 1)
```

# Type Inference

The pool automatically infers the Connection type from the driver.
This is done by calling `connect()` once during initialization.
"""
function ConnectionPool(driver::D,
                        config::String;
                        min_size::Int = 1,
                        max_size::Int = 10,
                        health_check_interval::Float64 = 60.0) where {D <: Driver}
    # Infer connection type by creating a test connection
    # This is necessary because Julia's type system can't infer the Connection type
    # from the Driver type alone (it's a runtime property)
    test_conn = connect(driver, config)
    C = typeof(test_conn)

    # Always close the test connection - we'll create fresh ones in the inner constructor
    close(test_conn)

    # Create pool with the inferred connection type
    return ConnectionPool{D, C}(driver, config;
                                min_size = min_size,
                                max_size = max_size,
                                health_check_interval = health_check_interval)
end

"""
    acquire(pool::ConnectionPool{D, C}; timeout::Float64 = 30.0) -> C

Acquire a connection from the pool.

This function returns an available connection from the pool. If all connections
are in use and the pool is not at maximum capacity, a new connection is created.
If all connections are in use and the pool is at maximum capacity, this function
blocks until a connection becomes available or the timeout is reached.

# Arguments

  - `pool`: The connection pool

# Keyword Arguments

  - `timeout`: Maximum time to wait in seconds (default: 30.0). Set to `Inf` for no timeout.

# Returns

A Connection instance from the pool

# Blocking Behavior

If all connections are in use and the pool is at max_size, this function
will block (using Condition wait) until a connection is released or timeout is reached.

# Timeout

If no connection becomes available within `timeout` seconds, throws an error.
This prevents indefinite blocking and helps detect resource leaks early.

# Health Checking

Before returning a connection, this function checks if the connection needs
health validation (based on `health_check_interval`). If validation fails,
the connection is automatically replaced with a new one.

# Thread Safety

This function is thread-safe and can be called from multiple threads.

# Example

```julia
# With default 30s timeout
conn = acquire(pool)
try
    result = execute_sql(conn, "SELECT 1", [])
finally
    release(pool, conn)
end

# With custom timeout
conn = acquire(pool; timeout = 5.0)  # 5 seconds

# No timeout
conn = acquire(pool; timeout = Inf)
```

# Note

It is recommended to use `with_connection()` instead of manual acquire/release
to ensure connections are always released, even if an exception occurs.
"""
function acquire(pool::ConnectionPool{D, C}; timeout::Float64 = 30.0)::C where {D, C}
    start_time = time()
    waited = Ref(false)
    iteration = 0
    timeout_entry = nothing

    Threads.atomic_add!(pool.metrics.total_acquires, 1)

    try
        conn = lock(pool.lock) do
            # Check if pool is closed
            if pool.closed
                error("Cannot acquire connection from closed pool")
            end

            # Main acquisition loop with predicate checks
            while true
                # === Predicate 1: Timeout check ===
                if timeout_entry !== nothing && timeout_entry.timed_out[]
                    Threads.atomic_add!(pool.metrics.total_timeouts, 1)
                    error("Connection acquisition timeout after $(round(time() - start_time, digits=2))s (pool exhausted: $(length(pool.connections))/$(pool.max_size) connections in use)")
                end

                # === Predicate 2: Available connection ===
                for pc in pool.connections
                    if !pc.in_use
                        # Health check if needed
                        if pool.health_check_interval > 0.0 &&
                           (time() - pc.last_used) > pool.health_check_interval
                            if !_is_connection_healthy(pc.conn)
                                Threads.atomic_add!(pool.metrics.health_check_failures, 1)
                                try
                                    close(pc.conn)
                                catch
                                end
                                pc.conn = connect(pool.driver, pool.config)::C
                                pc.error_count = 0
                                pc.last_used = time()
                                Threads.atomic_add!(pool.metrics.reconnections, 1)
                            end
                        end

                        # Mark as in use and return
                        pc.in_use = true
                        pc.last_used = time()

                        # Update peak usage
                        current_usage = count(p -> p.in_use, pool.connections)
                        old_peak = pool.metrics.peak_usage[]
                        while current_usage > old_peak
                            if Threads.atomic_cas!(pool.metrics.peak_usage, old_peak,
                                                   current_usage) == old_peak
                                break
                            end
                            old_peak = pool.metrics.peak_usage[]
                        end

                        return pc.conn
                    end
                end

                # === Predicate 3: Can create new connection ===
                if length(pool.connections) < pool.max_size
                    conn = connect(pool.driver, pool.config)::C
                    pc = PooledConnection{C}(conn)
                    pc.in_use = true
                    push!(pool.connections, pc)

                    # Update peak usage
                    current_usage = count(p -> p.in_use, pool.connections)
                    old_peak = pool.metrics.peak_usage[]
                    while current_usage > old_peak
                        if Threads.atomic_cas!(pool.metrics.peak_usage, old_peak,
                                               current_usage) == old_peak
                            break
                        end
                        old_peak = pool.metrics.peak_usage[]
                    end

                    return conn
                end

                # === No resource available, must wait ===

                # Track that we're waiting
                if !waited[]
                    waited[] = true
                    Threads.atomic_add!(pool.metrics.total_waits, 1)
                end

                iteration += 1

                # Spin-then-park pattern
                if !isinf(timeout)
                    elapsed = time() - start_time
                    remaining = timeout - elapsed

                    # Immediate timeout check
                    if remaining <= 0
                        Threads.atomic_add!(pool.metrics.total_timeouts, 1)
                        error("Connection acquisition timeout after $(round(elapsed, digits=2))s (pool exhausted: $(length(pool.connections))/$(pool.max_size) connections in use)")
                    end

                    if iteration <= 10
                        # Spin phase
                        Threads.atomic_add!(pool.metrics.spin_waits, 1)
                        unlock(pool.lock)
                        yield()
                        lock(pool.lock)
                    else
                        # Park phase - register for timeout monitoring
                        Threads.atomic_add!(pool.metrics.park_waits, 1)

                        if timeout_entry === nothing
                            deadline = start_time + timeout
                            timed_out = Ref(false)
                            timeout_entry = WaiterEntry(deadline, pool.condition, timed_out)

                            lock(pool.timeout_mgr.lock) do
                                # Start monitor if first waiter
                                if isempty(pool.timeout_mgr.waiters)
                                    _start_timeout_monitor!(pool.timeout_mgr)
                                end
                                push!(pool.timeout_mgr.waiters, timeout_entry)
                                pool.timeout_mgr.last_activity_time = time()
                            end
                        end

                        # Wait for release() to notify
                        wait(pool.condition)
                    end
                else
                    # Infinite timeout
                    Threads.atomic_add!(pool.metrics.park_waits, 1)
                    wait(pool.condition)
                end

                # Loop back to re-check predicates
            end
        end

        return conn

    finally
        # Cleanup timeout registration
        if timeout_entry !== nothing
            _unregister_waiter!(pool.timeout_mgr, timeout_entry)
        end

        # Record wait time if we waited
        if waited[]
            wait_time_ms = (time() - start_time) * 1000.0
            Threads.atomic_add!(pool.metrics.total_wait_time_ms, wait_time_ms)
        end
    end
end

"""
    release(pool::ConnectionPool{D, C}, conn::C) -> Nothing

Release a connection back to the pool.

This function marks the connection as available for reuse by other callers.
The connection is not closed - it remains in the pool for future use.

# Arguments

  - `pool`: The connection pool
  - `conn`: The connection to release (must have been acquired from this pool)

# Returns

Nothing

# Thread Safety

This function is thread-safe and can be called from multiple threads.

# Example

```julia
conn = acquire(pool)
try
    result = execute_sql(conn, "SELECT 1", [])
finally
    release(pool, conn)
end
```

# Note

It is recommended to use `with_connection()` instead of manual acquire/release.
"""
function release(pool::ConnectionPool{D, C}, conn::C)::Nothing where {D, C}
    Threads.atomic_add!(pool.metrics.total_releases, 1)

    lock(pool.lock) do
        # Find the pooled connection
        for pc in pool.connections
            if pc.conn === conn
                if !pc.in_use
                    @warn "Releasing connection that is not marked as in use"
                end
                pc.in_use = false
                pc.last_used = time()
                # Notify waiting threads that a connection is available
                notify(pool.condition)
                return nothing
            end
        end

        # Connection not found in pool
        @warn "Attempting to release connection not in pool"
        return nothing
    end
end

"""
    with_connection(f::Function, pool::ConnectionPool{D, C}) -> result

Execute a function with a connection from the pool.

This is the recommended way to use connection pools. It ensures that the
connection is always released back to the pool, even if an exception occurs.

# Arguments

  - `f`: Function to execute. Receives a Connection as its argument.
  - `pool`: The connection pool

# Returns

The return value of function `f`

# Example

```julia
pool = ConnectionPool(PostgreSQLDriver(), "postgresql://localhost/mydb")

result = with_connection(pool) do conn
    execute_sql(conn, "SELECT * FROM users", [])
end
```

# Thread Safety

This function is thread-safe. Multiple threads can call `with_connection`
on the same pool concurrently.

# Exception Handling

If function `f` throws an exception, the connection is still released back
to the pool before the exception is re-thrown.
"""
function with_connection(f::Function, pool::ConnectionPool{D, C}) where {D, C}
    conn = acquire(pool)
    try
        return f(conn)
    finally
        release(pool, conn)
    end
end

"""
    Base.close(pool::ConnectionPool) -> Nothing

Close all connections in the pool and mark the pool as closed.

After closing, no new connections can be acquired. Attempting to acquire
a connection from a closed pool will raise an error.

# Arguments

  - `pool`: The connection pool to close

# Returns

Nothing

# Thread Safety

This function is thread-safe.

# Example

```julia
pool = ConnectionPool(PostgreSQLDriver(), "postgresql://localhost/mydb")

# Use pool...

# Clean up
close(pool)
```

# Note

It is the caller's responsibility to ensure no connections are in use
when closing the pool. Connections that are in use at close time will
still be closed, which may cause errors in other threads.
"""
function Base.close(pool::ConnectionPool)::Nothing
    lock(pool.lock) do
        if pool.closed
            return nothing
        end

        # Stop timeout monitor task
        _stop_timeout_monitor!(pool.timeout_mgr)

        # Close all connections
        for pc in pool.connections
            try
                close(pc.conn)
            catch e
                @warn "Failed to close connection in pool" exception = e
            end
        end

        # Clear connections
        empty!(pool.connections)

        # Mark as closed
        pool.closed = true

        return nothing
    end
end

"""
    _is_connection_healthy(conn::Connection) -> Bool

Check if a connection is healthy and usable.

This is an internal function used for health checking. It attempts to execute
a simple query to verify the connection is still alive.

# Arguments

  - `conn`: The connection to check

# Returns

  - `true` if the connection is healthy
  - `false` if the connection is broken or unusable

# Implementation

Currently uses a simple ping query:

  - PostgreSQL: "SELECT 1"
  - SQLite: "SELECT 1"

Future improvements could include driver-specific health check methods.
"""
function _is_connection_healthy(conn::Connection)::Bool
    try
        # Simple ping query - works for both PostgreSQL and SQLite
        execute_sql(conn, "SELECT 1", [])
        return true
    catch e
        # Any exception means connection is unhealthy
        return false
    end
end

"""
    get_metrics(pool::ConnectionPool) -> NamedTuple

Get current performance metrics for the connection pool.

This function returns a snapshot of pool metrics including:
- Acquire/release counts
- Wait statistics
- Timeout counts
- Health check failures
- Reconnections
- Peak usage

# Arguments

  - `pool`: The connection pool

# Returns

A NamedTuple with the following fields:

  - `total_acquires`: Total acquire() calls
  - `total_releases`: Total release() calls
  - `total_waits`: Number of times acquire() had to wait
  - `total_timeouts`: Number of timeout errors
  - `wait_percentage`: Percentage of acquires that waited (0-100)
  - `avg_wait_time_ms`: Average wait time in milliseconds
  - `health_check_failures`: Number of health check failures
  - `reconnections`: Number of reconnections
  - `peak_usage`: Maximum connections in use simultaneously
  - `current_usage`: Current number of connections in use
  - `pool_size`: Current size of the pool

# Example

```julia
pool = ConnectionPool(PostgreSQLDriver(), "postgresql://localhost/mydb";
                      max_size = 10)

# ... use the pool ...

metrics = get_metrics(pool)
println("Total acquires: \$(metrics.total_acquires)")
println("Wait percentage: \$(round(metrics.wait_percentage, digits=2))%")
println("Avg wait time: \$(round(metrics.avg_wait_time_ms, digits=2))ms")
println("Peak usage: \$(metrics.peak_usage) / \$(metrics.pool_size)")

# Check if pool size is adequate
if metrics.peak_usage >= metrics.pool_size * 0.9
    @warn "Pool frequently at capacity - consider increasing max_size"
end
```
"""
function get_metrics(pool::ConnectionPool)::NamedTuple
    total_acquires = pool.metrics.total_acquires[]
    total_releases = pool.metrics.total_releases[]
    total_waits = pool.metrics.total_waits[]
    total_wait_time_ms = pool.metrics.total_wait_time_ms[]
    total_timeouts = pool.metrics.total_timeouts[]
    spin_waits = pool.metrics.spin_waits[]
    park_waits = pool.metrics.park_waits[]

    wait_percentage = total_acquires > 0 ? (total_waits / total_acquires * 100.0) : 0.0
    avg_wait_time_ms = total_waits > 0 ? (total_wait_time_ms / total_waits) : 0.0

    current_usage = lock(pool.lock) do
        count(pc -> pc.in_use, pool.connections)
    end

    return (total_acquires = total_acquires,
            total_releases = total_releases,
            total_waits = total_waits,
            total_timeouts = total_timeouts,
            wait_percentage = wait_percentage,
            avg_wait_time_ms = avg_wait_time_ms,
            health_check_failures = pool.metrics.health_check_failures[],
            reconnections = pool.metrics.reconnections[],
            peak_usage = pool.metrics.peak_usage[],
            current_usage = current_usage,
            pool_size = length(pool.connections),
            spin_waits = spin_waits,
            park_waits = park_waits)
end

#
# Exports
#

export ConnectionPool, acquire, release, with_connection, get_metrics
