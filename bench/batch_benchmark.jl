"""
# Batch Operations Benchmarks

Performance benchmarks for batch INSERT operations.

Compares:
- Loop INSERT (baseline)
- Standard batch INSERT (multi-row VALUES)
- PostgreSQL COPY (when available)

## Usage

```bash
# SQLite only
julia --project=. benchmark/batch_benchmark.jl

# SQLite + PostgreSQL
SQLSKETCH_PG_CONN="host=localhost dbname=mydb" julia --project=. benchmark/batch_benchmark.jl
```
"""

using BenchmarkTools
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers
using Printf

# Import PostgreSQL codec registry at top level
using SQLSketch.Codecs.PostgreSQL: PostgreSQLCodecRegistry

# Benchmark configuration
const SUITE = BenchmarkGroup()
const SIZES = [10, 100, 1_000, 10_000]  # Row counts to test

#
# Helper Functions
#

"""
Generate test data for benchmarking.
"""
function generate_test_data(n::Int)
    return [(id = i, email = "user$(i)@example.com", active = true) for i in 1:n]
end

"""
Clear table for fresh benchmark run.
"""
function clear_table(conn, table::Symbol)
    execute_sql(conn, "DELETE FROM $(String(table))", [])
end

"""
Loop INSERT baseline (slowest method).
"""
function insert_loop_sqlite(conn, rows)
    for row in rows
        execute_sql(conn,
                    "INSERT INTO users (id, email, active) VALUES (?, ?, ?)",
                    [row.id, row.email, row.active ? 1 : 0])
    end
end

function insert_loop_postgresql(conn, rows)
    for row in rows
        execute_sql(conn,
                    "INSERT INTO bench_users (id, email, active) VALUES (\$1, \$2, \$3)",
                    [row.id, row.email, row.active])
    end
end

"""
Format time in human-readable form.
"""
function format_time(ns::Float64)
    if ns < 1_000
        return @sprintf("%.2f ns", ns)
    elseif ns < 1_000_000
        return @sprintf("%.2f μs", ns / 1_000)
    elseif ns < 1_000_000_000
        return @sprintf("%.2f ms", ns / 1_000_000)
    else
        return @sprintf("%.2f s", ns / 1_000_000_000)
    end
end

"""
Calculate speedup ratio.
"""
function speedup(baseline_ns::Float64, optimized_ns::Float64)
    return baseline_ns / optimized_ns
end

#
# SQLite Benchmarks
#

function benchmark_sqlite()
    println("\n" * "="^80)
    println("SQLite Batch INSERT Benchmarks")
    println("="^80)

    # Setup
    driver = SQLiteDriver()
    conn = connect(driver, ":memory:")
    dialect = SQLiteDialect()
    registry = CodecRegistry()

    # Create test table
    execute_sql(conn,
                """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY,
                    email TEXT NOT NULL,
                    active INTEGER NOT NULL
                )
                """,
                [])

    println("\nBenchmarking SQLite batch operations...")

    # Run benchmarks for each size
    for n in SIZES
        println("\n--- $n rows ---")

        rows = generate_test_data(n)

        # 1. Loop INSERT (baseline)
        loop_time = @belapsed begin
            try
                transaction($conn) do tx
                    insert_loop_sqlite(tx, $rows)
                    error("rollback")  # Force rollback
                end
            catch
                # Ignore rollback error
            end
        end samples = 3 evals = 1

        # 2. Batch INSERT
        batch_time = @belapsed begin
            try
                transaction($conn) do tx
                    insert_batch(tx, $dialect, $registry, :users, [:id, :email, :active],
                                 $rows)
                    error("rollback")  # Force rollback
                end
            catch
                # Ignore rollback error
            end
        end samples = 3 evals = 1

        # Results
        println("  Loop INSERT:  $(format_time(loop_time * 1e9))")
        println("  Batch INSERT: $(format_time(batch_time * 1e9))")
        println("  Speedup:      $(Printf.@sprintf("%.2fx", speedup(loop_time, batch_time)))")
    end

    # Cleanup
    close(conn)
end

#
# PostgreSQL Benchmarks
#

function benchmark_postgresql(conninfo::String)
    println("\n" * "="^80)
    println("PostgreSQL Batch INSERT Benchmarks")
    println("="^80)

    # Setup
    driver = PostgreSQLDriver()
    conn = connect(driver, conninfo)
    dialect = PostgreSQLDialect()

    # Use PostgreSQL-specific codec registry
    registry = PostgreSQLCodecRegistry()

    # Create test table
    execute_sql(conn, "DROP TABLE IF EXISTS bench_users", [])
    execute_sql(conn,
                """
                CREATE TABLE bench_users (
                    id INTEGER PRIMARY KEY,
                    email TEXT NOT NULL,
                    active BOOLEAN NOT NULL
                )
                """,
                [])

    println("\nBenchmarking PostgreSQL batch operations...")

    # Run benchmarks for each size
    for n in SIZES
        println("\n--- $n rows ---")

        rows = generate_test_data(n)

        # 1. Loop INSERT (baseline)
        loop_time = @belapsed begin
            try
                transaction($conn) do tx
                    insert_loop_postgresql(tx, $rows)
                    error("rollback")  # Force rollback
                end
            catch
                # Ignore rollback error
            end
        end samples = 3 evals = 1

        # 2. COPY INSERT (automatic when using PostgreSQL)
        copy_time = @belapsed begin
            try
                transaction($conn) do tx
                    insert_batch(tx, $dialect, $registry, :bench_users,
                                 [:id, :email, :active],
                                 $rows)
                    error("rollback")  # Force rollback
                end
            catch
                # Ignore rollback error
            end
        end samples = 3 evals = 1

        # Results
        println("  Loop INSERT:  $(format_time(loop_time * 1e9))")
        println("  COPY INSERT:  $(format_time(copy_time * 1e9))")
        println("  Speedup:      $(Printf.@sprintf("%.2fx", speedup(loop_time, copy_time)))")
    end

    # Cleanup
    execute_sql(conn, "DROP TABLE IF EXISTS bench_users", [])
    close(conn)
end

#
# Main
#

function main()
    println("""
    ┌────────────────────────────────────────────────────────────────────────────┐
    │                     SQLSketch Batch Operations Benchmark                   │
    │                                                                            │
    │  Comparing:                                                                │
    │    - Loop INSERT (baseline - slowest)                                     │
    │    - Batch INSERT (multi-row VALUES - fast)                               │
    │    - PostgreSQL COPY (fastest for PostgreSQL)                             │
    └────────────────────────────────────────────────────────────────────────────┘
    """)

    # Always run SQLite benchmarks
    benchmark_sqlite()

    # Run PostgreSQL benchmarks if connection info is provided
    pg_conninfo = get(ENV, "SQLSKETCH_PG_CONN", nothing)
    if pg_conninfo !== nothing
        try
            benchmark_postgresql(pg_conninfo)
        catch e
            println("\n⚠️  PostgreSQL benchmark failed: $e")
            println("    Skipping PostgreSQL benchmarks.")
        end
    else
        println("\n" * "="^80)
        println("PostgreSQL Benchmarks: SKIPPED")
        println("="^80)
        println("\nSet SQLSKETCH_PG_CONN environment variable to run PostgreSQL benchmarks.")
        println("Example: SQLSKETCH_PG_CONN=\"host=localhost dbname=mydb\" julia benchmark/batch_benchmark.jl")
    end

    println("\n" * "="^80)
    println("Benchmark Complete!")
    println("="^80)
end

# Run benchmarks
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
