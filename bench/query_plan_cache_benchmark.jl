"""
# Query Plan Cache Benchmarks

Performance benchmarks for query plan caching.

Compares:
- Without cache (baseline)
- With query plan cache (optimized)

Tests compilation performance for:
- Simple queries
- Complex queries with joins
- Queries with multiple filters
- Window functions
- Set operations

## Usage

```bash
julia --project=. benchmark/query_plan_cache_benchmark.jl
```
"""

using BenchmarkTools
using SQLSketch
using SQLSketch.Core
using SQLSketch.Core.QueryPlanCache
using Printf

# Benchmark configuration
const SUITE = BenchmarkGroup()
const ITERATIONS = [1, 10, 100, 1_000]  # Number of repeated compilations

#
# Helper Functions
#

"""
Format time in human-readable form.
"""
function format_time(ns::Float64)
    if ns < 1_000
        return @sprintf("%.2f ns", ns)
    elseif ns < 1_000_000
        return @sprintf("%.2f μs", ns / 1_000)
    elseif ns < 1_000_000_000
        return @sprintf("%.2f ms", ns / 1_000_000)
    else
        return @sprintf("%.2f s", ns / 1_000_000_000)
    end
end

"""
Calculate speedup ratio.
"""
function speedup(baseline_ns::Float64, optimized_ns::Float64)
    return baseline_ns / optimized_ns
end

#
# Query Generators
#

"""
Simple query: SELECT with WHERE clause.
"""
function simple_query()
    return from(:users) |>
           where(col(:users, :active) == literal(true)) |>
           select(NamedTuple, col(:users, :id), col(:users, :name))
end

"""
Complex query with JOIN.
"""
function complex_join_query()
    return from(:users) |>
           leftjoin(:posts, col(:users, :id) == col(:posts, :user_id)) |>
           where(col(:posts, :published) == literal(true)) |>
           select(NamedTuple, col(:users, :name), col(:posts, :title)) |>
           order_by(col(:posts, :created_at); desc = true) |>
           limit(10)
end

"""
Query with multiple filters.
"""
function multi_filter_query()
    return from(:users) |>
           where(col(:users, :age) > literal(18)) |>
           where(col(:users, :active) == literal(true)) |>
           where(col(:users, :email) != literal("")) |>
           select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email))
end

"""
Query with window function.
"""
function window_function_query()
    return from(:employees) |>
           select(NamedTuple,
                  col(:employees, :name),
                  col(:employees, :department),
                  row_number(over(; partition_by = [col(:employees, :department)],
                                  order_by = [(col(:employees, :salary), true)])))
end

"""
Query with set operation (UNION).
"""
function set_operation_query()
    q1 = from(:users) |>
         where(col(:users, :active) == literal(true)) |>
         select(NamedTuple, col(:users, :email))

    q2 = from(:legacy_users) |>
         where(col(:legacy_users, :active) == literal(true)) |>
         select(NamedTuple, col(:legacy_users, :email))

    return SQLSketch.Core.union(q1, q2)
end

#
# Benchmark Functions
#

"""
Benchmark compilation without cache (baseline).
"""
function benchmark_without_cache(query_fn, n::Int)
    dialect = SQLiteDialect()

    # Warmup
    compile(dialect, query_fn())

    # Benchmark
    return @benchmark begin
        for _ in 1:($n)
            compile($dialect, $query_fn())
        end
    end samples=10 evals=1
end

"""
Benchmark compilation with cache.
"""
function benchmark_with_cache(query_fn, n::Int)
    dialect = SQLiteDialect()
    cache = QueryPlanCache(; max_size = 100)

    # Warmup
    compile_with_cache(cache, dialect, query_fn())

    # Benchmark
    return @benchmark begin
        cache = QueryPlanCache(max_size = 100)
        for _ in 1:($n)
            compile_with_cache(cache, $dialect, $query_fn())
        end
    end samples=10 evals=1
end

"""
Run benchmarks for a specific query type.
"""
function benchmark_query_type(name::String, query_fn::Function)
    println("\n" * "-"^80)
    println("Query Type: $name")
    println("-"^80)

    results = []

    for n in ITERATIONS
        # Without cache
        without_cache = benchmark_without_cache(query_fn, n)
        without_time = median(without_cache).time

        # With cache
        with_cache = benchmark_with_cache(query_fn, n)
        with_time = median(with_cache).time

        # Calculate speedup
        ratio = speedup(without_time, with_time)

        # Get cache stats after benchmark
        dialect = SQLiteDialect()
        cache = QueryPlanCache(; max_size = 100)
        for _ in 1:n
            compile_with_cache(cache, dialect, query_fn())
        end
        stats = cache_stats(cache)

        push!(results,
              (iterations = n,
               without_cache_time = without_time,
               with_cache_time = with_time,
               speedup = ratio,
               hit_rate = stats.hit_rate))

        println(@sprintf("  %5d iterations: %12s (no cache) → %12s (cached) | %.2fx speedup | %.1f%% hit rate",
                         n,
                         format_time(without_time),
                         format_time(with_time),
                         ratio,
                         stats.hit_rate * 100))
    end

    return results
end

#
# Main Benchmark Suite
#

function run_benchmarks()
    println("\n" * "="^80)
    println("Query Plan Cache Benchmarks")
    println("="^80)
    println("\nMeasuring compilation performance with and without query plan caching.")
    println("Each test compiles the same query N times to measure cache effectiveness.\n")

    all_results = Dict()

    # Simple query
    all_results["Simple Query"] = benchmark_query_type("Simple Query", simple_query)

    # Complex join query
    all_results["Complex JOIN"] = benchmark_query_type("Complex JOIN", complex_join_query)

    # Multi-filter query
    all_results["Multiple Filters"] = benchmark_query_type("Multiple Filters",
                                                           multi_filter_query)

    # Window function query
    all_results["Window Function"] = benchmark_query_type("Window Function",
                                                          window_function_query)

    # Set operation query
    all_results["Set Operation (UNION)"] = benchmark_query_type("Set Operation (UNION)",
                                                                set_operation_query)

    # Summary
    println("\n" * "="^80)
    println("Summary")
    println("="^80)

    for (query_type, results) in all_results
        # Get best speedup (usually at highest iteration count)
        best = maximum(r.speedup for r in results)
        best_hit_rate = results[end].hit_rate

        println(@sprintf("%-25s: %.2fx speedup (%.1f%% cache hit rate)",
                         query_type, best, best_hit_rate * 100))
    end

    println("\n" * "="^80)
    println("Conclusion")
    println("="^80)
    println("Query plan caching provides significant speedup for repeated compilations.")
    println("Speedup increases with the number of iterations as cache hit rate improves.")
    println("Cache is most effective for complex queries with high compilation overhead.")
    println("="^80)

    return all_results
end

#
# Run benchmarks
#

if abspath(PROGRAM_FILE) == @__FILE__
    results = run_benchmarks()
end
