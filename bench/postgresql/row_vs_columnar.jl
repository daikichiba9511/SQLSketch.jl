#!/usr/bin/env julia

# Row-based vs Columnar Format Benchmark
# Compares fetch_all (row-based) vs fetch_all_columnar (columnar)

include("setup.jl")

using BenchmarkTools
using LibPQ
using SQLSketch: fetch_all_columnar

println("=" ^ 80)
println("Row-based vs Columnar Format Benchmark")
println("Comparing: fetch_all vs fetch_all_columnar")
println("=" ^ 80)
println()

# Setup
conn = setup_postgresql_db()
dialect = SQLSketch.PostgreSQLDialect()

using SQLSketch.Codecs.PostgreSQL
registry = PostgreSQL.PostgreSQLCodecRegistry()

println()
println("Setting up test data...")
populate_postgresql_db(conn)
println()

# Get raw connection for baseline
raw_conn = conn.conn

println("=" ^ 80)
println("Test 1: Simple SELECT (500 rows)")
println("=" ^ 80)
println()

q_simple = from(:users) |>
           where(col(:users, :active) == literal(true)) |>
           select(NamedTuple, col(:users, :id), col(:users, :email))

raw_sql = "SELECT \"id\", \"email\" FROM \"users\" WHERE \"active\" = true"

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

println("2. fetch_all (row-based NamedTuple):")
result_row = @benchmark fetch_all($conn, $dialect, $registry, $q_simple)
println("  Median time: $(BenchmarkTools.prettytime(median(result_row).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_row).memory))")
println("  Allocations: $(median(result_row).allocs)")
println()

println("3. fetch_all_columnar (columnar NamedTuple):")
result_col = @benchmark fetch_all_columnar($conn, $dialect, $registry, $q_simple)
println("  Median time: $(BenchmarkTools.prettytime(median(result_col).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_col).memory))")
println("  Allocations: $(median(result_col).allocs)")
println()

speedup_row_vs_col = median(result_row).time / median(result_col).time
overhead_row = (median(result_row).time - median(result_raw).time) / median(result_raw).time * 100
overhead_col = (median(result_col).time - median(result_raw).time) / median(result_raw).time * 100

println("Analysis:")
println("  Row-based overhead vs raw:     $(round(overhead_row, digits=1))%")
println("  Columnar overhead vs raw:      $(round(overhead_col, digits=1))%")
println("  Columnar speedup vs row-based: $(round(speedup_row_vs_col, digits=1))x")
println()

println("=" ^ 80)
println("Test 2: JOIN Query (1667 rows)")
println("=" ^ 80)
println()

q_join = from(:users) |>
         innerjoin(:posts, col(:users, :id) == col(:posts, :user_id)) |>
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

println("2. fetch_all (row-based):")
result_join_row = @benchmark fetch_all($conn, $dialect, $registry, $q_join)
println("  Median time: $(BenchmarkTools.prettytime(median(result_join_row).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_join_row).memory))")
println("  Allocations: $(median(result_join_row).allocs)")
println()

println("3. fetch_all_columnar (columnar):")
result_join_col = @benchmark fetch_all_columnar($conn, $dialect, $registry, $q_join)
println("  Median time: $(BenchmarkTools.prettytime(median(result_join_col).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_join_col).memory))")
println("  Allocations: $(median(result_join_col).allocs)")
println()

speedup_join = median(result_join_row).time / median(result_join_col).time
overhead_join_row = (median(result_join_row).time - median(result_join_raw).time) / median(result_join_raw).time * 100
overhead_join_col = (median(result_join_col).time - median(result_join_raw).time) / median(result_join_raw).time * 100

println("Analysis:")
println("  Row-based overhead vs raw:     $(round(overhead_join_row, digits=1))%")
println("  Columnar overhead vs raw:      $(round(overhead_join_col, digits=1))%")
println("  Columnar speedup vs row-based: $(round(speedup_join, digits=1))x")
println()

println("=" ^ 80)
println("Test 3: ORDER BY + LIMIT (10 rows)")
println("=" ^ 80)
println()

