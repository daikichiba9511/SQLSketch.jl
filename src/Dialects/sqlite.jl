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
             DeleteFrom, DeleteWhere, Returning, CTE, With, SetUnion, SetIntersect,
             SetExcept,
             OnConflict
using .Core: SQLExpr, ColRef, Literal, Param, RawExpr, BinaryOp, UnaryOp, FuncCall,
             PlaceholderField,
             BetweenOp, InOp, Cast, Subquery, CaseExpr, WindowFunc, Over, WindowFrame
import .Core: compile, compile_expr, quote_identifier, placeholder, supports
using Dates

# Shared helper functions (resolve_placeholders, contains_placeholder, get_primary_table)
# are included in the main SQLSketch module before dialects

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

# Placeholder resolution and helper functions are in shared_helpers.jl

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
    elseif value isa Dates.DateTime
        # SQLite DATETIME format: 'YYYY-MM-DD HH:MM:SS'
        formatted = Dates.format(value, "yyyy-mm-dd HH:MM:SS")
        return "'$formatted'"
    elseif value isa Dates.Date
        # SQLite DATE format: 'YYYY-MM-DD'
        formatted = Dates.format(value, "yyyy-mm-dd")
        return "'$formatted'"
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

function compile_expr(dialect::SQLiteDialect, expr::RawExpr, params::Vector{Symbol})::String
    # Return raw SQL directly without any escaping or quoting
    return expr.sql
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

"""
    compile_window_frame(dialect::SQLiteDialect, frame::WindowFrame) -> String

Compile a window frame specification into SQL.
"""
function compile_window_frame(dialect::SQLiteDialect, frame::WindowFrame)::String
    # Frame mode
    mode_str = string(frame.mode)  # ROWS, RANGE, or GROUPS

    # Start bound
    start_str = if frame.start_bound isa Symbol
        replace(string(frame.start_bound), "_" => " ")  # UNBOUNDED_PRECEDING -> UNBOUNDED PRECEDING
    elseif frame.start_bound < 0
        "$(abs(frame.start_bound)) PRECEDING"
    elseif frame.start_bound > 0
        "$(frame.start_bound) FOLLOWING"
    else
        "CURRENT ROW"
    end

    # End bound
    if frame.end_bound === nothing
        # Single bound: "ROWS <start>"
        return "$mode_str $start_str"
    else
        end_str = if frame.end_bound isa Symbol
            replace(string(frame.end_bound), "_" => " ")
        elseif frame.end_bound < 0
            "$(abs(frame.end_bound)) PRECEDING"
        elseif frame.end_bound > 0
            "$(frame.end_bound) FOLLOWING"
        else
            "CURRENT ROW"
        end

        # Two bounds: "ROWS BETWEEN <start> AND <end>"
        return "$mode_str BETWEEN $start_str AND $end_str"
    end
end

"""
    compile_expr(dialect::SQLiteDialect, expr::WindowFunc, params::Vector{Symbol}) -> String

Compile a window function expression into SQL.
"""
function compile_expr(dialect::SQLiteDialect, expr::WindowFunc,
                      params::Vector{Symbol})::String
    # Compile function name and arguments
    func_name = string(expr.name)

    if isempty(expr.args)
        func_call = "$(func_name)()"
    else
        args_sql = [compile_expr(dialect, arg, params) for arg in expr.args]
        args_str = Base.join(args_sql, ", ")
        func_call = "$(func_name)($args_str)"
    end

    # Compile OVER clause
    over_parts = String[]

    # PARTITION BY
    if !isempty(expr.over.partition_by)
        partition_sql = [compile_expr(dialect, p, params) for p in expr.over.partition_by]
        partition_str = Base.join(partition_sql, ", ")
        push!(over_parts, "PARTITION BY $partition_str")
    end

    # ORDER BY
    if !isempty(expr.over.order_by)
        order_sql = [begin
                         e_sql = compile_expr(dialect, e, params)
                         desc ? "$e_sql DESC" : "$e_sql"
                     end
                     for (e, desc) in expr.over.order_by]
        order_str = Base.join(order_sql, ", ")
        push!(over_parts, "ORDER BY $order_str")
    end

    # Frame specification
    if expr.over.frame !== nothing
        frame_str = compile_window_frame(dialect, expr.over.frame)
        push!(over_parts, frame_str)
    end

    # Combine OVER clause
    if isempty(over_parts)
        over_clause = "OVER ()"
    else
        over_clause = "OVER ($(Base.join(over_parts, " ")))"
    end

    return "$func_call $over_clause"
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
# ON CONFLICT (UPSERT) Compilation
#

