#!/usr/bin/env julia

# Profile row-based fetch_all to find true bottleneck

include("setup.jl")

using Profile

println("=" ^ 80)
println("Profiling row-based fetch_all")
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

# Test query
q_simple = from(:users) |>
           where(col(:users, :active) == literal(true)) |>
           select(NamedTuple, col(:users, :id), col(:users, :email))

println("Warming up...")
# Warm up
for _ in 1:10
    fetch_all(conn, dialect, registry, q_simple)
end
println()

println("Profiling...")
# Profile
@profile for _ in 1:1000
    fetch_all(conn, dialect, registry, q_simple)
end

println("Done profiling. Generating report...")
println()

# Print profile
Profile.print(; format = :flat, sortedby = :count, maxdepth = 20)

println()
println("=" ^ 80)
println("Top allocations:")
println("=" ^ 80)
using Profile
Profile.clear_malloc_data()

# Run again to collect allocation data
@profile for _ in 1:100
    fetch_all(conn, dialect, registry, q_simple)
end

Profile.print(; format = :flat, sortedby = :count, maxdepth = 15)

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println()
println("✓ Profiling completed!")
