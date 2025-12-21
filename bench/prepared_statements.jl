# Final Prepared Statement Performance Benchmark
# Tests driver-level prepared statement caching (default behavior)

include("setup.jl")

using BenchmarkTools

println("Setting up test database...")
driver = SQLSketch.SQLiteDriver()
conn = connect(driver, ":memory:")
dialect = SQLSketch.SQLiteDialect()
registry = SQLSketch.CodecRegistry()

populate_db(conn.db)

println("=" ^ 80)
println("Prepared Statement Performance Benchmark (Driver-level Caching)")
println("=" ^ 80)
println()

# Benchmark suite
suite = BenchmarkGroup()
suite["direct_execution"] = BenchmarkGroup()
suite["prepared_statements"] = BenchmarkGroup()

queries = get_sample_queries()
query_asts = Dict(name => builder() for (name, builder) in queries)

# Warm up driver cache with prepared statements
println("Warming up driver cache...")
for (name, q) in query_asts
    fetch_all(conn, dialect, registry, q; use_prepared = true)
end
println("✓ Cache warmed")
println()

println("Benchmarking direct execution (no prepared statements)...")
for (name, q) in query_asts
    suite["direct_execution"][string(name)] = @benchmarkable fetch_all($conn,
                                                                       $dialect,
                                                                       $registry, $q;
                                                                       use_prepared = false)
end

println("Benchmarking with prepared statements (driver-level cache)...")
for (name, q) in query_asts
    suite["prepared_statements"][string(name)] = @benchmarkable fetch_all($conn,
                                                                          $dialect,
                                                                          $registry,
                                                                          $q;
                                                                          use_prepared = true)
end

# Run benchmarks
results = run(suite; verbose = true)

println()
println("=" ^ 80)
println("Performance Comparison: Prepared Statements vs Direct")
println("=" ^ 80)
println()

speedups = Float64[]

for name in keys(query_asts)
    name_str = string(name)
    if haskey(results["direct_execution"], name_str) &&
       haskey(results["prepared_statements"], name_str)
        direct_time = median(results["direct_execution"][name_str]).time
        prepared_time = median(results["prepared_statements"][name_str]).time
        speedup = (direct_time - prepared_time) / direct_time * 100

        push!(speedups, speedup)

        println("$name_str:")
        println("  Direct execution:   $(BenchmarkTools.prettytime(direct_time))")
        println("  Prepared statement: $(BenchmarkTools.prettytime(prepared_time))")
        println("  Speedup:            $(round(speedup, digits=2))%")
        println()
    end
end

# Summary
println("=" ^ 80)
println("Summary Statistics")
println("=" ^ 80)
println()

if !isempty(speedups)
    avg_speedup = mean(speedups)
    min_speedup = minimum(speedups)
    max_speedup = maximum(speedups)

    println("Average speedup: $(round(avg_speedup, digits=2))%")
    println("Min speedup:     $(round(min_speedup, digits=2))%")
    println("Max speedup:     $(round(max_speedup, digits=2))%")
    println()

    if avg_speedup >= 10
        println("✅ GOAL ACHIEVED: Driver-level prepared statements provide $(round(avg_speedup, digits=2))% speedup!")
    elseif avg_speedup > 0
        println("⚠️  Marginal improvement: $(round(avg_speedup, digits=2))% speedup")
    else
        println("⚠️  No improvement detected")
    end
    println()
end

println("=" ^ 80)
println("Implementation Summary")
println("=" ^ 80)
println()
println("Strategy: Driver-level Prepared Statement Caching")
println()
println("Implementation:")
println("  - SQLiteConnection maintains connection-level stmt_cache (Dict{String, Stmt})")
println("  - prepare_statement() checks cache before creating new Stmt")
println("  - fetch_all() uses prepared statements by default (use_prepared=true)")
println("  - No application-level cache overhead (hash, lock, OrderedDict)")
println()
println("Benefits:")
println("  - Simple, transparent caching at driver level")
println("  - No user action required - automatic optimization")
println("  - Statements reused for identical SQL strings")
println("  - Compatible with all drivers (graceful fallback)")
println()
println("Next Steps (Phase 13 continuation):")
println("  - Connection Pooling (shared cache across connections)")
println("  - Batch Operations (COPY for PostgreSQL, batch INSERT)")
println("  - Streaming Results (iterator-based row fetching)")