"""
    compile(dialect::SQLiteDialect, query::OnConflict{T}) -> (String, Vector{Symbol})

Compile an ON CONFLICT clause (UPSERT) for SQLite.

SQLite supports two forms:

  - `ON CONFLICT DO NOTHING` - ignore conflicts
  - `ON CONFLICT (...) DO UPDATE SET ...` - update on conflict

# Examples

```julia
# ON CONFLICT DO NOTHING
q = from(:users) |>
    insert_into(:id, :email) |>
    values((id = 1, email = "alice@example.com")) |>
    on_conflict_do_nothing()

sql, params = compile(dialect, q)
# → "INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT DO NOTHING"

# ON CONFLICT (email) DO UPDATE SET name = excluded.name
q = from(:users) |>
    insert_into(:id, :email, :name) |>
    values((id = 1, email = "alice@example.com", name = "Alice")) |>
    on_conflict_do_update([:email],
                          :name => col(:excluded, :name))

sql, params = compile(dialect, q)
# → "INSERT INTO `users` (`id`, `email`, `name`) VALUES (?, ?, ?) ON CONFLICT (`email`) DO UPDATE SET `name` = `excluded`.`name`"
```
"""
function compile(dialect::SQLiteDialect,
                 query::OnConflict{T})::Tuple{String, Vector{Symbol}} where {T}
    # Compile the INSERT VALUES statement
    source_sql, params = compile(dialect, query.source)

    # Start building ON CONFLICT clause
    conflict_sql = "ON CONFLICT"

    # Add target columns if specified
    if query.target !== nothing && !isempty(query.target)
        target_cols = [quote_identifier(dialect, col) for col in query.target]
        conflict_sql *= " (" * Base.join(target_cols, ", ") * ")"
    end

    # Add action
    if query.action == :DO_NOTHING
        conflict_sql *= " DO NOTHING"
    elseif query.action == :DO_UPDATE
        # Compile UPDATE SET clause
        set_parts = String[]
        for (col, expr) in query.updates
            col_name = quote_identifier(dialect, col)
            expr_sql = compile_expr(dialect, expr, params)
            push!(set_parts, "$col_name = $expr_sql")
        end
        conflict_sql *= " DO UPDATE SET " * Base.join(set_parts, ", ")

        # Add WHERE clause if specified
        if query.where_clause !== nothing
            where_sql = compile_expr(dialect, query.where_clause, params)
            conflict_sql *= " WHERE $where_sql"
        end
    else
        error("Invalid ON CONFLICT action: $(query.action). Must be :DO_NOTHING or :DO_UPDATE")
    end

    # Combine INSERT with ON CONFLICT
    sql = "$source_sql $conflict_sql"

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

#
# Set Operations Compilation (UNION, INTERSECT, EXCEPT)
#

"""
    compile(dialect::SQLiteDialect, query::SetUnion{T}) -> Tuple{String, Vector{Symbol}}

Compile a UNION or UNION ALL set operation.

# Example

```julia
q1 = from(:users) |> select(NamedTuple, col(:users, :email))
q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))
q = union(q1, q2)
sql, params = compile(SQLiteDialect(), q)
# → "SELECT `users`.`email` FROM `users` UNION SELECT `admins`.`email` FROM `admins`"
```
"""
function compile(dialect::SQLiteDialect,
                 query::SetUnion{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]

    # Compile left query
    left_sql, left_params = compile(dialect, query.left)
    append!(params, left_params)

    # Compile right query
    right_sql, right_params = compile(dialect, query.right)
    append!(params, right_params)

    # Determine operator
    op = query.all ? "UNION ALL" : "UNION"

    # Combine with parentheses for clarity
    sql = "($left_sql) $op ($right_sql)"

    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, query::SetIntersect{T}) -> Tuple{String, Vector{Symbol}}

