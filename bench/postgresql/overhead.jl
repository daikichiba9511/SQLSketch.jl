#!/usr/bin/env julia

# PostgreSQL Overhead Benchmarks
# Compares SQLSketch vs raw LibPQ.jl performance to measure overhead

include("setup.jl")

using BenchmarkTools
using LibPQ

println("=" ^ 80)
println("PostgreSQL Overhead Analysis: SQLSketch vs Raw LibPQ")
println("=" ^ 80)
println()

# Setup
conn = setup_postgresql_db()
dialect = SQLSketch.PostgreSQLDialect()
registry = SQLSketch.CodecRegistry()

println()
println("Setting up test data...")
populate_postgresql_db(conn)
println()

# Get raw LibPQ connection
raw_conn = conn.conn  # PostgreSQLConnection wraps LibPQ.Connection

println("=" ^ 80)
println("Benchmarking: Simple SELECT (500 rows)")
println("=" ^ 80)
println()

# SQLSketch version
q_sqlsketch = from(:users) |>
              where(col(:users, :active) == literal(true)) |>
              select(NamedTuple, col(:users, :id), col(:users, :email))

# Raw SQL version
raw_sql = "SELECT \"id\", \"email\" FROM \"users\" WHERE \"active\" = true"

println("SQLSketch version:")
result_sqlsketch = @benchmark fetch_all($conn, $dialect, $registry, $q_sqlsketch)
println("  Median time: $(BenchmarkTools.prettytime(median(result_sqlsketch).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_sqlsketch).memory))")
println("  Allocations: $(median(result_sqlsketch).allocs)")
println()

println("Raw LibPQ version:")
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

overhead_time = (median(result_sqlsketch).time - median(result_raw).time) /
                median(result_raw).time * 100
overhead_memory = (median(result_sqlsketch).memory - median(result_raw).memory) /
                  median(result_raw).memory * 100
overhead_allocs = median(result_sqlsketch).allocs - median(result_raw).allocs

println("Overhead:")
println("  Time:        $(round(overhead_time, digits=2))%")
println("  Memory:      $(round(overhead_memory, digits=2))%")
println("  Allocations: +$(overhead_allocs) allocs")
println()

println("=" ^ 80)
println("Benchmarking: JOIN Query (1667 rows)")
println("=" ^ 80)
println()

# SQLSketch version
q_join_sqlsketch = from(:users) |>
                   innerjoin(:posts, col(:users, :id) == col(:posts, :user_id)) |>
                   where(col(:posts, :published) == literal(true)) |>
                   select(NamedTuple,
                          col(:users, :name),
                          col(:posts, :title),
                          col(:posts, :created_at))

# Raw SQL version
raw_sql_join = """
SELECT "users"."name", "posts"."title", "posts"."created_at"
FROM "users"
INNER JOIN "posts" ON "users"."id" = "posts"."user_id"
WHERE "posts"."published" = true
"""

println("SQLSketch version:")
result_join_sqlsketch = @benchmark fetch_all($conn, $dialect, $registry, $q_join_sqlsketch)
println("  Median time: $(BenchmarkTools.prettytime(median(result_join_sqlsketch).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_join_sqlsketch).memory))")
println("  Allocations: $(median(result_join_sqlsketch).allocs)")
println()

println("Raw LibPQ version:")
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

overhead_join_time = (median(result_join_sqlsketch).time - median(result_join_raw).time) /
                     median(result_join_raw).time * 100
overhead_join_memory = (median(result_join_sqlsketch).memory -
                        median(result_join_raw).memory) / median(result_join_raw).memory *
                       100
overhead_join_allocs = median(result_join_sqlsketch).allocs - median(result_join_raw).allocs

println("Overhead:")
println("  Time:        $(round(overhead_join_time, digits=2))%")
println("  Memory:      $(round(overhead_join_memory, digits=2))%")
println("  Allocations: +$(overhead_join_allocs) allocs")
println()

println("=" ^ 80)
println("Benchmarking: ORDER BY + LIMIT (10 rows)")
println("=" ^ 80)
println()

