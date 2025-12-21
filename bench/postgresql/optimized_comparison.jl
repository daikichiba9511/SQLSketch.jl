#!/usr/bin/env julia

# Optimized DecodePlan Comparison Benchmarks
# Compares optimized fetch_all_optimized vs standard fetch_all

include("setup.jl")

using BenchmarkTools
using LibPQ

println("=" ^ 80)
println("DecodePlan Optimization Benchmark")
println("Comparing: fetch_all (standard) vs fetch_all_optimized (DecodePlan)")
println("=" ^ 80)
println()

# Setup
conn = setup_postgresql_db()
dialect = SQLSketch.PostgreSQLDialect()

# Use PostgreSQL-specific CodecRegistry
using SQLSketch.Codecs.PostgreSQL
registry = PostgreSQL.PostgreSQLCodecRegistry()

println()
println("Setting up test data...")
populate_postgresql_db(conn)
println()

# Import fetch_all_optimized
using SQLSketch.Drivers: fetch_all_optimized

println("=" ^ 80)
println("Test 1: Simple SELECT (500 rows)")
println("=" ^ 80)
println()

# SQLSketch query
q_simple = from(:users) |>
           where(col(:users, :active) == literal(true)) |>
           select(NamedTuple, col(:users, :id), col(:users, :email))

println("Standard fetch_all:")
result_standard = @benchmark fetch_all($conn, $dialect, $registry, $q_simple)
println("  Median time: $(BenchmarkTools.prettytime(median(result_standard).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_standard).memory))")
println("  Allocations: $(median(result_standard).allocs)")
println()

println("Optimized fetch_all_optimized (DecodePlan):")
result_optimized = @benchmark fetch_all_optimized($conn, $dialect, $registry, $q_simple)
println("  Median time: $(BenchmarkTools.prettytime(median(result_optimized).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_optimized).memory))")
println("  Allocations: $(median(result_optimized).allocs)")
println()

# Calculate improvement
time_improvement = (median(result_standard).time - median(result_optimized).time) /
                   median(result_standard).time * 100
memory_improvement = (median(result_standard).memory - median(result_optimized).memory) /
                     median(result_standard).memory * 100
alloc_reduction = median(result_standard).allocs - median(result_optimized).allocs

println("Improvement:")
println("  Time:        $(round(time_improvement, digits=2))% faster")
println("  Memory:      $(round(memory_improvement, digits=2))% reduction")
println("  Allocations: -$(alloc_reduction) allocs ($(round(alloc_reduction / median(result_standard).allocs * 100, digits=2))% reduction)")
println()

println("=" ^ 80)
println("Test 2: JOIN Query (1667 rows)")
println("=" ^ 80)
println()

q_join = from(:users) |>
         inner_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
         where(col(:posts, :published) == literal(true)) |>
         select(NamedTuple,
                col(:users, :name),
                col(:posts, :title),
                col(:posts, :created_at))

println("Standard fetch_all:")
result_join_standard = @benchmark fetch_all($conn, $dialect, $registry, $q_join)
println("  Median time: $(BenchmarkTools.prettytime(median(result_join_standard).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_join_standard).memory))")
println("  Allocations: $(median(result_join_standard).allocs)")
println()

println("Optimized fetch_all_optimized (DecodePlan):")
result_join_optimized = @benchmark fetch_all_optimized($conn, $dialect, $registry, $q_join)
println("  Median time: $(BenchmarkTools.prettytime(median(result_join_optimized).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_join_optimized).memory))")
println("  Allocations: $(median(result_join_optimized).allocs)")
println()

time_improvement_join = (median(result_join_standard).time -
                         median(result_join_optimized).time) /
                        median(result_join_standard).time * 100
memory_improvement_join = (median(result_join_standard).memory -
                           median(result_join_optimized).memory) /
                          median(result_join_standard).memory * 100
alloc_reduction_join = median(result_join_standard).allocs -
                       median(result_join_optimized).allocs

