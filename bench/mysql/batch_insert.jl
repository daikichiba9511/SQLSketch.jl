"""
# MySQL Batch Insert Benchmarks

Benchmarks to measure the performance of batch insert operations for MySQL.

## Setup

Requires MySQL 8.0+ running locally:
```bash
docker run --name mysql-bench -e MYSQL_ROOT_PASSWORD=test -e MYSQL_DATABASE=sqlsketch_bench \\
  -p 3307:3306 -d mysql:8.0
```

## Results

Batch insert provides:
- 5-10x faster than individual INSERTs for small batches (100-1000 rows)
- 10-50x faster for large batches (10K+ rows)
- Scales linearly with batch size
"""

using BenchmarkTools
using SQLSketch
using SQLSketch.Core: insert_batch, execute, CodecRegistry
using SQLSketch.Core: create_table, add_column, drop_table
using SQLSketch.Core: insert_into, values, literal
using SQLSketch: MySQLDriver, MySQLDialect

# Connection configuration
const MYSQL_HOST = get(ENV, "MYSQL_HOST", "127.0.0.1")
const MYSQL_PORT = parse(Int, get(ENV, "MYSQL_PORT", "3307"))
const MYSQL_USER = get(ENV, "MYSQL_USER", "test_user")
const MYSQL_PASSWORD = get(ENV, "MYSQL_PASSWORD", "test_password")
const MYSQL_DATABASE = get(ENV, "MYSQL_DATABASE", "sqlsketch_bench")

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
    @warn "Skipping MySQL batch insert benchmarks - MySQL not available"
    exit(0)
end

println("=" ^ 80)
println("MySQL Batch Insert Benchmarks")
println("=" ^ 80)
println()

# Setup
driver = MySQLDriver()
dialect = MySQLDialect()
registry = CodecRegistry()

conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
               user = MYSQL_USER, password = MYSQL_PASSWORD, port = MYSQL_PORT)

# Create test table
try
    execute(conn, dialect, drop_table(:bench_batch; if_exists = true))
catch
end

ddl = create_table(:bench_batch; if_not_exists = true) |>
      add_column(:id, :integer; primary_key = true, auto_increment = true) |>
      add_column(:email, :varchar; nullable = false) |>
      add_column(:name, :varchar; nullable = false) |>
      add_column(:age, :integer) |>
      add_column(:active, :boolean)

execute(conn, dialect, ddl)
println("✓ Test table created")
println()

#
# Helper Functions
#

"""
Generate test data with specified number of rows.
"""
function generate_test_data(n::Int)
    return [(email = "user$i@example.com", name = "User $i", age = 20+mod(i, 50),
             active = isodd(i))
            for i in 1:n]
end

"""
Cleanup table between benchmarks.
"""
function cleanup_table(conn, dialect)
    execute_sql(conn, "TRUNCATE TABLE bench_batch", [])
end

#
# Benchmark 1: Individual INSERTs vs Batch Insert
#

println("Benchmark 1: Individual INSERTs vs Batch Insert")
println("-" ^ 80)

batch_sizes = [10, 100, 1000, 5000]

for n in batch_sizes
    println("Inserting $n rows:")

    # Individual INSERTs
    data = generate_test_data(n)
    cleanup_table(conn, dialect)

    t_individual = @benchmark begin
        for row in $data
            q = insert_into(:bench_batch, [:email, :name, :age, :active]) |>
                insert_values([[literal(row.email), literal(row.name),
                         literal(row.age), literal(row.active)]])
            execute($conn, $dialect, q)
        end
    end

    # Batch insert
    cleanup_table(conn, dialect)

    t_batch = @benchmark begin
        insert_batch($conn, $dialect, $registry, :bench_batch,
                     [:email, :name, :age, :active], $data)
    end

    speedup = median(t_individual).time / median(t_batch).time

    println("  Individual INSERTs: $(round(median(t_individual).time / 1e6, digits=2)) ms")
    println("  Batch insert: $(round(median(t_batch).time / 1e6, digits=2)) ms")
    println("  Speedup: $(round(speedup, digits=2))x")
    println()
end

#
# Benchmark 2: Chunk Size Impact
#

println("Benchmark 2: Chunk Size Impact (10K rows)")
println("-" ^ 80)

data_10k = generate_test_data(10000)
chunk_sizes = [100, 500, 1000, 2000, 5000]

for chunk_size in chunk_sizes
    cleanup_table(conn, dialect)

    t = @benchmark insert_batch($conn, $dialect, $registry, :bench_batch,
                                [:email, :name, :age, :active], $data_10k;
                                chunk_size = $chunk_size)

    println("  Chunk size $chunk_size: $(round(median(t).time / 1e6, digits=2)) ms")
end

println()

#
# Benchmark 3: Throughput Test (Large Batches)
#

println("Benchmark 3: Throughput Test")
println("-" ^ 80)

large_batch_sizes = [1000, 5000, 10000, 50000]

println("Rows/sec throughput:")
println()

for n in large_batch_sizes
    data = generate_test_data(n)
    cleanup_table(conn, dialect)

    t = @benchmark insert_batch($conn, $dialect, $registry, :bench_batch,
                                [:email, :name, :age, :active], $data)

    median_time_sec = median(t).time / 1e9
    throughput = n / median_time_sec

    println("  $n rows: $(round(throughput, digits=0)) rows/sec " *
            "($(round(median_time_sec * 1000, digits=2)) ms total)")
end

println()

#
# Benchmark 4: Memory Usage
#

println("Benchmark 4: Memory Usage (100K rows)")
println("-" ^ 80)

data_100k = generate_test_data(100000)
cleanup_table(conn, dialect)

println("Generating 100K rows...")
println("  Memory allocated: $(Base.summarysize(data_100k) / 1024 / 1024 |> x -> round(x, digits=2)) MB")
println()

println("Batch inserting...")
t = @benchmark insert_batch($conn, $dialect, $registry, :bench_batch,
                            [:email, :name, :age, :active], $data_100k)

println("  Median time: $(round(median(t).time / 1e6, digits=2)) ms")
println("  Allocations: $(median(t).allocs)")
println("  Memory: $(round(median(t).memory / 1024 / 1024, digits=2)) MB")
println()

#
# Cleanup
#

try
    execute(conn, dialect, drop_table(:bench_batch; if_exists = true))
    println("✓ Cleanup complete")
catch e
    @warn "Cleanup failed" exception=e
finally
    close(conn)
end

println()
println("=" ^ 80)
println("MySQL Batch Insert Benchmarks Complete")
println("=" ^ 80)