Compile an INTERSECT or INTERSECT ALL set operation.

# Example

```julia
q1 = from(:customers) |> select(NamedTuple, col(:customers, :id))
q2 = from(:orders) |> select(NamedTuple, col(:orders, :customer_id))
q = intersect(q1, q2)
sql, params = compile(SQLiteDialect(), q)
# → "SELECT `customers`.`id` FROM `customers` INTERSECT SELECT `orders`.`customer_id` FROM `orders`"
```
"""
function compile(dialect::SQLiteDialect,
                 query::SetIntersect{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]

    # Compile left query
    left_sql, left_params = compile(dialect, query.left)
    append!(params, left_params)

    # Compile right query
    right_sql, right_params = compile(dialect, query.right)
    append!(params, right_params)

    # Determine operator (SQLite doesn't support INTERSECT ALL yet, but structure allows it)
    op = query.all ? "INTERSECT ALL" : "INTERSECT"

    # Combine with parentheses for clarity
    sql = "($left_sql) $op ($right_sql)"

    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, query::SetExcept{T}) -> Tuple{String, Vector{Symbol}}

Compile an EXCEPT or EXCEPT ALL set operation.

# Example

```julia
q1 = from(:all_users) |> select(NamedTuple, col(:all_users, :id))
q2 = from(:banned_users) |> select(NamedTuple, col(:banned_users, :user_id))
q = except(q1, q2)
sql, params = compile(SQLiteDialect(), q)
# → "SELECT `all_users`.`id` FROM `all_users` EXCEPT SELECT `banned_users`.`user_id` FROM `banned_users`"
```
"""
function compile(dialect::SQLiteDialect,
                 query::SetExcept{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]

    # Compile left query
    left_sql, left_params = compile(dialect, query.left)
    append!(params, left_params)

    # Compile right query
    right_sql, right_params = compile(dialect, query.right)
    append!(params, right_params)

    # Determine operator (SQLite doesn't support EXCEPT ALL yet, but structure allows it)
    op = query.all ? "EXCEPT ALL" : "EXCEPT"

    # Combine with parentheses for clarity
    sql = "($left_sql) $op ($right_sql)"

    return (sql, params)
end

#
# DDL Compilation
#

using .Core: DDLStatement, CreateTable, AlterTable, DropTable, CreateIndex, DropIndex
using .Core: ColumnDef, ColumnConstraint, PrimaryKeyConstraint, NotNullConstraint,
             UniqueConstraint, DefaultConstraint, CheckConstraint, ForeignKeyConstraint,
             AutoIncrementConstraint, GeneratedConstraint, CollationConstraint,
             OnUpdateConstraint, CommentConstraint, IdentityConstraint
using .Core: TableConstraint, TablePrimaryKey, TableForeignKey, TableUnique, TableCheck
using .Core: AlterTableOp, AddColumn, DropColumn, RenameColumn, AddTableConstraint,
             DropConstraint, AlterColumnSetDefault, AlterColumnDropDefault,
             AlterColumnSetNotNull, AlterColumnDropNotNull, AlterColumnSetType,
             AlterColumnSetStatistics, AlterColumnSetStorage

"""
    compile_column_type(dialect::SQLiteDialect, type::Symbol) -> String

Map portable column types to SQLite types.

# Example

```julia
compile_column_type(SQLiteDialect(), :integer)  # → "INTEGER"
compile_column_type(SQLiteDialect(), :text)     # → "TEXT"
```
"""
function compile_column_type(dialect::SQLiteDialect, type::Symbol)::String
    if type == :integer
        return "INTEGER"
    elseif type == :bigint
        return "INTEGER"  # SQLite uses INTEGER for all integer types
    elseif type == :real
        return "REAL"
    elseif type == :text
        return "TEXT"
    elseif type == :blob
        return "BLOB"
    elseif type == :boolean
        return "INTEGER"  # SQLite uses INTEGER for booleans (0/1)
    elseif type == :timestamp
        return "TEXT"  # SQLite stores timestamps as TEXT or INTEGER
    elseif type == :date
        return "TEXT"  # SQLite stores dates as TEXT
    elseif type == :uuid
        return "TEXT"  # SQLite stores UUIDs as TEXT
    elseif type == :json
        return "TEXT"  # SQLite stores JSON as TEXT
    else
        error("Unknown column type: $type")
    end
end

"""
    compile_column_constraint(dialect::SQLiteDialect, constraint::ColumnConstraint, params::Vector{Symbol}) -> String

Compile a column-level constraint to SQL.
"""
function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::PrimaryKeyConstraint,
                                   params::Vector{Symbol})::String
    return "PRIMARY KEY"
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::NotNullConstraint,
                                   params::Vector{Symbol})::String
    return "NOT NULL"
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::UniqueConstraint,
                                   params::Vector{Symbol})::String
    return "UNIQUE"
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::DefaultConstraint,
                                   params::Vector{Symbol})::String
    value_sql = compile_expr(dialect, constraint.value, params)
    return "DEFAULT $value_sql"
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::CheckConstraint,
                                   params::Vector{Symbol})::String
    condition_sql = compile_expr(dialect, constraint.condition, params)
    return "CHECK ($condition_sql)"
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::ForeignKeyConstraint,
                                   params::Vector{Symbol})::String
    ref_table = quote_identifier(dialect, constraint.ref_table)
    ref_column = quote_identifier(dialect, constraint.ref_column)
    parts = ["REFERENCES $ref_table($ref_column)"]

    if constraint.on_delete != :no_action
        action = uppercase(string(constraint.on_delete))
        action = replace(action, "_" => " ")
        push!(parts, "ON DELETE $action")
    end

    if constraint.on_update != :no_action
        action = uppercase(string(constraint.on_update))
        action = replace(action, "_" => " ")
        push!(parts, "ON UPDATE $action")
    end

    return Base.join(parts, " ")
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::AutoIncrementConstraint,
                                   params::Vector{Symbol})::String
    return "AUTOINCREMENT"
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::GeneratedConstraint,
                                   params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, constraint.expr, params)
    storage = constraint.stored ? "STORED" : "VIRTUAL"
    return "GENERATED ALWAYS AS ($expr_sql) $storage"
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::CollationConstraint,
                                   params::Vector{Symbol})::String
    return "COLLATE $(constraint.collation)"
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::OnUpdateConstraint,
                                   params::Vector{Symbol})::String
    # SQLite does not support ON UPDATE clause for columns
    # This is MySQL-specific, so we'll ignore it for SQLite
    @warn "ON UPDATE constraint is not supported in SQLite, ignoring"
    return ""
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::CommentConstraint,
                                   params::Vector{Symbol})::String
    # SQLite does not support column comments in CREATE TABLE
    # Comments would need to be stored in a separate metadata table
    @warn "Column comments are not supported in SQLite, ignoring"
    return ""