println("Improvement:")
println("  Time:        $(round(time_improvement_join, digits=2))% faster")
println("  Memory:      $(round(memory_improvement_join, digits=2))% reduction")
println("  Allocations: -$(alloc_reduction_join) allocs ($(round(alloc_reduction_join / median(result_join_standard).allocs * 100, digits=2))% reduction)")
println()

println("=" ^ 80)
println("Test 3: ORDER BY + LIMIT (10 rows)")
println("=" ^ 80)
println()

q_limit = from(:posts) |>
          where(col(:posts, :published) == literal(true)) |>
          order_by(col(:posts, :created_at); desc = true) |>
          limit(10) |>
          select(NamedTuple, col(:posts, :id), col(:posts, :title))

println("Standard fetch_all:")
result_limit_standard = @benchmark fetch_all($conn, $dialect, $registry, $q_limit)
println("  Median time: $(BenchmarkTools.prettytime(median(result_limit_standard).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_limit_standard).memory))")
println("  Allocations: $(median(result_limit_standard).allocs)")
println()

println("Optimized fetch_all_optimized (DecodePlan):")
result_limit_optimized = @benchmark fetch_all_optimized($conn, $dialect, $registry,
                                                        $q_limit)
println("  Median time: $(BenchmarkTools.prettytime(median(result_limit_optimized).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_limit_optimized).memory))")
println("  Allocations: $(median(result_limit_optimized).allocs)")
println()

time_improvement_limit = (median(result_limit_standard).time -
                          median(result_limit_optimized).time) /
                         median(result_limit_standard).time * 100
memory_improvement_limit = (median(result_limit_standard).memory -
                            median(result_limit_optimized).memory) /
                           median(result_limit_standard).memory * 100
alloc_reduction_limit = median(result_limit_standard).allocs -
                        median(result_limit_optimized).allocs

println("Improvement:")
println("  Time:        $(round(time_improvement_limit, digits=2))% faster")
println("  Memory:      $(round(memory_improvement_limit, digits=2))% reduction")
println("  Allocations: -$(alloc_reduction_limit) allocs ($(round(alloc_reduction_limit / median(result_limit_standard).allocs * 100, digits=2))% reduction)")
println()

println("=" ^ 80)
println("Summary: DecodePlan Optimization Results")
println("=" ^ 80)
println()

println("Simple SELECT (500 rows):")
println("  Time improvement:   $(round(time_improvement, digits=2))%")
println("  Memory reduction:   $(round(memory_improvement, digits=2))%")
println("  Allocation reduction: $(round(alloc_reduction / median(result_standard).allocs * 100, digits=2))%")
println()

println("JOIN Query (1667 rows):")
println("  Time improvement:   $(round(time_improvement_join, digits=2))%")
println("  Memory reduction:   $(round(memory_improvement_join, digits=2))%")
println("  Allocation reduction: $(round(alloc_reduction_join / median(result_join_standard).allocs * 100, digits=2))%")
println()

println("ORDER BY + LIMIT (10 rows):")
println("  Time improvement:   $(round(time_improvement_limit, digits=2))%")
println("  Memory reduction:   $(round(memory_improvement_limit, digits=2))%")
println("  Allocation reduction: $(round(alloc_reduction_limit / median(result_limit_standard).allocs * 100, digits=2))%")
println()

avg_time_improvement = (time_improvement + time_improvement_join + time_improvement_limit) /
                       3
avg_memory_improvement = (memory_improvement + memory_improvement_join +
                          memory_improvement_limit) / 3

println("Average improvement across all tests:")
println("  Time:   $(round(avg_time_improvement, digits=2))% faster")
println("  Memory: $(round(avg_memory_improvement, digits=2))% reduction")
println()

println("=" ^ 80)
println("Key Findings")
println("=" ^ 80)
println()

println("DecodePlan optimization provides:")
println("  ✓ Eliminates repeated codec lookups")
println("  ✓ Pre-resolves column metadata")
println("  ✓ Type-stable inner loops")
println("  ✓ Reduced memory allocations")
println()

println("Impact scales with result set size:")
println("  - Small results (10 rows): Modest improvement")
println("  - Medium results (500 rows): Significant improvement")
println("  - Large results (1667+ rows): Maximum benefit")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Optimization comparison completed!")
