#!/usr/bin/env julia

# Test columnar-via-rows for JOIN query (1667 rows)

include("setup.jl")

using BenchmarkTools
using SQLSketch: fetch_all_columnar

println("=" ^ 80)
println("Test: Columnar-via-rows for JOIN Query (1667 rows)")
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

# JOIN query
q_join = from(:users) |>
         inner_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
         where(col(:posts, :published) == literal(true)) |>
         select(NamedTuple,
                col(:users, :name),
                col(:posts, :title),
                col(:posts, :created_at))

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
        values = ntuple(ncols) do col_idx
            col_name = column_names[col_idx]
            cols[col_name][row_idx]
        end
        rows[row_idx] = NamedTuple{column_names}(values)
    end

    return rows
end

println("=" ^ 80)
println("Current approach (direct LibPQ)")
println("=" ^ 80)
println()

result_current = @benchmark fetch_all($conn, $dialect, $registry, $q_join)
println("  Median time: $(BenchmarkTools.prettytime(median(result_current).time))")
println("  Memory:      $(BenchmarkTools.prettymemory(median(result_current).memory))")
println("  Allocations: $(median(result_current).allocs)")
println()

println("=" ^ 80)
println("New approach (columnar → row)")
println("=" ^ 80)
println()

result_via_columnar = @benchmark begin
    columnar = fetch_all_columnar($conn, $dialect, $registry, $q_join)
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
println("Results")
println("=" ^ 80)
println()
println("  Speedup:          **$(round(speedup, digits=1))x faster**")
println("  Memory reduction: $(round(memory_reduction, digits=1))%")
println("  Alloc reduction:  $(round(alloc_reduction, digits=1))%")
println()

# Cleanup
cleanup_postgresql_db(conn)
Base.close(conn)

println("✓ Test completed!")
