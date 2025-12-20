#!/usr/bin/env julia

# Run All Benchmarks
# Main entry point for running the complete benchmark suite

using Pkg
Pkg.activate(".")

println("SQLSketch Benchmark Suite")
println("=" ^ 80)
println()
println("This will run all benchmarks in sequence:")
println("  1. Query Construction")
println("  2. SQL Compilation")
println("  3. Query Execution")
println("  4. SQLSketch vs Raw SQL Comparison")
println()
println("=" ^ 80)
println()

# Run each benchmark file
benchmarks = [
    ("Query Construction", "query_construction.jl"),
    ("SQL Compilation", "compilation.jl"),
    ("Query Execution", "execution.jl"),
    ("Comparison", "comparison.jl")
]

for (name, file) in benchmarks
    println()
    println("Running: $name")
    println()
    include(file)
    println()
    println("Completed: $name")
    println("=" ^ 80)
end

println()
println("All benchmarks completed!")
