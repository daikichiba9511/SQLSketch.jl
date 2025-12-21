#!/usr/bin/env julia

# Test: Can we make row-based faster by going through columnar?

include("setup.jl")

using BenchmarkTools
using SQLSketch: fetch_all_columnar

println("=" ^ 80)
println("Test: Row-based via Columnar conversion")
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

# Query
q_simple = from(:users) |>
           where(col(:users, :active) == literal(true)) |>
           select(NamedTuple, col(:users, :id), col(:users, :email))

println("=" ^ 80)
println("Approach 1: Current row-based (direct LibPQ access)")
println("=" ^ 80)
println()

result_current = @benchmark fetch_all($conn, $dialect, $registry, $q_simple)
println("  Median time: $(BenchmarkTools.prettytime(median(result_current).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_current).memory))")
println("  Allocations: $(median(result_current).allocs)")
println()

println("=" ^ 80)
println("Approach 2: Columnar → Row conversion")
println("=" ^ 80)
println()

# Conversion function
function columnar_to_rows(cols::NamedTuple)::Vector{NamedTuple}
    if isempty(cols)
        return NamedTuple[]
    end

    nrows = length(first(cols))
    column_names = keys(cols)
    ncols = length(column_names)

    rows = Vector{NamedTuple}(undef, nrows)

    for row_idx in 1:nrows
        # Build tuple of values for this row
        values = ntuple(ncols) do col_idx
            col_name = column_names[col_idx]
            cols[col_name][row_idx]
        end

        # Create NamedTuple
        rows[row_idx] = NamedTuple{column_names}(values)
    end

    return rows
end

# Benchmark columnar + conversion
result_via_columnar = @benchmark begin
    columnar = fetch_all_columnar($conn, $dialect, $registry, $q_simple)
    columnar_to_rows(columnar)
end

println("  Median time: $(BenchmarkTools.prettytime(median(result_via_columnar).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_via_columnar).memory))")
println("  Allocations: $(median(result_via_columnar).allocs)")
println()

# Compare
speedup = median(result_current).time / median(result_via_columnar).time
memory_reduction = (1 - median(result_via_columnar).memory / median(result_current).memory) *
                   100
alloc_reduction = (1 - median(result_via_columnar).allocs / median(result_current).allocs) *
                  100

println("=" ^ 80)
println("Comparison")
println("=" ^ 80)
println()
println("  Speedup:          $(round(speedup, digits=2))x")
println("  Memory reduction: $(round(memory_reduction, digits=1))%")
println("  Alloc reduction:  $(round(alloc_reduction, digits=1))%")
println()

# Verify correctness
println("=" ^ 80)
println("Correctness Check")
println("=" ^ 80)
println()

rows_direct = fetch_all(conn, dialect, registry, q_simple)
columnar = fetch_all_columnar(conn, dialect, registry, q_simple)
rows_via_columnar = columnar_to_rows(columnar)

println("  Direct rows:        $(length(rows_direct)) rows")
println("  Via columnar rows:  $(length(rows_via_columnar)) rows")
println("  First row direct:   $(rows_direct[1])")
println("  First row columnar: $(rows_via_columnar[1])")
println("  Match: $(rows_direct == rows_via_columnar)")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Test completed!")
