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

using .Core: Dialect, Capability, CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW,
             CAP_LATERAL, CAP_BULK_COPY, CAP_SAVEPOINT, CAP_ADVISORY_LOCK
using .Core: Query, From, Where, Select, Join, OrderBy, Limit, Offset, Distinct, GroupBy,
             Having, InsertInto, InsertValues, Update, UpdateSet, UpdateWhere,
             DeleteFrom, DeleteWhere, Returning, CTE, With
using .Core: SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall, PlaceholderField,
             BetweenOp, InOp, Cast, Subquery, CaseExpr
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
# Placeholder Resolution
#

"""
    resolve_placeholders(expr::SQLExpr, table::Symbol) -> SQLExpr

Resolve PlaceholderField expressions to ColRef expressions using the given table name.

# Example

```julia
resolve_placeholders(PlaceholderField(:email), :users)
# → ColRef(:users, :email)
```
"""
function resolve_placeholders(expr::PlaceholderField, table::Symbol)::ColRef
    return ColRef(table, expr.column)
end

function resolve_placeholders(expr::ColRef, table::Symbol)::ColRef
    return expr
end

function resolve_placeholders(expr::Literal, table::Symbol)::Literal
    return expr
end

function resolve_placeholders(expr::Param, table::Symbol)::Param
    return expr
end

function resolve_placeholders(expr::BinaryOp, table::Symbol)::BinaryOp
    left = resolve_placeholders(expr.left, table)
    right = resolve_placeholders(expr.right, table)
    return BinaryOp(expr.op, left, right)
end

function resolve_placeholders(expr::UnaryOp, table::Symbol)::UnaryOp
    resolved_expr = resolve_placeholders(expr.expr, table)
    return UnaryOp(expr.op, resolved_expr)
end

function resolve_placeholders(expr::FuncCall, table::Symbol)::FuncCall
    resolved_args = [resolve_placeholders(arg, table) for arg in expr.args]
    return FuncCall(expr.name, resolved_args)
end

function resolve_placeholders(expr::BetweenOp, table::Symbol)::BetweenOp
    resolved_expr = resolve_placeholders(expr.expr, table)
    resolved_low = resolve_placeholders(expr.low, table)
    resolved_high = resolve_placeholders(expr.high, table)
    return BetweenOp(resolved_expr, resolved_low, resolved_high, expr.negated)
end

function resolve_placeholders(expr::InOp, table::Symbol)::InOp
    resolved_expr = resolve_placeholders(expr.expr, table)
    resolved_values = [resolve_placeholders(v, table) for v in expr.values]
    return InOp(resolved_expr, resolved_values, expr.negated)
end

function resolve_placeholders(expr::Cast, table::Symbol)::Cast
    resolved_expr = resolve_placeholders(expr.expr, table)
    return Cast(resolved_expr, expr.target_type)
end

function resolve_placeholders(expr::Subquery, table::Symbol)::Subquery
    # Subqueries are self-contained, don't resolve placeholders within them
    # They will be resolved when the subquery itself is compiled
    return expr
end

function resolve_placeholders(expr::CaseExpr, table::Symbol)::CaseExpr
    # Resolve placeholders in all WHEN conditions and results
    resolved_whens = Tuple{SQLExpr, SQLExpr}[(resolve_placeholders(cond, table),
                                              resolve_placeholders(result, table))
                                             for (cond, result) in expr.whens]

    # Resolve placeholders in ELSE clause if present
    resolved_else = if expr.else_expr === nothing
        nothing
    else
        resolve_placeholders(expr.else_expr, table)
    end

    return CaseExpr(resolved_whens, resolved_else)
end

"""
    contains_placeholder(expr::SQLExpr) -> Bool

Check if an expression contains any PlaceholderField nodes.
"""
function contains_placeholder(expr::PlaceholderField)::Bool
    return true
end

function contains_placeholder(expr::ColRef)::Bool
    return false
end

function contains_placeholder(expr::Literal)::Bool
    return false
end

function contains_placeholder(expr::Param)::Bool
    return false
end

function contains_placeholder(expr::BinaryOp)::Bool
    return contains_placeholder(expr.left) || contains_placeholder(expr.right)
end

function contains_placeholder(expr::UnaryOp)::Bool
    return contains_placeholder(expr.expr)
end

