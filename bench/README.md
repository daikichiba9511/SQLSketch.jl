# SQLSketch Benchmarks

This directory contains the performance benchmarking suite for SQLSketch.jl.

## Overview

The benchmark suite measures:

1. **Query Construction** - Overhead of building Query ASTs
2. **SQL Compilation** - Time to compile ASTs to SQL strings
3. **Query Execution** - End-to-end query performance
4. **Comparison** - SQLSketch vs raw SQL performance

## Running Benchmarks

### Run All Benchmarks

```bash
julia --project=. bench/run_all.jl
```

### Run Individual Benchmarks

```bash
# Query construction only
julia --project=. bench/query_construction.jl

# SQL compilation only
julia --project=. bench/compilation.jl

# Query execution only
julia --project=. bench/execution.jl

# Comparison only
julia --project=. bench/comparison.jl
```

## Benchmark Files

- **`setup.jl`** - Common utilities and sample data
  - Database setup with 1,000 users and 5,000 posts
  - Sample query builders (simple, joins, aggregations, subqueries)
  - Raw SQL equivalents for comparison

- **`query_construction.jl`** - Measures AST building overhead
  - Simple SELECT
  - JOIN queries
  - Aggregations with GROUP BY/HAVING
  - Complex queries with multiple clauses
  - Subqueries

- **`compilation.jl`** - Measures SQL generation overhead
  - AST to SQL string conversion
  - Placeholder generation
  - Dialect-specific formatting

- **`execution.jl`** - Measures end-to-end query performance
  - Full pipeline: build → compile → execute → decode
  - Row materialization
  - Type conversion via CodecRegistry

- **`comparison.jl`** - Compares SQLSketch vs raw SQL
  - Overhead calculation
  - Side-by-side performance metrics
  - Summary statistics (avg, min, max overhead)

- **`run_all.jl`** - Master script to run all benchmarks sequentially

## Understanding Results

### Time Measurements

BenchmarkTools reports:
- **Median time** - Most representative (preferred over mean)
- **Memory** - Total allocations
- **Allocations** - Number of allocation events

### Overhead Calculation

Comparison benchmarks show overhead as:
```
Overhead = ((SQLSketch Time - Raw SQL Time) / Raw SQL Time) × 100%
```

Positive values indicate SQLSketch is slower; negative values (rare) indicate faster.

### Performance Goals

- **Query Construction**: < 1 μs for simple queries
- **SQL Compilation**: < 10 μs for complex queries
- **Execution Overhead**: < 20% vs raw SQL
- **Memory**: Minimal allocations in hot paths

## Sample Output

```
simple_select:
  Median time: 234.500 ns
  Memory:      1.09 KiB
  Allocations: 18

Performance Comparison:
simple_select:
  SQLSketch: 45.200 μs
  Raw SQL:   38.100 μs
  Overhead:  18.64%

Summary Statistics:
Average overhead: 15.23%
Min overhead:     12.45%
Max overhead:     19.87%
```

## Adding New Benchmarks

1. Add query builder to `get_sample_queries()` in `setup.jl`
2. Add raw SQL equivalent to `get_raw_sql_queries()`
3. Benchmarks will automatically include the new query

Example:
```julia
function get_sample_queries()::Dict{Symbol, Function}
    return Dict(
        # ... existing queries ...

        :my_new_query => () -> begin
            from(:users) |>
            where(col(:users, :active) == literal(1)) |>
            select(NamedTuple, col(:users, :id))
        end
    )
end
```

## Interpreting Overhead

- **< 10%**: Excellent - negligible overhead
- **10-20%**: Good - acceptable for type safety benefits
- **20-30%**: Fair - consider optimization
- **> 30%**: Poor - needs investigation

Common overhead sources:
- AST node allocations
- String building during compilation
- Type conversions in codec
- Row materialization

## Future Improvements

Planned optimizations:
1. Prepared statement caching
2. Connection pooling
3. Batch operations
4. Streaming results
5. Query plan caching

See `docs/roadmap.md` Phase 13 for details.
