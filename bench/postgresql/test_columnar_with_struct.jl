#!/usr/bin/env julia

# Test: fetch_all_columnar accepts both Query{NamedTuple} and Query{Struct}

include("setup.jl")

using SQLSketch: fetch_all_columnar

println("=" ^ 80)
println("Test: fetch_all_columnar with different Query types")
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
println("Test 1: fetch_all_columnar with Query{NamedTuple}")
println("=" ^ 80)
println()

result_nt = fetch_all_columnar(conn, dialect, registry, q_namedtuple)
println("  Result type: $(typeof(result_nt))")
println("  First 3 IDs: $(result_nt.id[1:3])")
println("  First 3 emails: $(result_nt.email[1:3])")
println()

println("=" ^ 80)
println("Test 2: fetch_all_columnar with Query{User}")
println("=" ^ 80)
println()

result_struct = fetch_all_columnar(conn, dialect, registry, q_struct)
println("  Result type: $(typeof(result_struct))")
println("  First 3 IDs: $(result_struct.id[1:3])")
println("  First 3 emails: $(result_struct.email[1:3])")
println()

println("=" ^ 80)
println("Comparison")
println("=" ^ 80)
println()

if result_nt == result_struct
    println("  ✅ Both queries return identical columnar results")
    println("  ✅ Type parameter (NamedTuple vs User) is ignored - this is expected!")
else
    println("  ❌ Results differ (unexpected)")
end
println()

println("Key insight:")
println("  fetch_all_columnar ALWAYS returns NamedTuple of Vectors,")
println("  regardless of Query{T} type parameter.")
println("  The T parameter is only used by fetch_all for conversion.")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Test completed!")