end

function compile_column_constraint(dialect::SQLiteDialect,
                                   constraint::IdentityConstraint,
                                   params::Vector{Symbol})::String
    # SQLite does not support IDENTITY columns
    # Use AUTOINCREMENT instead
    @warn "IDENTITY constraint is not supported in SQLite, using AUTOINCREMENT instead"
    return "AUTOINCREMENT"
end

"""
    compile_column_def(dialect::SQLiteDialect, column::ColumnDef, params::Vector{Symbol}) -> String

Compile a column definition to SQL.

# Example

```julia
col = ColumnDef(:email, :text, [NotNullConstraint(), UniqueConstraint()])
compile_column_def(SQLiteDialect(), col, Symbol[])
# → "`email` TEXT NOT NULL UNIQUE"
```
"""
function compile_column_def(dialect::SQLiteDialect, column::ColumnDef,
                            params::Vector{Symbol})::String
    name = quote_identifier(dialect, column.name)
    type_sql = compile_column_type(dialect, column.type)
    parts = [name, type_sql]

    for constraint in column.constraints
        constraint_sql = compile_column_constraint(dialect, constraint, params)
        # Skip empty constraint strings (from unsupported features)
        if !isempty(constraint_sql)
            push!(parts, constraint_sql)
        end
    end

    return Base.join(parts, " ")
