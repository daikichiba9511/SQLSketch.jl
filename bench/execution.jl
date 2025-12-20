# Query Execution Benchmarks
# Measures the end-to-end performance of query execution

include("setup.jl")

using BenchmarkTools

# Setup database
println("Setting up test database...")
driver = SQLSketch.SQLiteDriver()
conn = connect(driver, ":memory:")
dialect = SQLSketch.SQLiteDialect()
registry = SQLSketch.CodecRegistry()

# Populate database (conn.db is the underlying SQLite.DB)
populate_db(conn.db)

# Benchmark suite for query execution
suite = BenchmarkGroup()

queries = get_sample_queries()

# Pre-build queries
query_asts = Dict(name => builder() for (name, builder) in queries)

# Benchmark execution for each query type
for (name, q) in query_asts
    suite[string(name)] = @benchmarkable fetch_all($conn, $dialect, $registry, $q)
end

# Run benchmarks
println("=" ^ 80)
println("Query Execution Benchmarks")
println("=" ^ 80)
println()

results = run(suite, verbose=true)

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

# Cleanup
# Connection is closed automatically
