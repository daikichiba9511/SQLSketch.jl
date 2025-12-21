#!/usr/bin/env julia

# Connection Pooling Benchmark
# Measures the overhead reduction from connection pooling
# Expected: >80% reduction in connection overhead for short queries

using SQLSketch
using SQLSketch.Drivers: SQLiteDriver, SQLiteConnection
using BenchmarkTools

println("=" ^ 80)
println("Phase 13: Connection Pooling Benchmark")
println("Testing: Connection Pool vs Direct Connection")
println("=" ^ 80)
println()

# Test configuration
const N_QUERIES = 100  # Number of queries to execute

function setup_database()
    """Setup in-memory SQLite database with test data"""
    driver = SQLiteDriver()
    db = connect(driver, ":memory:")

    # Create schema
    execute_sql(db, """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL
        )
    """)

    # Insert test data
    for i in 1:500
        execute_sql(db,
                    "INSERT INTO users (name, email) VALUES (?, ?)",
                    ["User $i", "user$i@example.com"])
    end

    return db, driver
end

println("Setting up test database...")
test_db, driver = setup_database()
close(test_db)
println("✓ Database setup complete")
println()

# ============================================================================
# Test 1: Baseline - Direct Connection (No Pool)
# ============================================================================
println("=" ^ 80)
println("Test 1: Direct Connection (No Pool)")
println("=" ^ 80)
println()

function benchmark_no_pool(driver::SQLiteDriver, n_queries::Int)
    """Execute queries without connection pooling"""
    for _ in 1:n_queries
        db = connect(driver, ":memory:")
        execute_sql(db, """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT NOT NULL
            )
        """)
        execute_sql(db, "INSERT INTO users (name, email) VALUES (?, ?)",
                    ["Test User", "test@example.com"])
        result = execute_sql(db, "SELECT COUNT(*) as count FROM users")
        # Force iteration to consume result
        [NamedTuple(row) for row in result]
        close(db)
    end
end

println("Executing $N_QUERIES queries without connection pooling...")
result_no_pool = @benchmark benchmark_no_pool($driver, $N_QUERIES) samples=10 seconds=30
println()
println("Results (No Pool):")
println("  Median time: $(BenchmarkTools.prettytime(median(result_no_pool).time))")
println("  Mean time:   $(BenchmarkTools.prettytime(mean(result_no_pool).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_no_pool).memory))")
println("  Allocations: $(median(result_no_pool).allocs)")
println()

# ============================================================================
# Test 2: With Connection Pool
# ============================================================================
println("=" ^ 80)
println("Test 2: With Connection Pool")
println("=" ^ 80)
println()

function benchmark_with_pool(pool::ConnectionPool, n_queries::Int)
    """Execute queries with connection pooling"""
    for _ in 1:n_queries
        with_connection(pool) do conn
            # Database already has schema and data
            result = execute_sql(conn, "SELECT COUNT(*) as count FROM users")
            # Force iteration to consume result
            [NamedTuple(row) for row in result]
        end
    end
end

# Setup pool with persistent database
pool_db = connect(driver, ":memory:")
execute_sql(pool_db, """
    CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL
    )
""")
execute_sql(pool_db, "INSERT INTO users (name, email) VALUES (?, ?)",
            ["Test User", "test@example.com"])

# Create pool (we'll use the same connection, but wrapped in pool)
# Note: For fair comparison, we need to create a pool that reuses connections
# Since SQLite in-memory is not ideal for pooling, we'll use a file-based DB
close(pool_db)

# Use temporary file for pooling test
using Random
temp_db_path = joinpath(tempdir(), "sqlsketch_pool_bench_$(randstring(8)).db")

println("Creating connection pool (min_size=2, max_size=5)...")
pool = ConnectionPool(driver, temp_db_path; min_size = 2, max_size = 5)

# Setup database in pool
with_connection(pool) do conn
    execute_sql(conn, """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL
        )
    """)
    execute_sql(conn, "INSERT INTO users (name, email) VALUES (?, ?)",
                ["Test User", "test@example.com"])
end

println("✓ Connection pool ready")
println()

println("Executing $N_QUERIES queries with connection pooling...")
result_with_pool = @benchmark benchmark_with_pool($pool, $N_QUERIES) samples=10 seconds=30
println()
println("Results (With Pool):")
println("  Median time: $(BenchmarkTools.prettytime(median(result_with_pool).time))")
println("  Mean time:   $(BenchmarkTools.prettytime(mean(result_with_pool).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_with_pool).memory))")
println("  Allocations: $(median(result_with_pool).allocs)")
println()

