# Query Construction Benchmarks
# Measures the overhead of building Query ASTs

include("setup.jl")

using BenchmarkTools

# Benchmark suite for query construction
suite = BenchmarkGroup()

queries = get_sample_queries()

# Benchmark each query type
for (name, builder) in queries
    suite[string(name)] = @benchmarkable $builder()
end

# Run benchmarks
println("=" ^ 80)
println("Query Construction Benchmarks")
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

    # Add to global suite
    push!(SUITE, "Query Construction - $name", result)
end
