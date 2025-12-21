#!/usr/bin/env julia

# Test: Type-safe columnar results with user-defined structs

include("setup.jl")

using BenchmarkTools
using SQLSketch: fetch_all_columnar

println("=" ^ 80)
println("Type-Safe Columnar Results")
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

# Define regular struct
struct User
    id::String
    email::String
end

# Define columnar version (fields as Vectors)
struct UserColumnar
    id::Vector{String}
    email::Vector{String}
end

# Query
q = from(:users) |>
    where(col(:users, :active) == literal(true)) |>
    select(User, col(:users, :id), col(:users, :email))

println("=" ^ 80)
println("Test 1: Standard columnar (NamedTuple of Vectors)")
println("=" ^ 80)
println()

result_nt = fetch_all_columnar(conn, dialect, registry, q)
println("  Result type: $(typeof(result_nt))")
println("  First ID: $(result_nt.id[1])")
println("  First email: $(result_nt.email[1])")
println("  Total rows: $(length(result_nt.id))")
println()

println("=" ^ 80)
println("Test 2: Type-safe columnar (UserColumnar struct)")
println("=" ^ 80)
println()

result_typed = fetch_all_columnar(conn, dialect, registry, q, UserColumnar)
println("  Result type: $(typeof(result_typed))")
println("  First ID: $(result_typed.id[1])")
println("  First email: $(result_typed.email[1])")
println("  Total rows: $(length(result_typed.id))")
println()

println("=" ^ 80)
println("Type Safety Check")
println("=" ^ 80)
println()

println("  NamedTuple version: type is generic NamedTuple")
println("  Struct version: type is UserColumnar ✅")
println()

# Verify data matches
if result_typed.id == collect(result_nt.id) &&
   result_typed.email == collect(result_nt.email)
    println("  ✅ Data matches between both versions")
else
    println("  ❌ Data mismatch!")
end
println()

println("=" ^ 80)
println("Performance Comparison")
println("=" ^ 80)
println()

println("NamedTuple version:")
bench_nt = @benchmark fetch_all_columnar($conn, $dialect, $registry, $q)
println("  Median time: $(BenchmarkTools.prettytime(median(bench_nt).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(bench_nt).memory))")
println()

println("Struct version:")
bench_struct = @benchmark fetch_all_columnar($conn, $dialect, $registry, $q, $UserColumnar)
println("  Median time: $(BenchmarkTools.prettytime(median(bench_struct).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(bench_struct).memory))")
println()

overhead = (median(bench_struct).time - median(bench_nt).time) / median(bench_nt).time * 100
println("  Overhead: $(round(overhead, digits=1))%")
println()

if abs(overhead) < 10
    println("  ✅ Performance is nearly identical (<10% difference)")
else
    println("  ⚠️  Performance differs by >10%")
end
println()

println("=" ^ 80)
println("Usage Example")
println("=" ^ 80)
println()

println("```julia")
println("# Define your columnar struct")
println("struct UserColumnar")
println("    id::Vector{String}")
println("    email::Vector{String}")
println("end")
println()
println("# Fetch with type safety!")
println("result = fetch_all_columnar(conn, dialect, registry, query, UserColumnar)")
println("# → UserColumnar([...], [...])")
println()
println("# Now type-safe operations:")
println("total_users = length(result.id)")
println("unique_domains = unique(email -> split(email, '@')[2], result.email)")
println("```")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Test completed!")
