#
# Performance Profiling Tools
#
# Provides performance analysis and query optimization tools:
# - Detailed query timing (@timed macro)
# - EXPLAIN QUERY PLAN integration
# - Index usage analysis
# - Performance best practices
#

import ..Query, ..Dialect, ..Connection, ..compile, ..execute_sql

export @timed_query, QueryTiming
export analyze_query, analyze_explain

"""
    QueryTiming

Detailed timing breakdown for query execution.

# Fields
- `compile_time::Float64`: Time spent compiling SQL (seconds)
- `execute_time::Float64`: Time spent executing SQL (seconds)
- `decode_time::Float64`: Time spent decoding results (seconds)
- `total_time::Float64`: Total execution time (seconds)
- `row_count::Int`: Number of rows returned
"""
struct QueryTiming
    compile_time::Float64
    execute_time::Float64
    decode_time::Float64
    total_time::Float64
    row_count::Int
end

"""
    timed_query(f::Function, dialect::Dialect, query::Query) -> (result, QueryTiming)

Execute a query with detailed timing breakdown.

# Arguments
- `f::Function`: Execution function (conn, sql, params) -> result
- `dialect::Dialect`: SQL dialect
- `query::Query`: Query to execute

# Returns
- `(result, timing::QueryTiming)`: Query result and timing breakdown

# Example

```julia
result, timing = timed_query(dialect, query) do conn, sql, params
    execute_sql(conn, sql, params)
end

println("Compile: \$(timing.compile_time * 1000)ms")
println("Execute: \$(timing.execute_time * 1000)ms")
println("Total: \$(timing.total_time * 1000)ms")
```
"""
function timed_query(f::Function, dialect::Dialect, query::Query)::Tuple{Any,QueryTiming}
    # Compile timing
    compile_start = time()
    sql, params = compile(dialect, query)
    compile_time = time() - compile_start

    # Execute timing
    execute_start = time()
    result = f(sql, params)
    execute_time = time() - execute_start

    # Decode timing (approximation - actual decoding happens in map_row)
    decode_time = 0.0

    # Total time
    total_time = compile_time + execute_time + decode_time

    # Row count (attempt to get from result)
    row_count = try
        length(collect(result))
    catch
        0
    end

    timing = QueryTiming(compile_time, execute_time, decode_time, total_time, row_count)

    return (result, timing)
end

"""
    @timed_query expr

Macro for timing query execution with detailed breakdown.

Wraps a query execution expression and returns both the result and timing information.

# Example

```julia
result, timing = @timed_query fetch_all(conn, query)
println("Total time: \$(timing.total_time * 1000)ms")
println("Rows: \$(timing.row_count)")
```
"""
macro timed_query(expr)
    quote
        start_time = time()
        result = $(esc(expr))
        total_time = time() - start_time

        row_count = try
            length(result)
        catch
            0
        end

        timing = QueryTiming(
            0.0,  # compile time (not measured in macro)
            total_time,  # execute time
            0.0,  # decode time (not measured separately)
            total_time,
            row_count
        )

        (result, timing)
    end
end

"""
    ExplainAnalysis

Results from EXPLAIN QUERY PLAN analysis.

# Fields
- `plan::String`: Full EXPLAIN output
- `uses_index::Bool`: Whether the query uses an index
- `has_full_scan::Bool`: Whether the query has a full table scan
- `warnings::Vector{String}`: Performance warnings
"""
struct ExplainAnalysis
    plan::String
    uses_index::Bool
    has_full_scan::Bool
    warnings::Vector{String}
end

"""
    analyze_query(conn::Connection, dialect::Dialect, query::Query) -> ExplainAnalysis

Analyze query performance using EXPLAIN QUERY PLAN.

# Arguments
- `conn::Connection`: Database connection
- `dialect::Dialect`: SQL dialect
- `query::Query`: Query to analyze

# Returns
- `ExplainAnalysis`: Query plan analysis with performance warnings

# Example

```julia
analysis = analyze_query(conn, dialect, query)
println(analysis.plan)

if analysis.has_full_scan
    println("Warning: Query performs full table scan")
end

for warning in analysis.warnings
    println("⚠️  \$warning")
end
```
"""
function analyze_query(
    conn::Connection,
    dialect::Dialect,
    query::Query
)::ExplainAnalysis
    # Compile query
    sql, params = compile(dialect, query)

    # Get EXPLAIN QUERY PLAN
    explain_sql = "EXPLAIN QUERY PLAN " * sql
    result = execute_sql(conn, explain_sql, params)

    # Parse EXPLAIN output
    plan_lines = String[]
    for row in result
        # Try different column names (SQLite vs PostgreSQL)
        line = try
            row.QUERY_PLAN
        catch
            try
                string(row)
            catch
                "Unknown plan format"
            end
        end
        push!(plan_lines, line)
    end

    plan = Base.join(plan_lines, "\n")

    # Analyze plan for common issues
    uses_index = contains_index_usage(plan)
    has_full_scan = contains_full_scan(plan)
    warnings = generate_warnings(plan, uses_index, has_full_scan)

    return ExplainAnalysis(plan, uses_index, has_full_scan, warnings)
end

"""
    contains_index_usage(plan::String) -> Bool

Check if the query plan uses an index.
"""
function contains_index_usage(plan::String)::Bool
    plan_lower = lowercase(plan)
    return contains(plan_lower, "index") ||
           contains(plan_lower, "using index") ||
           contains(plan_lower, "index scan")
end

"""
    contains_full_scan(plan::String) -> Bool

Check if the query plan has a full table scan.
"""
function contains_full_scan(plan::String)::Bool
    plan_lower = lowercase(plan)
    return contains(plan_lower, "scan table") ||
           contains(plan_lower, "seq scan") ||
           contains(plan_lower, "table scan")
end

"""
    generate_warnings(plan::String, uses_index::Bool, has_full_scan::Bool) -> Vector{String}

Generate performance warnings based on query plan analysis.
"""
function generate_warnings(
    plan::String,
    uses_index::Bool,
    has_full_scan::Bool
)::Vector{String}
    warnings = String[]

    if has_full_scan && !uses_index
        push!(
            warnings,
            "Full table scan detected. Consider adding an index on filter columns."
        )
    end

    if contains(lowercase(plan), "temp")
        push!(
            warnings,
            "Temporary table/b-tree created. Query may benefit from optimization."
        )
    end

    return warnings
end

"""
    analyze_explain(explain_output::String) -> Dict{Symbol, Any}

Parse EXPLAIN output into structured information.

# Arguments
- `explain_output::String`: Raw EXPLAIN output

# Returns
- `Dict{Symbol, Any}`: Parsed explain information with keys:
  - `:uses_index` - Whether an index is used
  - `:scan_type` - Type of scan (index, table, etc.)
  - `:warnings` - List of performance warnings

# Example

```julia
info = analyze_explain(explain_output)
if info[:uses_index]
    println("✓ Query uses index")
else
    println("⚠️  Query does not use index")
end
```
"""
function analyze_explain(explain_output::String)::Dict{Symbol,Any}
    uses_index = contains_index_usage(explain_output)
    has_full_scan = contains_full_scan(explain_output)

    scan_type = if uses_index
        :index_scan
    elseif has_full_scan
        :table_scan
    else
        :unknown
    end

    warnings = generate_warnings(explain_output, uses_index, has_full_scan)

    return Dict{Symbol,Any}(
        :uses_index => uses_index,
        :scan_type => scan_type,
        :has_full_scan => has_full_scan,
        :warnings => warnings
    )
end