end

"""
    compile_table_constraint(dialect::SQLiteDialect, constraint::TableConstraint, params::Vector{Symbol}) -> String

Compile a table-level constraint to SQL.
"""
function compile_table_constraint(dialect::SQLiteDialect,
                                  constraint::TablePrimaryKey,
                                  params::Vector{Symbol})::String
    columns = [quote_identifier(dialect, col) for col in constraint.columns]
    columns_str = Base.join(columns, ", ")

    if constraint.name !== nothing
        name = quote_identifier(dialect, constraint.name)
        return "CONSTRAINT $name PRIMARY KEY ($columns_str)"
    else
        return "PRIMARY KEY ($columns_str)"
    end
end

function compile_table_constraint(dialect::SQLiteDialect,
                                  constraint::TableForeignKey,
                                  params::Vector{Symbol})::String
    columns = [quote_identifier(dialect, col) for col in constraint.columns]
    columns_str = Base.join(columns, ", ")

    ref_table = quote_identifier(dialect, constraint.ref_table)
    ref_columns = [quote_identifier(dialect, col) for col in constraint.ref_columns]
    ref_columns_str = Base.join(ref_columns, ", ")

    parts = ["FOREIGN KEY ($columns_str) REFERENCES $ref_table($ref_columns_str)"]

    if constraint.on_delete != :no_action
        action = uppercase(string(constraint.on_delete))
        action = replace(action, "_" => " ")
        push!(parts, "ON DELETE $action")
    end

    if constraint.on_update != :no_action
        action = uppercase(string(constraint.on_update))
        action = replace(action, "_" => " ")
        push!(parts, "ON UPDATE $action")
    end

    fk_sql = Base.join(parts, " ")

    if constraint.name !== nothing
        name = quote_identifier(dialect, constraint.name)
        return "CONSTRAINT $name $fk_sql"
    else
        return fk_sql
    end
end

function compile_table_constraint(dialect::SQLiteDialect,
                                  constraint::TableUnique,
                                  params::Vector{Symbol})::String
    columns = [quote_identifier(dialect, col) for col in constraint.columns]
    columns_str = Base.join(columns, ", ")

    if constraint.name !== nothing
        name = quote_identifier(dialect, constraint.name)
        return "CONSTRAINT $name UNIQUE ($columns_str)"
    else
        return "UNIQUE ($columns_str)"
    end
end

function compile_table_constraint(dialect::SQLiteDialect,
                                  constraint::TableCheck,
                                  params::Vector{Symbol})::String
    condition_sql = compile_expr(dialect, constraint.condition, params)

    if constraint.name !== nothing
        name = quote_identifier(dialect, constraint.name)
        return "CONSTRAINT $name CHECK ($condition_sql)"
    else
        return "CHECK ($condition_sql)"
    end
end

