# SQLSketch vs Raw SQL Comparison Benchmarks
# Compares the performance of SQLSketch queries vs equivalent raw SQL

include("setup.jl")

using BenchmarkTools

# Setup database
println("Setting up test database...")
driver = SQLSketch.SQLiteDriver()
conn = connect(driver, ":memory:")
dialect = SQLSketch.SQLiteDialect()
registry = SQLSketch.CodecRegistry()

# Populate database (conn.db is the underlying SQLite.DB)
db_handle = conn.db  # For raw SQL benchmarks
populate_db(db_handle)

# Get queries
sqlsketch_queries = get_sample_queries()
raw_sql_queries = get_raw_sql_queries()

# Pre-build SQLSketch query ASTs
query_asts = Dict(name => builder() for (name, builder) in sqlsketch_queries)

# Pre-build raw SQL prepared statements (fair comparison with SQLSketch caching)
raw_stmts = Dict(name => SQLite.Stmt(db_handle, sql) for (name, sql) in raw_sql_queries)

# Benchmark suite
suite = BenchmarkGroup()
suite["sqlsketch"] = BenchmarkGroup()
suite["raw_sql"] = BenchmarkGroup()
suite["raw_sql_nocache"] = BenchmarkGroup()

# Benchmark SQLSketch queries (with prepared statement caching)
for (name, q) in query_asts
    suite["sqlsketch"][string(name)] = @benchmarkable fetch_all($conn, $dialect, $registry,
                                                                $q)
end

# Benchmark raw SQL queries (WITH prepared statement caching - fair comparison)
for (name, stmt) in raw_stmts
    suite["raw_sql"][string(name)] = @benchmarkable begin
        rows = SQLite.DBInterface.execute($stmt) |> collect
        rows
    end
end

# Benchmark raw SQL queries (WITHOUT caching - shows statement preparation overhead)
for (name, sql) in raw_sql_queries
    suite["raw_sql_nocache"][string(name)] = @benchmarkable begin
        stmt = SQLite.Stmt($db_handle, $sql)
        rows = SQLite.DBInterface.execute(stmt) |> collect
        rows
    end
end

# Run benchmarks
println("=" ^ 80)
println("SQLSketch vs Raw SQL Comparison")
println("=" ^ 80)
println()

results = run(suite; verbose = true)

# Calculate and display comparison
println()
println("Performance Comparison (with Prepared Statement Caching):")
println("=" ^ 80)
println()

for name in keys(raw_sql_queries)
    name_str = string(name)
    if haskey(results["sqlsketch"], name_str) && haskey(results["raw_sql"], name_str)
        sqlsketch_time = median(results["sqlsketch"][name_str]).time
        raw_sql_time = median(results["raw_sql"][name_str]).time
        raw_sql_nocache_time = median(results["raw_sql_nocache"][name_str]).time
        overhead = ((sqlsketch_time - raw_sql_time) / raw_sql_time) * 100
        cache_benefit = ((raw_sql_nocache_time - raw_sql_time) / raw_sql_nocache_time) * 100

        println("$name_str:")
        println("  SQLSketch:           $(BenchmarkTools.prettytime(sqlsketch_time))")
        println("  Raw SQL (cached):    $(BenchmarkTools.prettytime(raw_sql_time))")
        println("  Raw SQL (no cache):  $(BenchmarkTools.prettytime(raw_sql_nocache_time))")
        println("  Overhead vs cached:  $(round(overhead, digits=2))%")
        println("  Cache benefit:       $(round(cache_benefit, digits=2))%")
        println()

        # Add to global suite (if running from run_all.jl)
        if @isdefined(SUITE)
            push!(SUITE, "Comparison (SQLSketch) - $name_str",
                  results["sqlsketch"][name_str])
            push!(SUITE, "Comparison (Raw SQL Cached) - $name_str",
                  results["raw_sql"][name_str])
            push!(SUITE, "Comparison (Raw SQL No Cache) - $name_str",
                  results["raw_sql_nocache"][name_str])
        end
    end
end

# Summary statistics
println("Summary Statistics:")
println("-" ^ 80)

sqlsketch_times = Float64[]
raw_sql_times = Float64[]

for name in keys(raw_sql_queries)
    name_str = string(name)
    if haskey(results["sqlsketch"], name_str) && haskey(results["raw_sql"], name_str)
        push!(sqlsketch_times, median(results["sqlsketch"][name_str]).time)
        push!(raw_sql_times, median(results["raw_sql"][name_str]).time)
    end
end

if !isempty(sqlsketch_times)
    avg_overhead = mean(((sqlsketch_times .- raw_sql_times) ./ raw_sql_times) .* 100)
    min_overhead = minimum(((sqlsketch_times .- raw_sql_times) ./ raw_sql_times) .* 100)
    max_overhead = maximum(((sqlsketch_times .- raw_sql_times) ./ raw_sql_times) .* 100)

    println("Average overhead: $(round(avg_overhead, digits=2))%")
    println("Min overhead:     $(round(min_overhead, digits=2))%")
    println("Max overhead:     $(round(max_overhead, digits=2))%")
end

# Cleanup
# Connection is closed automatically
