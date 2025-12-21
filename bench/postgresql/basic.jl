#!/usr/bin/env julia

# PostgreSQL Basic Performance Benchmarks
# Measures query construction, compilation, and execution performance

include("setup.jl")

using BenchmarkTools

println("=" ^ 80)
println("PostgreSQL Basic Performance Benchmarks")
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

# Get queries
queries = get_postgresql_queries()
query_asts = Dict(name => builder() for (name, builder) in queries)

println("=" ^ 80)
println("1. Query Construction Performance")
println("=" ^ 80)
println()

suite_construction = BenchmarkGroup()
for (name, builder) in queries
    suite_construction[string(name)] = @benchmarkable $builder()
end

results_construction = run(suite_construction; verbose = true)

println()
println("Summary:")
println("-" ^ 80)
for (name, result) in results_construction
    med = median(result)
    println("$name:")
    println("  Median time: $(BenchmarkTools.prettytime(med.time))")
    println("  Memory:      $(BenchmarkTools.prettymemory(med.memory))")
    println("  Allocations: $(med.allocs)")
    println()
end

println("=" ^ 80)
println("2. SQL Compilation Performance")
println("=" ^ 80)
println()

suite_compilation = BenchmarkGroup()
for (name, q) in query_asts
    suite_compilation[string(name)] = @benchmarkable sql($dialect, $q)
end

results_compilation = run(suite_compilation; verbose = true)

println()
println("Summary:")
println("-" ^ 80)
for (name, result) in results_compilation
    med = median(result)
    println("$name:")
    println("  Median time: $(BenchmarkTools.prettytime(med.time))")
    println("  Memory:      $(BenchmarkTools.prettymemory(med.memory))")
    println("  Allocations: $(med.allocs)")
    println()
end

println("=" ^ 80)
println("3. Query Execution Performance")
println("=" ^ 80)
println()

suite_execution = BenchmarkGroup()
for (name, q) in query_asts
    # Skip JSONB and Array queries if they have issues
    if name in [:jsonb_query, :array_query]
        continue
    end
    suite_execution[string(name)] = @benchmarkable fetch_all($conn, $dialect, $registry, $q)
end

results_execution = run(suite_execution; verbose = true)

println()
println("Summary:")
println("-" ^ 80)
for (name, result) in results_execution
    med = median(result)
    println("$name:")
    println("  Median time: $(BenchmarkTools.prettytime(med.time))")
    println("  Memory:      $(BenchmarkTools.prettymemory(med.memory))")
    println("  Allocations: $(med.allocs)")
    println()
end

println("=" ^ 80)
println("Overall Summary")
println("=" ^ 80)
println()

println("Query Construction (median):")
for (name, result) in results_construction
    med = median(result).time
    println("  $name: $(BenchmarkTools.prettytime(med))")
end
println()

println("SQL Compilation (median):")
for (name, result) in results_compilation
    med = median(result).time
    println("  $name: $(BenchmarkTools.prettytime(med))")
end
println()

println("Query Execution (median):")
for (name, result) in results_execution
    med = median(result).time
    println("  $name: $(BenchmarkTools.prettytime(med))")
end
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Benchmarks completed!")