"""
    compile(dialect::SQLiteDialect, ddl::CreateTable) -> (String, Vector{Symbol})

Compile a CREATE TABLE statement to SQL.

# Example

```julia
ddl = create_table(:users) |>
      add_column(:id, :integer; primary_key = true) |>
      add_column(:email, :text; nullable = false)

sql, params = compile(SQLiteDialect(), ddl)
# sql → "CREATE TABLE `users` (`id` INTEGER PRIMARY KEY, `email` TEXT NOT NULL)"
```
"""
function compile(dialect::SQLiteDialect,
                 ddl::CreateTable)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    # Build CREATE TABLE clause
    parts = ["CREATE"]

    if ddl.temporary
        push!(parts, "TEMPORARY")
    end

    push!(parts, "TABLE")

    if ddl.if_not_exists
        push!(parts, "IF NOT EXISTS")
    end

    table = quote_identifier(dialect, ddl.table)
    push!(parts, table)

    # Compile columns
    column_defs = [compile_column_def(dialect, col, params) for col in ddl.columns]

    # Compile table constraints
    constraint_defs = [compile_table_constraint(dialect, con, params)
                       for con in ddl.constraints]

    # Combine columns and constraints
    all_defs = vcat(column_defs, constraint_defs)
    defs_str = Base.join(all_defs, ", ")

    sql = Base.join(parts, " ") * " ($defs_str)"

    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, ddl::AlterTable) -> (String, Vector{Symbol})

Compile an ALTER TABLE statement to SQL.

Note: SQLite has limited ALTER TABLE support. Only ADD COLUMN and RENAME COLUMN
are supported directly. Other operations may require table recreation.

# Example

```julia
ddl = alter_table(:users) |>
      add_alter_column(:age, :integer)

sql, params = compile(SQLiteDialect(), ddl)
# sql → "ALTER TABLE `users` ADD COLUMN `age` INTEGER"
```
"""
function compile(dialect::SQLiteDialect,
                 ddl::AlterTable)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    if isempty(ddl.operations)
        error("AlterTable must have at least one operation")
    end

    # SQLite requires one ALTER TABLE per operation
    # We'll compile the first operation and warn if there are more
    if length(ddl.operations) > 1
        @warn "SQLite only supports one ALTER TABLE operation at a time. Only the first operation will be compiled."
    end

    op = ddl.operations[1]
    table = quote_identifier(dialect, ddl.table)

    if op isa AddColumn
        column_def = compile_column_def(dialect, op.column, params)
        sql = "ALTER TABLE $table ADD COLUMN $column_def"
    elseif op isa DropColumn
        # SQLite doesn't support DROP COLUMN directly
        error("SQLite does not support DROP COLUMN. Use table recreation instead.")
    elseif op isa RenameColumn
        old_name = quote_identifier(dialect, op.old_name)
        new_name = quote_identifier(dialect, op.new_name)
        sql = "ALTER TABLE $table RENAME COLUMN $old_name TO $new_name"
    elseif op isa AddTableConstraint
        error("SQLite does not support ADD CONSTRAINT directly. Define constraints at table creation.")
    elseif op isa DropConstraint
        error("SQLite does not support DROP CONSTRAINT directly.")
    elseif op isa AlterColumnSetDefault
        error("SQLite does not support ALTER COLUMN SET DEFAULT. Use table recreation or set default at column creation.")
    elseif op isa AlterColumnDropDefault
        error("SQLite does not support ALTER COLUMN DROP DEFAULT. Use table recreation.")
    elseif op isa AlterColumnSetNotNull
        error("SQLite does not support ALTER COLUMN SET NOT NULL. Use table recreation or define NOT NULL at column creation.")
    elseif op isa AlterColumnDropNotNull
        error("SQLite does not support ALTER COLUMN DROP NOT NULL. Use table recreation.")
    elseif op isa AlterColumnSetType
        error("SQLite does not support ALTER COLUMN TYPE. Use table recreation to change column types.")
    elseif op isa AlterColumnSetStatistics
        error("SQLite does not support ALTER COLUMN SET STATISTICS. This is a PostgreSQL-specific feature.")
    elseif op isa AlterColumnSetStorage
        error("SQLite does not support ALTER COLUMN SET STORAGE. This is a PostgreSQL-specific feature.")
    else
        error("Unknown ALTER TABLE operation: $(typeof(op))")
    end

    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, ddl::DropTable) -> (String, Vector{Symbol})

Compile a DROP TABLE statement to SQL.

# Example

```julia
ddl = drop_table(:users; if_exists = true)
sql, params = compile(SQLiteDialect(), ddl)
# sql → "DROP TABLE IF EXISTS `users`"
```
"""
function compile(dialect::SQLiteDialect,
                 ddl::DropTable)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    parts = ["DROP TABLE"]

    if ddl.if_exists
        push!(parts, "IF EXISTS")
    end

    table = quote_identifier(dialect, ddl.table)
    push!(parts, table)

    # Note: SQLite doesn't support CASCADE/RESTRICT in DROP TABLE
    if ddl.cascade
        @warn "SQLite does not support CASCADE in DROP TABLE. Ignoring cascade option."
    end

    sql = Base.join(parts, " ")

    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, ddl::CreateIndex) -> (String, Vector{Symbol})