q_limit = from(:posts) |>
          where(col(:posts, :published) == literal(true)) |>
          order_by(col(:posts, :created_at); desc = true) |>
          limit(10) |>
          select(NamedTuple, col(:posts, :id), col(:posts, :title))

raw_sql_limit = """
SELECT "id", "title"
FROM "posts"
WHERE "published" = true
ORDER BY "created_at" DESC
LIMIT 10
"""

println("1. Raw LibPQ (baseline):")
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

println("2. fetch_all (row-based):")
result_limit_row = @benchmark fetch_all($conn, $dialect, $registry, $q_limit)
println("  Median time: $(BenchmarkTools.prettytime(median(result_limit_row).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_limit_row).memory))")
println("  Allocations: $(median(result_limit_row).allocs)")
println()

println("3. fetch_all_columnar (columnar):")
result_limit_col = @benchmark fetch_all_columnar($conn, $dialect, $registry, $q_limit)
println("  Median time: $(BenchmarkTools.prettytime(median(result_limit_col).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_limit_col).memory))")
println("  Allocations: $(median(result_limit_col).allocs)")
println()

speedup_limit = median(result_limit_row).time / median(result_limit_col).time
overhead_limit_row = (median(result_limit_row).time - median(result_limit_raw).time) / median(result_limit_raw).time * 100
overhead_limit_col = (median(result_limit_col).time - median(result_limit_raw).time) / median(result_limit_raw).time * 100

println("Analysis:")
println("  Row-based overhead vs raw:     $(round(overhead_limit_row, digits=1))%")
println("  Columnar overhead vs raw:      $(round(overhead_limit_col, digits=1))%")
println("  Columnar speedup vs row-based: $(round(speedup_limit, digits=1))x")
println()

println("=" ^ 80)
println("Summary: Row-based vs Columnar Comparison")
println("=" ^ 80)
println()

println("Performance Summary:")
println()
println("| Query | Row-based | Columnar | Speedup |")
println("|-------|-----------|----------|---------|")
println("| Simple SELECT (500 rows) | $(BenchmarkTools.prettytime(median(result_row).time)) | $(BenchmarkTools.prettytime(median(result_col).time)) | **$(round(speedup_row_vs_col, digits=1))x** |")
println("| JOIN (1667 rows) | $(BenchmarkTools.prettytime(median(result_join_row).time)) | $(BenchmarkTools.prettytime(median(result_join_col).time)) | **$(round(speedup_join, digits=1))x** |")
println("| ORDER BY + LIMIT (10 rows) | $(BenchmarkTools.prettytime(median(result_limit_row).time)) | $(BenchmarkTools.prettytime(median(result_limit_col).time)) | **$(round(speedup_limit, digits=1))x** |")
println()

avg_speedup = (speedup_row_vs_col + speedup_join + speedup_limit) / 3
println("Average speedup: $(round(avg_speedup, digits=1))x")
println()

println("Overhead Analysis (vs Raw LibPQ):")
println()
println("Row-based (fetch_all):")
println("  Simple SELECT:   $(round(overhead_row, digits=1))%")
println("  JOIN Query:      $(round(overhead_join_row, digits=1))%")
println("  Small result:    $(round(overhead_limit_row, digits=1))%")
println()

println("Columnar (fetch_all_columnar):")
println("  Simple SELECT:   $(round(overhead_col, digits=1))%")
println("  JOIN Query:      $(round(overhead_join_col, digits=1))%")
println("  Small result:    $(round(overhead_limit_col, digits=1))%")
println()

println("=" ^ 80)
println("Recommendations")
println("=" ^ 80)
println()

println("Use fetch_all (row-based) when:")
println("  ✅ Building web applications (CRUD operations)")
println("  ✅ Need to iterate over individual records")
println("  ✅ Working with small result sets (<1000 rows)")
println("  ✅ Row-by-row processing is natural for your use case")
println()

println("Use fetch_all_columnar (columnar) when:")
println("  ✅ Running analytics queries")
println("  ✅ Working with large result sets (>1000 rows)")
println("  ✅ Need column-wise operations (sum, mean, etc.)")
println("  ✅ Exporting to DataFrame/CSV")
println("  ✅ Performance is critical (~$(round(avg_speedup, digits=0))x faster!)")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Benchmark completed!")
