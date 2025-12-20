# SQL Compilation Benchmarks
# Measures the overhead of compiling Query ASTs to SQL

include("setup.jl")

using BenchmarkTools

# Setup a dialect for SQL compilation
dialect = SQLSketch.SQLiteDialect()

# Benchmark suite for SQL compilation
suite = BenchmarkGroup()

queries = get_sample_queries()

# Pre-build queries
query_asts = Dict(name => builder() for (name, builder) in queries)

# Benchmark compilation for each query type
for (name, q) in query_asts
    suite[string(name)] = @benchmarkable sql($dialect, $q)
end

# Run benchmarks
println("=" ^ 80)
println("SQL Compilation Benchmarks")
println("=" ^ 80)
println()

results = run(suite; verbose = true)

println()
println("Summary:")
println("-" ^ 80)

for (name, result) in results
    med = median(result)
    println("$name:")
    println("  Median time: $(BenchmarkTools.prettytime(med.time))")
    println("  Memory:      $(BenchmarkTools.prettymemory(med.memory))")
    println("  Allocations: $(med.allocs)")
    println()
end