Compile a CREATE INDEX statement to SQL.

Supports:

  - Column indexes
  - Expression indexes (SQLite 3.9+)
  - Partial indexes (WHERE clause)
  - Unique indexes

Note: Index method (USING clause) is PostgreSQL-specific and ignored in SQLite.

# Example

```julia
# Column index
ddl = create_index(:idx_users_email, :users, [:email]; unique = true)
sql, params = compile(SQLiteDialect(), ddl)
# sql → "CREATE UNIQUE INDEX `idx_users_email` ON `users` (`email`)"

# Expression index (SQLite 3.9+)
ddl = create_index(:idx_users_lower_email, :users, Symbol[];
                   expr = [func(:lower, [col(:users, :email)])])
sql, params = compile(SQLiteDialect(), ddl)
# sql → "CREATE INDEX `idx_users_lower_email` ON `users` (lower(`users`.`email`))"
```
"""
function compile(dialect::SQLiteDialect,
                 ddl::CreateIndex)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    parts = ["CREATE"]

    if ddl.unique
        push!(parts, "UNIQUE")
    end

    push!(parts, "INDEX")

    if ddl.if_not_exists
        push!(parts, "IF NOT EXISTS")
    end

    name = quote_identifier(dialect, ddl.name)
    push!(parts, name)

    push!(parts, "ON")

    table = quote_identifier(dialect, ddl.table)
    push!(parts, table)

    # Index columns or expressions
    if ddl.expressions !== nothing
        # Expression index (SQLite 3.9+)
        exprs = [compile_expr(dialect, expr, params) for expr in ddl.expressions]
        exprs_str = Base.join(exprs, ", ")
        push!(parts, "($exprs_str)")
    else
        # Column index
        columns = [quote_identifier(dialect, col) for col in ddl.columns]
        columns_str = Base.join(columns, ", ")
        push!(parts, "($columns_str)")
    end

    # Note: Index method (USING clause) is PostgreSQL-specific, not supported in SQLite
    # We silently ignore ddl.method for SQLite

    # Partial index support (WHERE clause)
    if ddl.where !== nothing
        where_sql = compile_expr(dialect, ddl.where, params)
        push!(parts, "WHERE $where_sql")
    end

    sql = Base.join(parts, " ")

    return (sql, params)
end

"""
    compile(dialect::SQLiteDialect, ddl::DropIndex) -> (String, Vector{Symbol})

Compile a DROP INDEX statement to SQL.

# Example

```julia
ddl = drop_index(:idx_users_email; if_exists = true)
sql, params = compile(SQLiteDialect(), ddl)
# sql → "DROP INDEX IF EXISTS `idx_users_email`"
```
"""
function compile(dialect::SQLiteDialect,
                 ddl::DropIndex)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    parts = ["DROP INDEX"]

    if ddl.if_exists
        push!(parts, "IF EXISTS")
    end

    name = quote_identifier(dialect, ddl.name)
    push!(parts, name)

    sql = Base.join(parts, " ")

    return (sql, params)
end
