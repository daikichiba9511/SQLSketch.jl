"""
# SQLite Dialect

SQLite dialect implementation for SQLSketch.

This dialect generates SQLite-compatible SQL from query and expression ASTs.

## Characteristics

- Identifier quoting: backticks (`` `identifier` ``)
- Placeholder syntax: `?` (positional)
- Dynamic typing with runtime normalization
- Limited DDL capabilities compared to PostgreSQL

## Supported Capabilities

- ✓ Basic SELECT/INSERT/UPDATE/DELETE
- ✓ Window functions
- ✓ CTE (WITH clause)
- ✓ UPSERT (ON CONFLICT)
- ✓ RETURNING clause (SQLite 3.35+)
- ✗ LATERAL joins
- ✗ COPY FROM

See `docs/design.md` Section 10 for detailed design rationale.
"""

using .Core: Dialect, Capability, CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW, CAP_LATERAL, CAP_BULK_COPY, CAP_SAVEPOINT, CAP_ADVISORY_LOCK
using .Core: Query, From, Where, Select, Join, OrderBy, Limit, Offset, Distinct, GroupBy, Having
using .Core: SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall
import .Core: compile, compile_expr, quote_identifier, placeholder, supports

"""
    SQLiteDialect(version::VersionNumber = v"3.35.0")

SQLite dialect for SQL generation.

# Fields
- `version`: SQLite version (affects capability reporting)

# Example
```julia
dialect = SQLiteDialect()
sql, params = compile(dialect, query)
```
"""
struct SQLiteDialect <: Dialect
    version::VersionNumber
end

# Default constructor uses recent SQLite version
SQLiteDialect() = SQLiteDialect(v"3.35.0")

#
# Helper Functions
#

"""
    quote_identifier(dialect::SQLiteDialect, name::Symbol) -> String

Quote an identifier using SQLite backtick syntax.

# Example
```julia
quote_identifier(SQLiteDialect(), :users) # → "`users`"
```
"""
function quote_identifier(dialect::SQLiteDialect, name::Symbol)::String
    # Escape backticks by doubling them
    name_str = string(name)
    escaped = replace(name_str, "`" => "``")
    return "`$escaped`"
end

"""
    placeholder(dialect::SQLiteDialect, idx::Int) -> String

Generate a positional parameter placeholder.

SQLite uses `?` for all positional parameters.

# Example
```julia
placeholder(SQLiteDialect(), 1) # → "?"
placeholder(SQLiteDialect(), 2) # → "?"
```
"""
function placeholder(dialect::SQLiteDialect, idx::Int)::String
    return "?"
end

"""
    supports(dialect::SQLiteDialect, cap::Capability) -> Bool

Check if SQLite supports a specific capability.

# Example
```julia
supports(SQLiteDialect(), CAP_CTE)     # → true
supports(SQLiteDialect(), CAP_LATERAL) # → false
```
"""
function supports(dialect::SQLiteDialect, cap::Capability)::Bool
    if cap == CAP_CTE
        return true
    elseif cap == CAP_RETURNING
        # RETURNING was added in SQLite 3.35.0
        return dialect.version >= v"3.35.0"
    elseif cap == CAP_UPSERT
        return true
    elseif cap == CAP_WINDOW
        return true
    elseif cap == CAP_SAVEPOINT
        return true
    elseif cap == CAP_LATERAL
        return false
    elseif cap == CAP_BULK_COPY
        return false
    elseif cap == CAP_ADVISORY_LOCK
        return false
    else
        return false
    end
end

#
# Expression Compilation
#

"""
    compile_expr(dialect::SQLiteDialect, expr::SQLExpr, params::Vector{Symbol}) -> String

Compile an expression AST into a SQL fragment.

This function is called recursively to build SQL expressions.
When a Param is encountered, its name is appended to the params vector.
"""
function compile_expr(dialect::SQLiteDialect, expr::ColRef, params::Vector{Symbol})::String
    table = quote_identifier(dialect, expr.table)
    column = quote_identifier(dialect, expr.column)
    return "$table.$column"
end

function compile_expr(dialect::SQLiteDialect, expr::Literal, params::Vector{Symbol})::String
    value = expr.value

    if value === nothing || value === missing
        return "NULL"
    elseif value isa Bool
        # SQLite uses 1/0 for boolean
        return value ? "1" : "0"
    elseif value isa Number
        return string(value)
    elseif value isa AbstractString
        # Escape single quotes by doubling them
        escaped = replace(string(value), "'" => "''")
        return "'$escaped'"
    else
        # Fallback for other types
        error("Unsupported literal type: $(typeof(value))")
    end
end

function compile_expr(dialect::SQLiteDialect, expr::Param, params::Vector{Symbol})::String
    # Add parameter name to the list
    push!(params, expr.name)
    # Return placeholder
    return placeholder(dialect, length(params))
end