function contains_placeholder(expr::FuncCall)::Bool
    return any(contains_placeholder(arg) for arg in expr.args)
end

function contains_placeholder(expr::BetweenOp)::Bool
    return contains_placeholder(expr.expr) || contains_placeholder(expr.low) ||
           contains_placeholder(expr.high)
end

function contains_placeholder(expr::InOp)::Bool
    return contains_placeholder(expr.expr) ||
           any(contains_placeholder(v) for v in expr.values)
end

function contains_placeholder(expr::Cast)::Bool
    return contains_placeholder(expr.expr)
end

function contains_placeholder(expr::Subquery)::Bool
    # Subqueries are self-contained
    return false
end

function contains_placeholder(expr::CaseExpr)::Bool
    # Check if any WHEN condition or result contains placeholders
    for (cond, result) in expr.whens
        if contains_placeholder(cond) || contains_placeholder(result)
            return true
        end
    end

    # Check ELSE clause if present
    if expr.else_expr !== nothing && contains_placeholder(expr.else_expr)
        return true
    end

    return false
end

"""
    get_primary_table(query::Query) -> Union{Symbol, Nothing}

Extract the primary table name from a query for placeholder resolution.
Returns `nothing` if the query has multiple tables (JOINs).
"""
function get_primary_table(query::From)::Symbol
    return query.table
end

function get_primary_table(query::Where)::Union{Symbol, Nothing}
    return get_primary_table(query.source)
end

function get_primary_table(query::Select)::Union{Symbol, Nothing}
    return get_primary_table(query.source)
end

function get_primary_table(query::OrderBy)::Union{Symbol, Nothing}
    return get_primary_table(query.source)
end

function get_primary_table(query::Limit)::Union{Symbol, Nothing}
    return get_primary_table(query.source)
end

function get_primary_table(query::Offset)::Union{Symbol, Nothing}
    return get_primary_table(query.source)
end

function get_primary_table(query::Distinct)::Union{Symbol, Nothing}
    return get_primary_table(query.source)
end

function get_primary_table(query::GroupBy)::Union{Symbol, Nothing}
    return get_primary_table(query.source)
end

function get_primary_table(query::Having)::Union{Symbol, Nothing}
    return get_primary_table(query.source)
end

function get_primary_table(query::Join)::Nothing
    # JOINs have multiple tables - placeholders are ambiguous
    return nothing
end

# DML query types
function get_primary_table(query::InsertInto)::Symbol
    return query.table
end

function get_primary_table(query::InsertValues)::Symbol
    return get_primary_table(query.source)
end

function get_primary_table(query::Update)::Symbol
    return query.table
end

function get_primary_table(query::UpdateSet)::Symbol
    return get_primary_table(query.source)
end

function get_primary_table(query::UpdateWhere)::Symbol
    return get_primary_table(query.source)
end

function get_primary_table(query::DeleteFrom)::Symbol
    return query.table
end

function get_primary_table(query::DeleteWhere)::Symbol
    return get_primary_table(query.source)
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

function compile_expr(dialect::SQLiteDialect, expr::BinaryOp,
                      params::Vector{Symbol})::String
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
    elseif expr.op == :LIKE
        "LIKE"
    elseif expr.op == :NOT_LIKE
        "NOT LIKE"
    elseif expr.op == :ILIKE
        # SQLite doesn't have native ILIKE, emulate with UPPER
        # Return special marker to handle differently
        return "(UPPER($left_sql) LIKE UPPER($right_sql))"
    elseif expr.op == :NOT_ILIKE
        # SQLite doesn't have native NOT ILIKE, emulate with UPPER
        return "(UPPER($left_sql) NOT LIKE UPPER($right_sql))"
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
    elseif expr.op == :EXISTS
        return "EXISTS $operand_sql"
    elseif expr.op == :NOT_EXISTS
        return "NOT EXISTS $operand_sql"
    else
        error("Unsupported unary operator: $(expr.op)")
    end
end

function compile_expr(dialect::SQLiteDialect, expr::FuncCall,
                      params::Vector{Symbol})::String
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

function compile_expr(dialect::SQLiteDialect, expr::PlaceholderField,
                      params::Vector{Symbol})::String
    error("PlaceholderField($(expr.column)) must be resolved to ColRef before compilation. " *
          "This is a bug in the query resolution logic.")
