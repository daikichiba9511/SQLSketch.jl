#!/usr/bin/env julia

# Connection Pooling Benchmark - PostgreSQL
# Measures the overhead reduction from connection pooling with real TCP connections
# Expected: >80% reduction in connection overhead for short queries

include("setup.jl")

using BenchmarkTools
using SQLSketch
using SQLSketch.Drivers: PostgreSQLDriver, PostgreSQLConnection

println("=" ^ 80)
println("Phase 13: Connection Pooling Benchmark (PostgreSQL)")
println("Testing: Connection Pool vs Direct Connection")
println("=" ^ 80)
println()

# Test configuration
const N_QUERIES = 100  # Number of queries to execute

# Get PostgreSQL connection string from environment
const PG_CONN = get(ENV, "SQLSKETCH_PG_CONN", "host=localhost dbname=sqlsketch_bench")

println("PostgreSQL Connection: $PG_CONN")
println()

function setup_test_table(driver::PostgreSQLDriver, conninfo::String)
    """Setup PostgreSQL database with test table"""
    db = connect(driver, conninfo)

    # Drop and recreate table
    execute_sql(db, "DROP TABLE IF EXISTS pool_bench_users")
    execute_sql(db, """
        CREATE TABLE pool_bench_users (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL
        )
    """)

    # Insert test data
    for i in 1:500
        execute_sql(db,
                    "INSERT INTO pool_bench_users (name, email) VALUES (\$1, \$2)",
                    ["User $i", "user$i@example.com"])
    end

    close(db)
end

driver = PostgreSQLDriver()

println("Setting up test database...")
setup_test_table(driver, PG_CONN)
println("✓ Database setup complete")
println()

# ============================================================================
# Test 1: Baseline - Direct Connection (No Pool)
# ============================================================================
println("=" ^ 80)
println("Test 1: Direct Connection (No Pool)")
println("=" ^ 80)
println()

function benchmark_no_pool(driver::PostgreSQLDriver, conninfo::String, n_queries::Int)
    """Execute queries without connection pooling - each query creates new connection"""
    for _ in 1:n_queries
        db = connect(driver, conninfo)
        result = execute_sql(db, "SELECT COUNT(*) as count FROM pool_bench_users")
        # Force iteration to consume result
        for row in result
        end
        close(db)
    end
end

println("Executing $N_QUERIES queries without connection pooling...")
println("(Each query creates a new TCP connection)")
result_no_pool = @benchmark benchmark_no_pool($driver, $PG_CONN, $N_QUERIES) samples=10 seconds=60
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
    """Execute queries with connection pooling - reuses connections"""
    for _ in 1:n_queries
        with_connection(pool) do conn
            result = execute_sql(conn, "SELECT COUNT(*) as count FROM pool_bench_users")
            # Force iteration to consume result
            for row in result
            end
        end
    end
end

println("Creating connection pool (min_size=2, max_size=5)...")
pool = ConnectionPool(driver, PG_CONN; min_size = 2, max_size = 5)
println("✓ Connection pool ready")
println()

println("Executing $N_QUERIES queries with connection pooling...")
println("(Queries reuse existing connections)")
result_with_pool = @benchmark benchmark_with_pool($pool, $N_QUERIES) samples=10 seconds=60
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
println("No Pool (new connection each time):")
println("  Time per query: $(BenchmarkTools.prettytime(time_no_pool))")
println("  Mem per query:  $(BenchmarkTools.prettymemory(mem_no_pool))")
println("  Allocs per query: $(round(allocs_no_pool, digits=1))")
println()
println("With Pool (connection reuse):")
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
end
println()

# ============================================================================
# Test 4: Short Query (connection overhead dominant)
# ============================================================================
println("=" ^ 80)
println("Test 4: Short Query (connection overhead dominant)")
println("=" ^ 80)
println()

function benchmark_short_query_no_pool(driver::PostgreSQLDriver, conninfo::String)
    """Very short query - connection overhead dominates"""
    db = connect(driver, conninfo)
    result = execute_sql(db, "SELECT 1 as value")
    for row in result
    end
    close(db)
end

function benchmark_short_query_with_pool(pool::ConnectionPool)
    """Very short query with pooling"""
    with_connection(pool) do conn
        result = execute_sql(conn, "SELECT 1 as value")
        for row in result
        end
    end
end

println("Short query without pool (SELECT 1):")
result_short_no_pool = @benchmark benchmark_short_query_no_pool($driver, $PG_CONN) samples=100
println("  Median time: $(BenchmarkTools.prettytime(median(result_short_no_pool).time))")
println()

