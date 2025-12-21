#!/usr/bin/env julia

# PostgreSQL-Specific Type Benchmarks
# Tests performance of UUID, JSONB, Array, and other PostgreSQL types

include("setup.jl")

using BenchmarkTools

println("=" ^ 80)
println("PostgreSQL-Specific Type Benchmarks")
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

println("=" ^ 80)
println("Type-Specific Query Performance")
println("=" ^ 80)
println()

# UUID query
println("1. UUID Type Performance")
println("-" ^ 80)

q_uuid = from(:users) |>
         where(col(:users, :active) == literal(true)) |>
         select(NamedTuple, col(:users, :id), col(:users, :email))

result_uuid = @benchmark fetch_all($conn, $dialect, $registry, $q_uuid)
println("UUID query (500 rows with UUID primary keys):")
println("  Median time: $(BenchmarkTools.prettytime(median(result_uuid).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_uuid).memory))")
println("  Allocations: $(median(result_uuid).allocs)")
println()

# Boolean query
println("2. Boolean Type Performance")
println("-" ^ 80)

q_bool = from(:users) |>
         select(NamedTuple, col(:users, :id), col(:users, :active))

result_bool = @benchmark fetch_all($conn, $dialect, $registry, $q_bool)
println("Boolean query (1000 rows with native BOOLEAN):")
println("  Median time: $(BenchmarkTools.prettytime(median(result_bool).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_bool).memory))")
println("  Allocations: $(median(result_bool).allocs)")
println()

# Timestamp query
println("3. Timestamp Type Performance")
println("-" ^ 80)

q_timestamp = from(:posts) |>
              limit(100) |>
              select(NamedTuple, col(:posts, :id), col(:posts, :created_at))

result_timestamp = @benchmark fetch_all($conn, $dialect, $registry, $q_timestamp)
println("Timestamp query (100 rows with TIMESTAMP):")
println("  Median time: $(BenchmarkTools.prettytime(median(result_timestamp).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_timestamp).memory))")
println("  Allocations: $(median(result_timestamp).allocs)")
println()

# JSONB query (if supported)
println("4. JSONB Type Performance")
println("-" ^ 80)
println("Note: JSONB queries currently use raw SQL expressions")

try
    q_jsonb = from(:posts) |>
              where(raw_expr("metadata->>'category' = 'cat_1'")) |>
              limit(100) |>
              select(NamedTuple, col(:posts, :title), col(:posts, :metadata))

    result_jsonb = @benchmark fetch_all($conn, $dialect, $registry, $q_jsonb)
    println("JSONB query (100 rows with JSONB metadata):")
    println("  Median time: $(BenchmarkTools.prettytime(median(result_jsonb).time))")
    println("  Memory:      $(BenchmarkTools.prettymemory(median(result_jsonb).memory))")
    println("  Allocations: $(median(result_jsonb).allocs)")
    println()
catch e
    println("❌ JSONB query failed: $e")
    println("This is expected if JSONB codec is not fully implemented")
    println()
end

# Array query (if supported)
println("5. Array Type Performance")
println("-" ^ 80)
println("Note: Array queries currently use raw SQL expressions")

try
    q_array = from(:posts) |>
              where(raw_expr("'tag_5' = ANY(tags)")) |>
              limit(100) |>
              select(NamedTuple, col(:posts, :title), col(:posts, :tags))

    result_array = @benchmark fetch_all($conn, $dialect, $registry, $q_array)
    println("Array query (100 rows with TEXT[] tags):")
    println("  Median time: $(BenchmarkTools.prettytime(median(result_array).time))")
    println("  Memory:      $(BenchmarkTools.prettymemory(median(result_array).memory))")
    println("  Allocations: $(median(result_array).allocs)")
    println()
catch e
    println("❌ Array query failed: $e")
    println("This is expected if Array codec is not fully implemented")
    println()
end

println("=" ^ 80)
println("Summary")
println("=" ^ 80)
println()
println("PostgreSQL native type support:")
println("  ✅ UUID - Fully supported, good performance")
println("  ✅ BOOLEAN - Native support (vs SQLite INTEGER)")
println("  ✅ TIMESTAMP - Native support")
println("  ⚠️  JSONB - Requires raw_expr for queries")
println("  ⚠️  TEXT[] - Requires raw_expr for queries")
println()
println("Future improvements:")
println("  - First-class JSONB expression support")
println("  - First-class Array expression support")
println("  - JSONB path operators (->>, ->, #>, etc.)")
println("  - Array operators (ANY, ALL, @>, etc.)")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Type benchmarks completed!")