end

function compile_expr(dialect::SQLiteDialect, expr::BetweenOp,
                      params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, expr.expr, params)
    low_sql = compile_expr(dialect, expr.low, params)
    high_sql = compile_expr(dialect, expr.high, params)

    if expr.negated
        return "($expr_sql NOT BETWEEN $low_sql AND $high_sql)"
    else
        return "($expr_sql BETWEEN $low_sql AND $high_sql)"
    end
end

function compile_expr(dialect::SQLiteDialect, expr::InOp,
                      params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, expr.expr, params)

    # Compile each value in the list
    values_sql = [compile_expr(dialect, v, params) for v in expr.values]
    values_list = Base.join(values_sql, ", ")

    if expr.negated
        return "($expr_sql NOT IN ($values_list))"
    else
        return "($expr_sql IN ($values_list))"
    end
end

function compile_expr(dialect::SQLiteDialect, expr::Cast,
                      params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, expr.expr, params)
    target_type = uppercase(string(expr.target_type))
    return "CAST($expr_sql AS $target_type)"
end

function compile_expr(dialect::SQLiteDialect, expr::Subquery,
                      params::Vector{Symbol})::String
    # Compile the subquery
    subquery_sql, subquery_params = compile(dialect, expr.query)

    # Append subquery parameters to the main params list
    append!(params, subquery_params)

    # Return the subquery wrapped in parentheses
    return "($subquery_sql)"
end