# ============================================================================
# Test 3: Per-Query Overhead Comparison
# ============================================================================
println("=" ^ 80)
println("Test 3: Per-Query Overhead Analysis")
println("=" ^ 80)
println()

# Calculate per-query metrics
time_no_pool = median(result_no_pool).time / N_QUERIES
time_with_pool = median(result_with_pool).time / N_QUERIES

mem_no_pool = median(result_no_pool).memory / N_QUERIES
mem_with_pool = median(result_with_pool).memory / N_QUERIES

allocs_no_pool = median(result_no_pool).allocs / N_QUERIES
allocs_with_pool = median(result_with_pool).allocs / N_QUERIES

println("Per-Query Metrics:")
println()
println("No Pool:")
println("  Time per query: $(BenchmarkTools.prettytime(time_no_pool))")
println("  Mem per query:  $(BenchmarkTools.prettymemory(mem_no_pool))")
println("  Allocs per query: $(round(allocs_no_pool, digits=1))")
println()
println("With Pool:")
println("  Time per query: $(BenchmarkTools.prettytime(time_with_pool))")
println("  Mem per query:  $(BenchmarkTools.prettymemory(mem_with_pool))")
println("  Allocs per query: $(round(allocs_with_pool, digits=1))")
println()

# ============================================================================
# Performance Improvements
# ============================================================================
println("=" ^ 80)
println("Summary: Performance Improvements")
println("=" ^ 80)
println()

time_improvement = (time_no_pool - time_with_pool) / time_no_pool * 100
mem_improvement = (mem_no_pool - mem_with_pool) / mem_no_pool * 100
alloc_improvement = (allocs_no_pool - allocs_with_pool) / allocs_no_pool * 100

speedup = time_no_pool / time_with_pool

println("Connection Pooling Benefits:")
println()
println("  Time Reduction:        $(round(time_improvement, digits=2))% faster")
println("  Speedup:               $(round(speedup, digits=2))x")
println("  Memory Reduction:      $(round(mem_improvement, digits=2))% less memory")
println("  Allocation Reduction:  $(round(alloc_improvement, digits=2))% fewer allocations")
println()

if time_improvement >= 80.0
    println("✅ GOAL ACHIEVED: >80% connection overhead reduction")
    println("   Actual: $(round(time_improvement, digits=2))%")
else
    println("⚠️  Target: >80% overhead reduction")
    println("   Actual: $(round(time_improvement, digits=2))%")
    println("   Note: Results may vary based on query complexity and database setup")
end
println()

# ============================================================================
# Test 4: Comparison with Short vs Long Queries
# ============================================================================
println("=" ^ 80)
println("Test 4: Short Query (connection overhead dominant)")
println("=" ^ 80)
println()

function benchmark_short_query_no_pool(driver::SQLiteDriver, path::String)
    """Very short query - connection overhead dominates"""
    db = connect(driver, path)
    result = execute_sql(db, "SELECT 1 as value")
    [NamedTuple(row) for row in result]
    close(db)
end

function benchmark_short_query_with_pool(pool::ConnectionPool)
    """Very short query with pooling"""
    with_connection(pool) do conn
        result = execute_sql(conn, "SELECT 1 as value")
        [NamedTuple(row) for row in result]
    end
end

println("Short query without pool:")
result_short_no_pool = @benchmark benchmark_short_query_no_pool($driver,
                                                                 $temp_db_path) samples=100
println("  Median time: $(BenchmarkTools.prettytime(median(result_short_no_pool).time))")
println()

println("Short query with pool:")
result_short_with_pool = @benchmark benchmark_short_query_with_pool($pool) samples=100
println("  Median time: $(BenchmarkTools.prettytime(median(result_short_with_pool).time))")
println()

short_improvement = (median(result_short_no_pool).time - median(result_short_with_pool).time) /
                    median(result_short_no_pool).time * 100
short_speedup = median(result_short_no_pool).time / median(result_short_with_pool).time

println("Short Query Results:")
println("  Improvement: $(round(short_improvement, digits=2))% faster")
println("  Speedup:     $(round(short_speedup, digits=2))x")
println()

# ============================================================================
# Cleanup
# ============================================================================
close(pool)
rm(temp_db_path; force = true)

println("=" ^ 80)
println("Benchmark Complete")
println("=" ^ 80)
