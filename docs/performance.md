# Performance Optimization Guide

This guide covers performance optimization techniques and tools in SQLSketch.jl.

## Table of Contents

1. [Performance Features](#performance-features)
2. [Query Profiling](#query-profiling)
3. [Query Plan Analysis](#query-plan-analysis)
4. [Caching Strategies](#caching-strategies)
5. [Connection Pooling](#connection-pooling)
6. [Batch Operations](#batch-operations)
7. [Best Practices](#best-practices)

---

## Performance Features

SQLSketch.jl provides several performance optimization features:

| Feature | Speedup | Use Case |
|---------|---------|----------|
| **Prepared Statement Cache** | 10-20% | Repeated queries with different parameters |
| **Query Plan Cache** | **4.85-6.95x** | Repeated query compilation |
| **Connection Pooling** | 4-5x | Concurrent workloads |
| **Batch INSERT (PostgreSQL COPY)** | 4-2016x | Bulk data insertion |
| **Batch INSERT (Multi-row)** | 1.35-299x | Bulk data insertion (all DBs) |

---

## Query Profiling

### Using `@timed_query` Macro

The `@timed_query` macro provides detailed timing breakdown for query execution:

```julia
using SQLSketch

# Execute query with timing
result, timing = @timed_query fetch_all(conn, dialect, registry, query)

println("Total time: $(timing.total_time * 1000)ms")
println("Execute time: $(timing.execute_time * 1000)ms")
println("Rows: $(timing.row_count)")
```

### QueryTiming Structure

```julia
struct QueryTiming
    compile_time::Float64   # Time spent compiling SQL (seconds)
    execute_time::Float64   # Time spent executing SQL (seconds)
    decode_time::Float64    # Time spent decoding results (seconds)
    total_time::Float64     # Total execution time (seconds)
    row_count::Int          # Number of rows returned
end
```

### Example: Profiling Different Queries

```julia
# Simple query
q1 = from(:users) |> where(col(:users, :active) == literal(true))
result1, timing1 = @timed_query fetch_all(conn, dialect, registry, q1)
println("Simple query: $(timing1.total_time * 1000)ms")

# Complex query with join
q2 = from(:users) |>
     left_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
     where(col(:posts, :published) == literal(true)) |>
     select(NamedTuple, col(:users, :name), col(:posts, :title))

result2, timing2 = @timed_query fetch_all(conn, dialect, registry, q2)
println("Complex query: $(timing2.total_time * 1000)ms")
```

---

## Query Plan Analysis

### Using `analyze_query`

Analyze query execution plans to identify performance bottlenecks:

```julia
query = from(:users) |> where(col(:users, :email) == param(String, :email))

analysis = analyze_query(conn, dialect, query)

println(analysis.plan)
# → SEARCH TABLE users USING INDEX idx_users_email (email=?)

if analysis.uses_index
    println("✓ Query uses index")
else
    println("⚠️  Query does not use index")
end

if analysis.has_full_scan
    println("⚠️  Query performs full table scan")
end

for warning in analysis.warnings
    println("⚠️  $warning")
end
```

### Example: Index Usage Detection

```julia
# Without index - full table scan
execute_sql(conn, "CREATE TABLE products (id INTEGER PRIMARY KEY, price REAL)")

query = from(:products) |> where(col(:products, :price) > literal(100.0))
analysis = analyze_query(conn, dialect, query)

if analysis.has_full_scan
    println("Creating index to improve performance...")
    execute_sql(conn, "CREATE INDEX idx_products_price ON products(price)")
end

# With index - index scan
analysis = analyze_query(conn, dialect, query)
println(analysis.uses_index)  # → true
```

### Using `analyze_explain`

Parse raw EXPLAIN output:

```julia
explain_output = """
SEARCH TABLE users USING INDEX idx_users_email (email=?)
"""

info = analyze_explain(explain_output)

println("Uses index: $(info[:uses_index])")      # → true
println("Scan type: $(info[:scan_type])")        # → :index_scan
println("Has full scan: $(info[:has_full_scan])") # → false
println("Warnings: $(info[:warnings])")          # → []
```

---

## Caching Strategies

### Prepared Statement Cache

**Automatic caching** of prepared statements for repeated queries.

```julia
# Prepared statements are cached automatically in drivers
# No user action required

# First execution - cache miss
execute(conn, dialect, query, (email="user@example.com",))

# Second execution - cache hit (10-20% faster)
execute(conn, dialect, query, (email="another@example.com",))
```

**Benefits:**
- 10-20% speedup for repeated queries
- Automatic LRU eviction
- Thread-safe

### Query Plan Cache

**Internal caching** of compiled SQL based on query AST structure.

```julia
using SQLSketch.Core.QueryPlanCache

cache = QueryPlanCache(max_size=200)

# First compilation - cache miss
sql1, params1 = compile_with_cache(cache, dialect, query)

# Second compilation - cache hit (50-80% faster)
sql2, params2 = compile_with_cache(cache, dialect, query)

# Check cache statistics
stats = cache_stats(cache)
println("Hit rate: $(stats.hit_rate * 100)%")
println("Cache size: $(stats.size)/$(stats.max_size)")
```

**Benefits:**
- **4.85-6.95x speedup** for repeated compilation (verified by benchmarks)
- AST-based cache keys
- LRU eviction policy
- Thread-safe
- 99.9% cache hit rate after warm-up

**Benchmark Results:**

| Query Type | Speedup (1000 iterations) | Cache Hit Rate |
|------------|---------------------------|----------------|
| Simple Query | 4.85x | 99.9% |
| Complex JOIN | 6.25x | 99.9% |
| Multiple Filters | 6.89x | 99.9% |
| Window Functions | 6.95x | 99.9% |
| Set Operations | 5.79x | 99.9% |

*Results measured on 1000 repeated compilations of the same query structure.*

---

## Connection Pooling

### Creating a Connection Pool

```julia
using SQLSketch

pool = ConnectionPool(
    driver=PostgreSQLDriver(),
    config="host=localhost port=5432 dbname=myapp",
    min_connections=2,
    max_connections=10
)

# Acquire connection from pool
conn = acquire(pool)
try
    result = fetch_all(conn, dialect, registry, query)
finally
    release(pool, conn)
end
```

### Using `with_connection`

Automatic acquire/release pattern:

```julia
result = with_connection(pool) do conn
    fetch_all(conn, dialect, registry, query)
end
```

### Concurrent Workloads

```julia
using Base.Threads

pool = ConnectionPool(
    driver=PostgreSQLDriver(),
    config="host=localhost port=5432 dbname=myapp",
    max_connections=10
)

# Concurrent queries
@threads for i in 1:100
    with_connection(pool) do conn
        execute(conn, dialect, query, (id=i,))
    end
end

# Check pool statistics
stats = pool_stats(pool)
println("Active: $(stats.active_connections)")
println("Idle: $(stats.idle_connections)")
```

**Benefits:**
- 4-5x speedup for concurrent workloads
- Automatic connection reuse
- Health checks and reconnection
- Thread-safe

---

## Batch Operations

### Batch INSERT

**PostgreSQL COPY (fastest):**

```julia
using SQLSketch

data = [
    (name="User $i", email="user$i@example.com", age=20+i)
    for i in 1:10000
]

# PostgreSQL COPY - 4-2016x faster
insert_batch(conn, :users, [:name, :email, :age], data)
```

**Multi-row INSERT (all databases):**

```julia
# Multi-row INSERT - 1.35-299x faster
insert_batch(conn, :users, [:name, :email, :age], data)
```

### Performance Comparison

| Method | 10 rows | 1,000 rows | 10,000 rows |
|--------|---------|------------|-------------|
| **Loop INSERT** | 3.2ms | 310ms | 3100ms |
| **Multi-row INSERT** | 2.3ms | 25ms | 230ms |
| **PostgreSQL COPY** | 1.1ms | 2.5ms | 1.5ms |

### Transaction-Wrapped Batches

```julia
transaction(conn) do tx
    insert_batch(tx, :users, [:name, :email], batch1)
    insert_batch(tx, :users, [:name, :email], batch2)
end
```

---

## Best Practices

### 1. Use Indexes for Filter Columns

**❌ Bad:**
```julia
# No index on email column
query = from(:users) |> where(col(:users, :email) == param(String, :email))
# → Full table scan
```

**✅ Good:**
```julia
# Create index
execute_sql(conn, "CREATE INDEX idx_users_email ON users(email)")

# Now query uses index
query = from(:users) |> where(col(:users, :email) == param(String, :email))
# → Index scan (much faster)
```

### 2. Use Connection Pooling for Concurrent Workloads

**❌ Bad:**
```julia
# Creating new connection for each request
@threads for i in 1:100
    conn = connect(driver, config)
    execute(conn, dialect, query)
    close(conn)
end
```

**✅ Good:**
```julia
# Reuse connections from pool
pool = ConnectionPool(driver=driver, config=config, max_connections=10)

@threads for i in 1:100
    with_connection(pool) do conn
        execute(conn, dialect, query)
    end
end
```

### 3. Use Batch Operations for Bulk Inserts

**❌ Bad:**
```julia
# Loop INSERT
for row in data
    execute(conn, dialect, insert_query, row)
end
```

**✅ Good:**
```julia
# Batch INSERT (up to 2000x faster)
insert_batch(conn, :users, [:name, :email], data)
```

### 4. Profile Slow Queries

**Identify bottlenecks:**

```julia
query = complex_query()

# Profile query
result, timing = @timed_query fetch_all(conn, dialect, registry, query)

if timing.total_time > 1.0  # > 1 second
    println("Slow query detected!")

    # Analyze execution plan
    analysis = analyze_query(conn, dialect, query)
    println(analysis.plan)

    for warning in analysis.warnings
        println("⚠️  $warning")
    end
end
```

### 5. Use Parameterized Queries

**❌ Bad:**
```julia
# String interpolation - no prepared statement reuse
for email in emails
    q = from(:users) |> where(col(:users, :email) == literal(email))
    execute(conn, dialect, q)
end
```

**✅ Good:**
```julia
# Parameterized query - prepared statement reused
q = from(:users) |> where(col(:users, :email) == param(String, :email))

for email in emails
    execute(conn, dialect, q, (email=email,))
end
```

### 6. Limit Result Sets

**❌ Bad:**
```julia
# Fetch all rows (could be millions)
query = from(:users)
result = fetch_all(conn, dialect, registry, query)
```

**✅ Good:**
```julia
# Limit results
query = from(:users) |> limit(100)
result = fetch_all(conn, dialect, registry, query)
```

### 7. Select Only Needed Columns

**❌ Bad:**
```julia
# SELECT * (fetches all columns)
query = from(:users)
```

**✅ Good:**
```julia
# SELECT specific columns
query = from(:users) |> select(NamedTuple, col(:users, :id), col(:users, :name))
```

---

## Performance Checklist

Before deploying to production, verify:

- [ ] **Indexes created** for all filter columns
- [ ] **Connection pooling** enabled for web applications
- [ ] **Batch operations** used for bulk inserts
- [ ] **Prepared statement cache** enabled (automatic)
- [ ] **Query profiling** performed for slow queries
- [ ] **EXPLAIN analysis** performed for complex queries
- [ ] **Result sets limited** to reasonable sizes
- [ ] **Only needed columns selected** in queries
- [ ] **Parameterized queries** used instead of literals

---

## Troubleshooting

### Slow Query Performance

1. **Profile the query:**
   ```julia
   result, timing = @timed_query fetch_all(conn, dialect, registry, query)
   println("Time: $(timing.total_time * 1000)ms")
   ```

2. **Analyze execution plan:**
   ```julia
   analysis = analyze_query(conn, dialect, query)
   println(analysis.plan)
   ```

3. **Check for warnings:**
   ```julia
   for warning in analysis.warnings
       println("⚠️  $warning")
   end
   ```

4. **Add indexes if needed:**
   ```julia
   execute_sql(conn, "CREATE INDEX idx_table_column ON table(column)")
   ```

### High Memory Usage

- Use `limit()` to restrict result set size
- Consider streaming results (future feature)
- Select only needed columns with `select()`

### Connection Exhaustion

- Increase `max_connections` in connection pool
- Check for connection leaks (always `release()` or use `with_connection()`)
- Monitor pool statistics with `pool_stats()`

---

## Benchmarking

See `benchmark/RESULTS.md` for detailed performance benchmarks and comparisons.

**Key Results:**
- Prepared statement cache: 10-20% speedup
- **Query plan cache: 4.85-6.95x speedup** (verified)
- Connection pooling: 4-5x speedup (concurrent workloads)
- Batch INSERT (PostgreSQL COPY): 4-2016x speedup
- Batch INSERT (Multi-row): 1.35-299x speedup

Run benchmarks yourself:
```bash
julia --project=. benchmark/query_plan_cache_benchmark.jl
```

---

## Next Steps

- Review [API Reference](api.md) for detailed API documentation
- See [Tutorial](tutorial.md) for usage examples
- Check [Benchmark Results](../benchmark/RESULTS.md) for performance data

---

**Last Updated:** 2025-12-21