println("Short query with pool (SELECT 1):")
result_short_with_pool = @benchmark benchmark_short_query_with_pool($pool) samples=100
println("  Median time: $(BenchmarkTools.prettytime(median(result_short_with_pool).time))")
println()

short_improvement = (median(result_short_no_pool).time -
                     median(result_short_with_pool).time) /
                    median(result_short_no_pool).time * 100
short_speedup = median(result_short_no_pool).time / median(result_short_with_pool).time

println("Short Query Results:")
println("  Improvement: $(round(short_improvement, digits=2))% faster")
println("  Speedup:     $(round(short_speedup, digits=2))x")
println()

if short_improvement >= 80.0
    println("✅ Short query: >80% overhead reduction achieved")
else
    println("⚠️  Short query: $(round(short_improvement, digits=2))% overhead reduction")
end
println()

# ============================================================================
# Test 5: Query with Data (realistic workload)
# ============================================================================
println("=" ^ 80)
println("Test 5: Realistic Query (SELECT with WHERE)")
println("=" ^ 80)
println()

function benchmark_realistic_no_pool(driver::PostgreSQLDriver, conninfo::String)
    db = connect(driver, conninfo)
    result = execute_sql(db,
                         "SELECT id, name, email FROM pool_bench_users WHERE id < \$1",
                         [100])
    for row in result
    end
    close(db)
end

function benchmark_realistic_with_pool(pool::ConnectionPool)
    with_connection(pool) do conn
        result = execute_sql(conn,
                             "SELECT id, name, email FROM pool_bench_users WHERE id < \$1",
                             [100])
        for row in result
        end
    end
end

println("Realistic query without pool:")
result_realistic_no_pool = @benchmark benchmark_realistic_no_pool($driver, $PG_CONN) samples=100
println("  Median time: $(BenchmarkTools.prettytime(median(result_realistic_no_pool).time))")
println()

println("Realistic query with pool:")
result_realistic_with_pool = @benchmark benchmark_realistic_with_pool($pool) samples=100
println("  Median time: $(BenchmarkTools.prettytime(median(result_realistic_with_pool).time))")
println()

realistic_improvement = (median(result_realistic_no_pool).time -
                         median(result_realistic_with_pool).time) /
                        median(result_realistic_no_pool).time * 100
realistic_speedup = median(result_realistic_no_pool).time /
                    median(result_realistic_with_pool).time

println("Realistic Query Results:")
println("  Improvement: $(round(realistic_improvement, digits=2))% faster")
println("  Speedup:     $(round(realistic_speedup, digits=2))x")
println()

# ============================================================================
# Connection Overhead Breakdown
# ============================================================================
println("=" ^ 80)
println("Test 6: Connection Overhead Breakdown")
println("=" ^ 80)
println()

println("Measuring pure connection establishment time...")

function benchmark_connection_only(driver::PostgreSQLDriver, conninfo::String)
    """Measure just the connection establishment overhead"""
    db = connect(driver, conninfo)
    close(db)
end

result_conn_only = @benchmark benchmark_connection_only($driver, $PG_CONN) samples=100
println("Connection establishment time:")
println("  Median: $(BenchmarkTools.prettytime(median(result_conn_only).time))")
println("  Mean:   $(BenchmarkTools.prettytime(mean(result_conn_only).time))")
println()

println("Connection overhead represents:")
conn_overhead_pct = median(result_conn_only).time / median(result_short_no_pool).time * 100
println("  $(round(conn_overhead_pct, digits=1))% of short query time (SELECT 1)")
println()

# ============================================================================
# Cleanup
# ============================================================================
close(pool)

# Cleanup test table
cleanup_db = connect(driver, PG_CONN)
execute_sql(cleanup_db, "DROP TABLE IF EXISTS pool_bench_users")
close(cleanup_db)

println("=" ^ 80)
println("Benchmark Complete")
println("=" ^ 80)
println()

# Print summary
println("SUMMARY:")
println("--------")
println("1. Complex queries ($N_QUERIES iterations): $(round(time_improvement, digits=2))% faster with pooling")
println("2. Short queries (SELECT 1):                $(round(short_improvement, digits=2))% faster with pooling")
println("3. Realistic queries (SELECT with WHERE):   $(round(realistic_improvement, digits=2))% faster with pooling")
println()
println("Connection establishment overhead: $(BenchmarkTools.prettytime(median(result_conn_only).time))")
println()