# SQLSketch version
q_limit_sqlsketch = from(:posts) |>
                    where(col(:posts, :published) == literal(true)) |>
                    order_by(col(:posts, :created_at); desc = true) |>
                    limit(10) |>
                    select(NamedTuple, col(:posts, :id), col(:posts, :title))

# Raw SQL version
raw_sql_limit = """
SELECT "id", "title"
FROM "posts"
WHERE "published" = true
ORDER BY "created_at" DESC
LIMIT 10
"""

println("SQLSketch version:")
result_limit_sqlsketch = @benchmark fetch_all($conn, $dialect, $registry,
                                              $q_limit_sqlsketch)
println("  Median time: $(BenchmarkTools.prettytime(median(result_limit_sqlsketch).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_limit_sqlsketch).memory))")
println("  Allocations: $(median(result_limit_sqlsketch).allocs)")
println()

println("Raw LibPQ version:")
result_limit_raw = @benchmark begin
    result = LibPQ.execute($raw_conn, $raw_sql_limit)
    rows = LibPQ.columntable(result)
    LibPQ.close(result)
    rows
end
println("  Median time: $(BenchmarkTools.prettytime(median(result_limit_raw).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_limit_raw).memory))")
println("  Allocations: $(median(result_limit_raw).allocs)")
println()

overhead_limit_time = (median(result_limit_sqlsketch).time - median(result_limit_raw).time) /
                      median(result_limit_raw).time * 100
overhead_limit_memory = (median(result_limit_sqlsketch).memory -
                         median(result_limit_raw).memory) /
                        median(result_limit_raw).memory * 100
overhead_limit_allocs = median(result_limit_sqlsketch).allocs -
                        median(result_limit_raw).allocs

println("Overhead:")
println("  Time:        $(round(overhead_limit_time, digits=2))%")
println("  Memory:      $(round(overhead_limit_memory, digits=2))%")
println("  Allocations: +$(overhead_limit_allocs) allocs")
println()

println("=" ^ 80)
println("Summary: SQLSketch Overhead Analysis")
println("=" ^ 80)
println()

println("Simple SELECT (500 rows):")
println("  Time overhead:   $(round(overhead_time, digits=2))%")
println("  Memory overhead: $(round(overhead_memory, digits=2))%")
println("  Extra allocs:    +$(overhead_allocs)")
println()

println("JOIN Query (1667 rows):")
println("  Time overhead:   $(round(overhead_join_time, digits=2))%")
println("  Memory overhead: $(round(overhead_join_memory, digits=2))%")
println("  Extra allocs:    +$(overhead_join_allocs)")
println()

println("ORDER BY + LIMIT (10 rows):")
println("  Time overhead:   $(round(overhead_limit_time, digits=2))%")
println("  Memory overhead: $(round(overhead_limit_memory, digits=2))%")
println("  Extra allocs:    +$(overhead_limit_allocs)")
println()

avg_overhead_time = (overhead_time + overhead_join_time + overhead_limit_time) / 3
avg_overhead_memory = (overhead_memory + overhead_join_memory + overhead_limit_memory) / 3

println("Average overhead:")
println("  Time:   $(round(avg_overhead_time, digits=2))%")
println("  Memory: $(round(avg_overhead_memory, digits=2))%")
println()

println("=" ^ 80)
println("Key Findings")
println("=" ^ 80)
println()

println("SQLSketch components that add overhead:")
println("  1. Query AST construction (~300ns)")
println("  2. SQL compilation (~1-8μs)")
println("  3. Codec encoding/decoding")
println("  4. Result mapping to NamedTuple")
println()

println("PostgreSQL baseline (raw LibPQ):")
println("  - Network round-trip")
println("  - Query planning & execution")
println("  - Result serialization")
println()

println("Optimization opportunities:")
println("  - Prepared statement caching (Phase 13)")
println("  - Connection pooling (Phase 13)")
println("  - Codec optimization")
println("  - Result mapping optimization")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Overhead analysis completed!")