function compile_expr(dialect::SQLiteDialect, expr::BinaryOp, params::Vector{Symbol})::String
    left_sql = compile_expr(dialect, expr.left, params)
    right_sql = compile_expr(dialect, expr.right, params)

    # Map operator symbols to SQL operators
    op_str = if expr.op == :(=)
        "="
    elseif expr.op == :!=
        "!="
    elseif expr.op == :<
        "<"
    elseif expr.op == :>
        ">"
    elseif expr.op == :<=
        "<="
    elseif expr.op == :>=
        ">="
    elseif expr.op == :AND
        "AND"
    elseif expr.op == :OR
        "OR"
    elseif expr.op == :+
        "+"
    elseif expr.op == :-
        "-"
    elseif expr.op == :*
        "*"
    elseif expr.op == :/
        "/"
    else
        string(expr.op)
    end

    # Add parentheses for clarity
    return "($left_sql $op_str $right_sql)"
end

function compile_expr(dialect::SQLiteDialect, expr::UnaryOp, params::Vector{Symbol})::String
    operand_sql = compile_expr(dialect, expr.expr, params)

    if expr.op == :NOT
        return "(NOT $operand_sql)"
    elseif expr.op == :IS_NULL
        return "($operand_sql IS NULL)"
    elseif expr.op == :IS_NOT_NULL
        return "($operand_sql IS NOT NULL)"
    else
        error("Unsupported unary operator: $(expr.op)")
    end
end

function compile_expr(dialect::SQLiteDialect, expr::FuncCall, params::Vector{Symbol})::String
    func_name = string(expr.name)

    if isempty(expr.args)
        # No-argument function
        return "$func_name()"
    else
        # Compile arguments
        args_sql = [compile_expr(dialect, arg, params) for arg in expr.args]
        args_str = Base.join(args_sql, ", ")
        return "$func_name($args_str)"
    end
end

#
# Query Compilation
#

"""
    compile(dialect::SQLiteDialect, query::Query) -> (String, Vector{Symbol})

Compile a Query AST into a SQL string and parameter list.

# Example
```julia
q = from(:users) |> where(col(:users, :active) == param(Bool, :active))
sql, params = compile(SQLiteDialect(), q)
# sql    → "SELECT * FROM `users` WHERE (`users`.`active` = ?)"
# params → [:active]
```
"""
function compile(dialect::SQLiteDialect, query::From{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "SELECT * FROM $table"
    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::Where{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Compile the WHERE condition
    condition_sql = compile_expr(dialect, query.condition, params)

    # Append WHERE clause
    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::Select{OutT})::Tuple{String, Vector{Symbol}} where {OutT}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Compile the SELECT fields
    if isempty(query.fields)
        # SELECT with no fields - keep SELECT *
        return (source_sql, params)
    end

    fields_sql = [compile_expr(dialect, field, params) for field in query.fields]
    fields_str = Base.join(fields_sql, ", ")

    # Replace "SELECT * FROM" with "SELECT fields FROM"
    # This is a simplification - in reality we'd need smarter SQL rewriting
    if startswith(source_sql, "SELECT * FROM")
        sql = "SELECT $fields_str FROM" * source_sql[14:end]
    else
        # Source query is more complex - wrap it as a subquery
        sql = "SELECT $fields_str FROM ($source_sql) AS sub"
    end

    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::Join{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Determine join type
    join_type = if query.kind == :inner
        "INNER JOIN"
    elseif query.kind == :left
        "LEFT JOIN"
    elseif query.kind == :right
        "RIGHT JOIN"
    elseif query.kind == :full
        "FULL OUTER JOIN"
    else
        error("Unsupported join kind: $(query.kind)")
    end

    # Quote the joined table
    table = quote_identifier(dialect, query.table)

    # Compile the ON condition
    on_sql = compile_expr(dialect, query.on, params)

    # Append JOIN clause
    sql = "$source_sql $join_type $table ON $on_sql"
    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::OrderBy{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Compile ORDER BY clauses
    orderings_sql = String[]
    for (field, desc) in query.orderings
        field_sql = compile_expr(dialect, field, params)
        ordering = desc ? "$field_sql DESC" : "$field_sql ASC"
        push!(orderings_sql, ordering)
    end

    orderings_str = Base.join(orderings_sql, ", ")
    sql = "$source_sql ORDER BY $orderings_str"
    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::Limit{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Append LIMIT clause
    sql = "$source_sql LIMIT $(query.n)"
    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::Offset{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Append OFFSET clause
    sql = "$source_sql OFFSET $(query.n)"
    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::Distinct{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Insert DISTINCT after SELECT
    if startswith(source_sql, "SELECT ")
        sql = "SELECT DISTINCT" * source_sql[7:end]
    else
        # Complex query - wrap as subquery
        sql = "SELECT DISTINCT * FROM ($source_sql) AS sub"
    end

    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::GroupBy{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Compile GROUP BY fields
    if isempty(query.fields)
        # Empty GROUP BY - just return source
        return (source_sql, params)
    end

    fields_sql = [compile_expr(dialect, field, params) for field in query.fields]
    fields_str = Base.join(fields_sql, ", ")

    sql = "$source_sql GROUP BY $fields_str"
    return (sql, params)
end

function compile(dialect::SQLiteDialect, query::Having{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Compile the HAVING condition
    condition_sql = compile_expr(dialect, query.condition, params)

    # Append HAVING clause
    sql = "$source_sql HAVING $condition_sql"
    return (sql, params)
end