function compile_expr(dialect::SQLiteDialect, expr::CaseExpr,
                      params::Vector{Symbol})::String
    # Start CASE
    parts = ["CASE"]

    # Compile WHEN clauses
    for (condition, result) in expr.whens
        condition_sql = compile_expr(dialect, condition, params)
        result_sql = compile_expr(dialect, result, params)
        push!(parts, "WHEN $condition_sql THEN $result_sql")
    end

    # Compile ELSE clause if present
    if expr.else_expr !== nothing
        else_sql = compile_expr(dialect, expr.else_expr, params)
        push!(parts, "ELSE $else_sql")
    end

    # End CASE
    push!(parts, "END")

    return Base.join(parts, " ")
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
function compile(dialect::SQLiteDialect,
                 query::From{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "SELECT * FROM $table"
    return (sql, params)
end

function compile(dialect::SQLiteDialect,
                 query::Where{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Resolve placeholders in the WHERE condition
    table = get_primary_table(query)
    if table === nothing
        # Multi-table query (JOIN) - check if placeholders exist
        if contains_placeholder(query.condition)
            error("Cannot use placeholder syntax (_.) in multi-table queries. " *
                  "Use explicit col(table, column) instead.")
        end
        resolved_condition = query.condition
    else
        resolved_condition = resolve_placeholders(query.condition, table)
    end

    # Compile the WHERE condition
    condition_sql = compile_expr(dialect, resolved_condition, params)

    # Append WHERE clause
    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

function compile(dialect::SQLiteDialect,
                 query::Select{OutT})::Tuple{String, Vector{Symbol}} where {OutT}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Compile the SELECT fields
    if isempty(query.fields)
        # SELECT with no fields - keep SELECT *
        return (source_sql, params)
    end

    # Resolve placeholders in SELECT fields
    table = get_primary_table(query)
    resolved_fields = if table === nothing
        # Multi-table query - check for placeholders
        if any(contains_placeholder(f) for f in query.fields)
            error("Cannot use placeholder syntax (_.) in multi-table queries. " *
                  "Use explicit col(table, column) instead.")
        end
        query.fields
    else
        [resolve_placeholders(f, table) for f in query.fields]
    end

    fields_sql = [compile_expr(dialect, field, params) for field in resolved_fields]
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

function compile(dialect::SQLiteDialect,
                 query::Join{T})::Tuple{String, Vector{Symbol}} where {T}
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

function compile(dialect::SQLiteDialect,
                 query::OrderBy{T})::Tuple{String, Vector{Symbol}} where {T}
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

function compile(dialect::SQLiteDialect,
                 query::Limit{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Append LIMIT clause
    sql = "$source_sql LIMIT $(query.n)"
    return (sql, params)
end

function compile(dialect::SQLiteDialect,
                 query::Offset{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Append OFFSET clause
    sql = "$source_sql OFFSET $(query.n)"
    return (sql, params)
end

function compile(dialect::SQLiteDialect,
                 query::Distinct{T})::Tuple{String, Vector{Symbol}} where {T}
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

function compile(dialect::SQLiteDialect,
                 query::GroupBy{T})::Tuple{String, Vector{Symbol}} where {T}
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

function compile(dialect::SQLiteDialect,
                 query::Having{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the source query first
    source_sql, params = compile(dialect, query.source)

    # Compile the HAVING condition
    condition_sql = compile_expr(dialect, query.condition, params)

    # Append HAVING clause
    sql = "$source_sql HAVING $condition_sql"
    return (sql, params)
end

#
# DML Compilation (INSERT, UPDATE, DELETE)
#

"""
    compile(dialect::SQLiteDialect, query::InsertInto{T}) -> (String, Vector{Symbol})

Compile an INSERT INTO statement.

# Example

```julia
q = insert_into(:users, [:name, :email])
sql, params = compile(SQLiteDialect(), q)
# sql → "INSERT INTO `users` (`name`, `email`) VALUES"
# Note: Incomplete without VALUES clause
```
"""
function compile(dialect::SQLiteDialect,
                 query::InsertInto{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    columns = [quote_identifier(dialect, col) for col in query.columns]
    columns_str = Base.join(columns, ", ")
    sql = "INSERT INTO $table ($columns_str)"
    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, query::InsertValues{T}) -> (String, Vector{Symbol})

Compile an INSERT...VALUES statement.

# Example

```julia
q = insert_into(:users, [:name, :email]) |>
    values([[literal("Alice"), literal("alice@example.com")]])
sql, params = compile(SQLiteDialect(), q)
# sql → "INSERT INTO `users` (`name`, `email`) VALUES ('Alice', 'alice@example.com')"
```
"""
function compile(dialect::SQLiteDialect,
                 query::InsertValues{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the INSERT INTO part
    source_sql, params = compile(dialect, query.source)

    # Compile each row
    rows_sql = String[]
    for row in query.rows
        values_sql = [compile_expr(dialect, expr, params) for expr in row]
        values_str = Base.join(values_sql, ", ")
        push!(rows_sql, "($values_str)")
    end

    rows_str = Base.join(rows_sql, ", ")
    sql = "$source_sql VALUES $rows_str"
    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, query::Update{T}) -> (String, Vector{Symbol})

Compile an UPDATE statement (without SET clause).

# Example

```julia
q = update(:users)
sql, params = compile(SQLiteDialect(), q)
# sql → "UPDATE `users`"
# Note: Incomplete without SET clause
```
"""
function compile(dialect::SQLiteDialect,
                 query::Update{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "UPDATE $table"
    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, query::UpdateSet{T}) -> (String, Vector{Symbol})

Compile an UPDATE...SET statement.

# Example

```julia
q = update(:users) |>
    set(:name => param(String, :name), :email => param(String, :email))
sql, params = compile(SQLiteDialect(), q)
# sql → "UPDATE `users` SET `name` = ?, `email` = ?"
# params → [:name, :email]
```
"""
function compile(dialect::SQLiteDialect,
                 query::UpdateSet{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the UPDATE part
    source_sql, params = compile(dialect, query.source)

    # Compile SET assignments
    assignments_sql = String[]
    for (column, expr) in query.assignments
        column_name = quote_identifier(dialect, column)
        value_sql = compile_expr(dialect, expr, params)
        push!(assignments_sql, "$column_name = $value_sql")
    end

    assignments_str = Base.join(assignments_sql, ", ")
    sql = "$source_sql SET $assignments_str"
    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, query::UpdateWhere{T}) -> (String, Vector{Symbol})

Compile an UPDATE...SET...WHERE statement.

# Example

```julia
q = update(:users) |>
    set(:name => param(String, :name)) |>
    where(col(:users, :id) == param(Int, :id))
sql, params = compile(SQLiteDialect(), q)
# sql → "UPDATE `users` SET `name` = ? WHERE (`users`.`id` = ?)"
# params → [:name, :id]
```
"""
function compile(dialect::SQLiteDialect,
                 query::UpdateWhere{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the UPDATE...SET part
    source_sql, params = compile(dialect, query.source)

    # Resolve placeholders in WHERE condition
    table = get_primary_table(query.source)
    resolved_condition = resolve_placeholders(query.condition, table)

    # Compile the WHERE condition
    condition_sql = compile_expr(dialect, resolved_condition, params)

    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, query::DeleteFrom{T}) -> (String, Vector{Symbol})

Compile a DELETE FROM statement (without WHERE clause).

# Example

```julia
q = delete_from(:users)
sql, params = compile(SQLiteDialect(), q)
# sql → "DELETE FROM `users`"
# WARNING: This will delete all rows!
```
"""
function compile(dialect::SQLiteDialect,
                 query::DeleteFrom{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "DELETE FROM $table"
    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, query::DeleteWhere{T}) -> (String, Vector{Symbol})

Compile a DELETE FROM...WHERE statement.

# Example

```julia
q = delete_from(:users) |>
    where(col(:users, :id) == param(Int, :id))
sql, params = compile(SQLiteDialect(), q)
# sql → "DELETE FROM `users` WHERE (`users`.`id` = ?)"
# params → [:id]
```
"""
function compile(dialect::SQLiteDialect,
                 query::DeleteWhere{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the DELETE FROM part
    source_sql, params = compile(dialect, query.source)

    # Resolve placeholders in WHERE condition
    table = get_primary_table(query.source)
    resolved_condition = resolve_placeholders(query.condition, table)

    # Compile the WHERE condition
    condition_sql = compile_expr(dialect, resolved_condition, params)

    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

#
# RETURNING Clause Compilation
#

"""
    compile(dialect::SQLiteDialect, query::Returning{OutT}) -> (String, Vector{Symbol})

Compile a RETURNING clause for DML operations.

The RETURNING clause allows INSERT, UPDATE, and DELETE operations to return
values from the affected rows, similar to a SELECT query.

# SQLite Support

Requires SQLite 3.35+ (released March 2021)

# Example

```julia
q = insert_into(:users, [:email]) |>
    values([[literal("test@example.com")]]) |>
    returning(NamedTuple, p_.id, p_.email)

sql, params = compile(dialect, q)
# → ("INSERT INTO `users` (`email`) VALUES ('test@example.com') RETURNING `users`.`id`, `users`.`email`", [])
```
"""
function compile(dialect::SQLiteDialect,
                 query::Returning{OutT})::Tuple{String, Vector{Symbol}} where {OutT}
    # Compile the source DML query (INSERT, UPDATE, or DELETE)
    source_sql, params = compile(dialect, query.source)

    # Determine the primary table for placeholder resolution
    table = get_primary_table(query.source)

    # Resolve placeholders in RETURNING fields
    resolved_fields = if table === nothing
        # Multi-table query - check for placeholders
        if any(contains_placeholder(f) for f in query.fields)
            error("Cannot use placeholder syntax (p_) in RETURNING clause for multi-table queries. " *
                  "Use explicit col(table, column) instead.")
        end
        query.fields
    else
        [resolve_placeholders(f, table) for f in query.fields]
    end

    # Compile each RETURNING field
    fields_sql = [compile_expr(dialect, field, params) for field in resolved_fields]
    fields_str = Base.join(fields_sql, ", ")

    # Append RETURNING clause to the DML statement
    sql = "$source_sql RETURNING $fields_str"

    return (sql, params)
end

#
# CTE (Common Table Expressions) Compilation
#

function compile(dialect::SQLiteDialect,
                 query::With{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]

    # Compile all CTEs
    cte_parts = String[]
    for cte_def in query.ctes
        cte_name = quote_identifier(dialect, cte_def.name)

        # Add column aliases if specified
        if !isempty(cte_def.columns)
            column_list = Base.join([quote_identifier(dialect, col)
                                     for col in cte_def.columns],
                                    ", ")
            cte_name = "$cte_name ($column_list)"
        end

        # Compile the CTE query
        cte_sql, cte_params = compile(dialect, cte_def.query)
        append!(params, cte_params)

        push!(cte_parts, "$cte_name AS ($cte_sql)")
    end

    # Compile the main query
    main_sql, main_params = compile(dialect, query.main_query)
    append!(params, main_params)

    # Combine: WITH cte1 AS (...), cte2 AS (...) main_query
    cte_clause = Base.join(cte_parts, ", ")
    sql = "WITH $cte_clause $main_sql"

    return (sql, params)
end
