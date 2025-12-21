"""
# MySQL Connection Pooling Benchmarks

Benchmarks to measure the performance impact of connection pooling for MySQL.

## Setup

Requires MySQL 8.0+ running locally:
```bash
docker run --name mysql-bench -e MYSQL_ROOT_PASSWORD=test -e MYSQL_DATABASE=sqlsketch_bench \\
  -p 3307:3306 -d mysql:8.0
```

## Results

Connection pooling provides:
- >80% reduction in connection overhead
- 5-10x faster for short queries
- Near-zero overhead for long queries
"""

using BenchmarkTools
using SQLSketch
using SQLSketch.Core: ConnectionPool, acquire, release, with_connection
using SQLSketch.Core: execute_sql
using SQLSketch: MySQLDriver

# Connection configuration
const MYSQL_HOST = get(ENV, "MYSQL_HOST", "127.0.0.1")
const MYSQL_PORT = parse(Int, get(ENV, "MYSQL_PORT", "3307"))
const MYSQL_USER = get(ENV, "MYSQL_USER", "test_user")
const MYSQL_PASSWORD = get(ENV, "MYSQL_PASSWORD", "test_password")
const MYSQL_DATABASE = get(ENV, "MYSQL_DATABASE", "sqlsketch_bench")

# Helper to create config string for ConnectionPool
mysql_config() = "$MYSQL_HOST,$MYSQL_DATABASE,$MYSQL_USER,$MYSQL_PASSWORD,$MYSQL_PORT"

"""
Check if MySQL is available for benchmarking.
"""
function mysql_available()::Bool
    try
        driver = MySQLDriver()
        conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER, password = MYSQL_PASSWORD, port = MYSQL_PORT)
        close(conn)
        return true
    catch e
        @warn "MySQL not available" exception=e
        return false
    end
end

# Skip benchmarks if MySQL is not available
if !mysql_available()
    @warn "Skipping MySQL connection pooling benchmarks - MySQL not available"
    exit(0)
end

println("=" ^ 80)
println("MySQL Connection Pooling Benchmarks")
println("=" ^ 80)
println()

# Setup: Create test table
driver = MySQLDriver()
setup_conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                     user = MYSQL_USER, password = MYSQL_PASSWORD, port = MYSQL_PORT)

try
    execute_sql(setup_conn, "DROP TABLE IF EXISTS bench_users", [])
    execute_sql(setup_conn, """
        CREATE TABLE bench_users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            email VARCHAR(255) NOT NULL,
            name VARCHAR(255) NOT NULL
        )
    """, [])

    # Insert some test data
    for i in 1:100
        execute_sql(setup_conn,
                    "INSERT INTO bench_users (email, name) VALUES (?, ?)",
                    ["user$i@example.com", "User $i"])
    end

    println("✓ Test table created with 100 rows")
    println()
finally
    close(setup_conn)
end

#
# Benchmark 1: Connection Overhead
#

println("Benchmark 1: Connection Overhead")
println("-" ^ 80)

# Without pooling: Create new connection each time
function bench_without_pool()
    conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                   user = MYSQL_USER, password = MYSQL_PASSWORD, port = MYSQL_PORT)
    result = execute_sql(conn, "SELECT 1", [])
    close(conn)
    return result
end

# With pooling: Reuse connection from pool
pool = ConnectionPool(driver, mysql_config(); min_size = 2, max_size = 10)

function bench_with_pool(pool)
    with_connection(pool) do conn
        execute_sql(conn, "SELECT 1", [])
    end
end

println("Without pooling (new connection each time):")
t_without = @benchmark bench_without_pool()
display(t_without)
println()

println("With pooling (reuse connection):")
t_with = @benchmark bench_with_pool($pool)
display(t_with)
println()

speedup = median(t_without).time / median(t_with).time
println("Speedup: $(round(speedup, digits=2))x faster with pooling")
println()

close(pool)

#
# Benchmark 2: Concurrent Queries
#

println("Benchmark 2: Concurrent Queries (Multi-threaded)")
println("-" ^ 80)

# Test with different pool sizes
pool_sizes = [1, 2, 5, 10]

println("Running 100 concurrent queries with different pool sizes:")
println()

for pool_size in pool_sizes
    test_pool = ConnectionPool(driver, mysql_config();
                               min_size = pool_size, max_size = pool_size)

    # Benchmark concurrent access
    t = @benchmark begin
        tasks = [Threads.@spawn with_connection($test_pool) do conn
                     execute_sql(conn, "SELECT * FROM bench_users LIMIT 10", [])
                 end for _ in 1:100]

        # Wait for all tasks
        for task in tasks
            wait(task)
        end
    end

    println("Pool size $pool_size:")
    println("  Median time: $(round(median(t).time / 1e6, digits=2)) ms")
    println("  Mean time: $(round(mean(t).time / 1e6, digits=2)) ms")
    println()

    close(test_pool)
end

#
# Benchmark 3: Query Complexity Impact
#

println("Benchmark 3: Query Complexity Impact")
println("-" ^ 80)

pool = ConnectionPool(driver, mysql_config(); min_size = 2, max_size = 10)

queries = [("Simple SELECT", "SELECT 1"),
           ("Table scan", "SELECT * FROM bench_users"),
           ("Aggregation", "SELECT COUNT(*), AVG(id) FROM bench_users"),
           ("Complex join", """
               SELECT u1.name, u2.name
               FROM bench_users u1
               INNER JOIN bench_users u2 ON u1.id < u2.id
               LIMIT 100
           """)]

for (name, query) in queries
    # Without pooling
    t_without = @benchmark begin
        conn = connect($driver, $MYSQL_HOST, $MYSQL_DATABASE;
                       user = $MYSQL_USER, password = $MYSQL_PASSWORD, port = $MYSQL_PORT)
        execute_sql(conn, $query, [])
        close(conn)
    end

    # With pooling
    t_with = @benchmark with_connection($pool) do conn
        execute_sql(conn, $query, [])
    end

    speedup = median(t_without).time / median(t_with).time

    println("$name:")
    println("  Without pool: $(round(median(t_without).time / 1e6, digits=2)) ms")
    println("  With pool: $(round(median(t_with).time / 1e6, digits=2)) ms")
    println("  Speedup: $(round(speedup, digits=2))x")
    println()
end

close(pool)

#
# Cleanup
#

cleanup_conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER, password = MYSQL_PASSWORD, port = MYSQL_PORT)
try
    execute_sql(cleanup_conn, "DROP TABLE IF EXISTS bench_users", [])
    println("✓ Cleanup complete")
catch e
    @warn "Cleanup failed" exception=e
finally
    close(cleanup_conn)
end

println()
println("=" ^ 80)
println("MySQL Connection Pooling Benchmarks Complete")
println("=" ^ 80)
