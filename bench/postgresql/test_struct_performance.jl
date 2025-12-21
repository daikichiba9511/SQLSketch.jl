#!/usr/bin/env julia

# Benchmark: NamedTuple vs Struct performance

include("setup.jl")

using BenchmarkTools
using SQLSketch: fetch_all_columnar

println("=" ^ 80)
println("NamedTuple vs Struct Performance Comparison")
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

# Define struct
struct User
    id::String
    email::String
end

# Queries
q_namedtuple = from(:users) |>
               where(col(:users, :active) == literal(true)) |>
               select(NamedTuple, col(:users, :id), col(:users, :email))

q_struct = from(:users) |>
           where(col(:users, :active) == literal(true)) |>
           select(User, col(:users, :id), col(:users, :email))

println("=" ^ 80)
println("Test 1: NamedTuple (500 rows)")
println("=" ^ 80)
println()

result_nt = @benchmark fetch_all($conn, $dialect, $registry, $q_namedtuple)
println("  Median time: $(BenchmarkTools.prettytime(median(result_nt).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_nt).memory))")
println("  Allocations: $(median(result_nt).allocs)")
println()

println("=" ^ 80)
println("Test 2: Struct (500 rows)")
println("=" ^ 80)
println()

result_struct = @benchmark fetch_all($conn, $dialect, $registry, $q_struct)
println("  Median time: $(BenchmarkTools.prettytime(median(result_struct).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_struct).memory))")
println("  Allocations: $(median(result_struct).allocs)")
println()

# Compare
time_diff = (median(result_struct).time - median(result_nt).time) / median(result_nt).time *
            100
mem_diff = (median(result_struct).memory - median(result_nt).memory) /
           median(result_nt).memory * 100

println("=" ^ 80)
println("Comparison")
println("=" ^ 80)
println()
println("  Time difference:   $(round(time_diff, digits=1))%")
println("  Memory difference: $(round(mem_diff, digits=1))%")
println()

if abs(time_diff) < 10
    println("  ✅ Performance is nearly identical (<10% difference)")
else
    println("  ⚠️  Performance differs by >10%")
end
println()

# Correctness check
println("=" ^ 80)
println("Correctness Check")
println("=" ^ 80)
println()

rows_nt = fetch_all(conn, dialect, registry, q_namedtuple)
rows_struct = fetch_all(conn, dialect, registry, q_struct)

println("  NamedTuple count: $(length(rows_nt))")
println("  Struct count:     $(length(rows_struct))")
println("  First NamedTuple: $(rows_nt[1])")
println("  First Struct:     $(rows_struct[1])")
println("  Match: $(rows_nt[1].id == rows_struct[1].id && rows_nt[1].email == rows_struct[1].email)")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Test completed!")
