#!/usr/bin/env julia

# Row-based fetch_all Optimization Phases Benchmark
# Measures incremental improvements from each optimization phase

include("setup.jl")

using BenchmarkTools
using LibPQ

println("=" ^ 80)
println("Row-based fetch_all Optimization Phases")
println("Baseline: Current implementation with DecodePlan")
println("=" ^ 80)
println()

# Setup
conn = setup_postgresql_db()
dialect = SQLSketch.PostgreSQLDialect()

using SQLSketch.Codecs.PostgreSQL
registry = PostgreSQL.PostgreSQLCodecRegistry()

println("Setting up test data...")
populate_postgresql_db(conn)
println()

# Get raw connection for baseline
raw_conn = conn.conn

println("=" ^ 80)
println("Baseline Benchmark - Current Implementation")
println("=" ^ 80)
println()

# Test query: Simple SELECT (500 rows)
q_simple = from(:users) |>
           where(col(:users, :active) == literal(true)) |>
           select(NamedTuple, col(:users, :id), col(:users, :email))

raw_sql = "SELECT \"id\", \"email\" FROM \"users\" WHERE \"active\" = true"

println("Test: Simple SELECT (500 rows)")
println()

println("1. Raw LibPQ (baseline):")
result_raw = @benchmark begin
    result = LibPQ.execute($raw_conn, $raw_sql)
    rows = LibPQ.columntable(result)
    LibPQ.close(result)
    rows
end
println("  Median time: $(BenchmarkTools.prettytime(median(result_raw).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_raw).memory))")
println("  Allocations: $(median(result_raw).allocs)")
println()

println("2. fetch_all (current with DecodePlan):")
result_current = @benchmark fetch_all($conn, $dialect, $registry, $q_simple)
println("  Median time: $(BenchmarkTools.prettytime(median(result_current).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_current).memory))")
println("  Allocations: $(median(result_current).allocs)")
println()

overhead_current = (median(result_current).time - median(result_raw).time) /
                   median(result_raw).time * 100
println("Analysis:")
println("  Overhead vs raw LibPQ: $(round(overhead_current, digits=1))%")
println()

println("=" ^ 80)
println("JOIN Query Baseline (1667 rows)")
println("=" ^ 80)
println()

q_join = from(:users) |>
         inner_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
         where(col(:posts, :published) == literal(true)) |>
         select(NamedTuple,
                col(:users, :name),
                col(:posts, :title),
                col(:posts, :created_at))

raw_sql_join = """
SELECT "users"."name", "posts"."title", "posts"."created_at"
FROM "users"
INNER JOIN "posts" ON "users"."id" = "posts"."user_id"
WHERE "posts"."published" = true
"""

println("1. Raw LibPQ (baseline):")
result_join_raw = @benchmark begin
    result = LibPQ.execute($raw_conn, $raw_sql_join)
    rows = LibPQ.columntable(result)
    LibPQ.close(result)
    rows
end
println("  Median time: $(BenchmarkTools.prettytime(median(result_join_raw).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_join_raw).memory))")
println("  Allocations: $(median(result_join_raw).allocs)")
println()

println("2. fetch_all (current):")
result_join_current = @benchmark fetch_all($conn, $dialect, $registry, $q_join)
println("  Median time: $(BenchmarkTools.prettytime(median(result_join_current).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_join_current).memory))")
println("  Allocations: $(median(result_join_current).allocs)")
println()

overhead_join_current = (median(result_join_current).time - median(result_join_raw).time) /
                        median(result_join_raw).time * 100
println("Analysis:")
println("  Overhead vs raw LibPQ: $(round(overhead_join_current, digits=1))%")
println()

println("=" ^ 80)
println("Baseline Summary")
println("=" ^ 80)
println()

println("Simple SELECT (500 rows):")
println("  Raw LibPQ:     $(BenchmarkTools.prettytime(median(result_raw).time))")
println("  fetch_all:     $(BenchmarkTools.prettytime(median(result_current).time))")
println("  Overhead:      $(round(overhead_current, digits=1))%")
println()

println("JOIN Query (1667 rows):")
println("  Raw LibPQ:     $(BenchmarkTools.prettytime(median(result_join_raw).time))")
println("  fetch_all:     $(BenchmarkTools.prettytime(median(result_join_current).time))")
println("  Overhead:      $(round(overhead_join_current, digits=1))%")
println()

println("This is the baseline for optimization phases.")
println("Next: Implement Phase 1 (Type-stable NamedTuple construction)")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Baseline benchmark completed!")
