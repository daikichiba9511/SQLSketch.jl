#!/usr/bin/env julia

# SQLite vs PostgreSQL Performance Comparison
# Compares identical queries on both databases

include("setup.jl")
include("../setup.jl")  # SQLite setup

using BenchmarkTools

println("=" ^ 80)
println("SQLite vs PostgreSQL Performance Comparison")
println("=" ^ 80)
println()

# Setup SQLite
println("Setting up SQLite...")
sqlite_driver = SQLSketch.SQLiteDriver()
sqlite_conn = connect(sqlite_driver, ":memory:")
sqlite_dialect = SQLSketch.SQLiteDialect()
populate_db(sqlite_conn.db)
println("✓ SQLite ready")
println()

# Setup PostgreSQL
println("Setting up PostgreSQL...")
pg_conn = setup_postgresql_db()
pg_dialect = SQLSketch.PostgreSQLDialect()
populate_postgresql_db(pg_conn)
println("✓ PostgreSQL ready")
println()

registry = SQLSketch.CodecRegistry()

# Common queries (excluding PostgreSQL-specific)
common_queries = Dict(:simple_select => () -> begin
                          from(:users) |>
                          where(col(:users, :active) == literal(true)) |>
                          select(NamedTuple, col(:users, :id), col(:users, :email))
                      end,
                      :join_query => () -> begin
                          from(:users) |>
                          innerjoin(:posts, col(:users, :id) == col(:posts, :user_id)) |>
                          where(col(:posts, :published) == literal(true)) |>
                          select(NamedTuple,
                                 col(:users, :name),
                                 col(:posts, :title),
                                 col(:posts, :created_at))
                      end,
                      :filter_and_project => () -> begin
                          from(:posts) |>
                          where(col(:posts, :published) == literal(true)) |>
                          select(NamedTuple,
                                 col(:posts, :user_id),
                                 col(:posts, :title))
                      end,
                      :order_and_limit => () -> begin
                          from(:posts) |>
                          where(col(:posts, :published) == literal(true)) |>
                          order_by(col(:posts, :created_at); desc = true) |>
                          limit(10) |>
                          select(NamedTuple, col(:posts, :id), col(:posts, :title))
                      end)

query_asts = Dict(name => builder() for (name, builder) in common_queries)

println("=" ^ 80)
println("Benchmarking identical queries on both databases")
println("=" ^ 80)
println()

suite = BenchmarkGroup()
suite["sqlite"] = BenchmarkGroup()
suite["postgresql"] = BenchmarkGroup()

# SQLite benchmarks
println("Benchmarking SQLite...")
for (name, q) in query_asts
    suite["sqlite"][string(name)] = @benchmarkable fetch_all($sqlite_conn, $sqlite_dialect,
                                                             $registry, $q)
end

# PostgreSQL benchmarks
println("Benchmarking PostgreSQL...")
for (name, q) in query_asts
    suite["postgresql"][string(name)] = @benchmarkable fetch_all($pg_conn, $pg_dialect,
                                                                 $registry, $q)
end

results = run(suite; verbose = true)

println()
println("=" ^ 80)
println("Performance Comparison Results")
println("=" ^ 80)
println()

comparison_data = []

for name in keys(query_asts)
    name_str = string(name)
    if haskey(results["sqlite"], name_str) && haskey(results["postgresql"], name_str)
        sqlite_time = median(results["sqlite"][name_str]).time
        pg_time = median(results["postgresql"][name_str]).time
        sqlite_allocs = median(results["sqlite"][name_str]).allocs
        pg_allocs = median(results["postgresql"][name_str]).allocs

        speedup = (sqlite_time / pg_time - 1) * 100
        alloc_diff = (sqlite_allocs / pg_allocs - 1) * 100

        push!(comparison_data,
              (name = name_str,
               sqlite_time = sqlite_time,
               pg_time = pg_time,
               speedup = speedup,
               sqlite_allocs = sqlite_allocs,
               pg_allocs = pg_allocs,
               alloc_diff = alloc_diff))

        println("$name_str:")
        println("  SQLite:      $(BenchmarkTools.prettytime(sqlite_time)) ($(sqlite_allocs) allocs)")
        println("  PostgreSQL:  $(BenchmarkTools.prettytime(pg_time)) ($(pg_allocs) allocs)")

        if speedup > 0
            println("  SQLite is $(round(abs(speedup), digits=2))% SLOWER")
        else
            println("  SQLite is $(round(abs(speedup), digits=2))% FASTER")
        end
        println()
    end
end

# Summary
println("=" ^ 80)
println("Summary Statistics")
println("=" ^ 80)
println()

if !isempty(comparison_data)
    speedups = [d.speedup for d in comparison_data]
    avg_speedup = mean(speedups)

    println("Average performance:")
    if avg_speedup > 0
        println("  PostgreSQL is $(round(avg_speedup, digits=2))% faster than SQLite")
    else
        println("  SQLite is $(round(abs(avg_speedup), digits=2))% faster than PostgreSQL")
    end
    println()

    println("Per-query breakdown:")
    for d in comparison_data
        winner = d.speedup > 0 ? "PostgreSQL" : "SQLite"
        margin = abs(d.speedup)
        println("  $(d.name): $winner wins by $(round(margin, digits=2))%")
    end
    println()
end

println("=" ^ 80)
println("Key Observations")
println("=" ^ 80)
println()
println("SQLite advantages:")
println("  - In-memory database (no network overhead)")
println("  - Simpler architecture (fewer layers)")
println("  - Good for development/testing")
println()
println("PostgreSQL advantages:")
println("  - Production-ready (ACID, transactions)")
println("  - Rich type system (UUID, JSONB, Arrays)")
println("  - Better concurrency support")
println("  - Advanced features (CTEs, Window functions)")
println()
println("Recommendation:")
println("  - Use SQLite for: development, testing, embedded apps")
println("  - Use PostgreSQL for: production, complex queries, multi-user apps")
println()

# Cleanup
cleanup_postgresql_db(pg_conn)
Base.close(pg_conn)
Base.close(sqlite_conn)

println("✓ Comparison completed!")
