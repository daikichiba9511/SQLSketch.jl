"""
# PostgreSQL Dialect

PostgreSQL dialect implementation for SQLSketch.

This dialect generates PostgreSQL-compatible SQL from query and expression ASTs.

## Characteristics

- Identifier quoting: double quotes (`"identifier"`)
- Placeholder syntax: `\$1`, `\$2`, ... (positional with numbers)
- Advanced features: LATERAL joins, RETURNING *, JSONB, Arrays
- Rich DDL capabilities

## Supported Capabilities

- ✓ Basic SELECT/INSERT/UPDATE/DELETE
- ✓ Window functions
- ✓ CTE (WITH clause)
- ✓ UPSERT (ON CONFLICT)
- ✓ RETURNING clause (full support)
- ✓ LATERAL joins
- ✓ Advanced types (UUID, JSONB, ARRAY, etc.)
- ✓ COPY FROM
- ✓ Advisory locks

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
    PostgreSQLDialect(version::VersionNumber = v"14.0.0")

PostgreSQL dialect for SQL generation.

# Fields

  - `version`: PostgreSQL version (affects capability reporting)

# Example

```julia
dialect = PostgreSQLDialect()
sql, params = compile(dialect, query)
```
"""
struct PostgreSQLDialect <: Dialect
    version::VersionNumber
end

# Default constructor uses PostgreSQL 14 (recent stable version)
PostgreSQLDialect() = PostgreSQLDialect(v"14.0.0")

#
# Helper Functions
#

"""
    quote_identifier(dialect::PostgreSQLDialect, name::Symbol) -> String

Quote an identifier using PostgreSQL double-quote syntax.

# Example

```julia
quote_identifier(PostgreSQLDialect(), :users) # → "\"users\""
```
"""
function quote_identifier(dialect::PostgreSQLDialect, name::Symbol)::String
    # Escape double quotes by doubling them
    name_str = string(name)
    escaped = replace(name_str, "\"" => "\"\"")
    return "\"$escaped\""
end

"""
    placeholder(dialect::PostgreSQLDialect, idx::Int) -> String

Generate a positional parameter placeholder.

PostgreSQL uses `\$1`, `\$2`, etc. for numbered positional parameters.

# Example

```julia
placeholder(PostgreSQLDialect(), 1) # → "\$1"
placeholder(PostgreSQLDialect(), 2) # → "\$2"
```
"""
function placeholder(dialect::PostgreSQLDialect, idx::Int)::String
    return "\$$idx"
end

"""
    supports(dialect::PostgreSQLDialect, cap::Capability) -> Bool

Check if PostgreSQL supports a specific capability.

# Example

```julia
supports(PostgreSQLDialect(), CAP_CTE)     # → true
supports(PostgreSQLDialect(), CAP_LATERAL) # → true
```
"""
function supports(dialect::PostgreSQLDialect, cap::Capability)::Bool
    if cap == CAP_CTE
        return true
    elseif cap == CAP_RETURNING
        return true
    elseif cap == CAP_UPSERT
        return true
    elseif cap == CAP_WINDOW
        return true
    elseif cap == CAP_LATERAL
        return true
    elseif cap == CAP_BULK_COPY
        return true
    elseif cap == CAP_SAVEPOINT
        return true
    elseif cap == CAP_ADVISORY_LOCK
        return true
    else
        return false
    end
end

# Placeholder resolution and helper functions are in shared_helpers.jl

#
# Expression Compilation
#

"""
    compile_expr(dialect::PostgreSQLDialect, expr::SQLExpr, params::Vector{Symbol}) -> String

Compile an expression AST into a SQL fragment.
"""
function compile_expr(dialect::PostgreSQLDialect, expr::ColRef,
                      params::Vector{Symbol})::String
    table = quote_identifier(dialect, expr.table)
    column = quote_identifier(dialect, expr.column)
    return "$table.$column"
end

function compile_expr(dialect::PostgreSQLDialect, expr::Literal,
                      params::Vector{Symbol})::String
    value = expr.value

    if value === nothing || value === missing
        return "NULL"
    elseif value isa Bool
        # PostgreSQL uses TRUE/FALSE for booleans
        return value ? "TRUE" : "FALSE"
    elseif value isa Number
        return string(value)
    elseif value isa AbstractString
        # Escape single quotes by doubling them
        escaped = replace(string(value), "'" => "''")
        return "'$escaped'"
    elseif value isa Dates.DateTime
        # PostgreSQL TIMESTAMP format: 'YYYY-MM-DD HH:MM:SS'
        formatted = Dates.format(value, "yyyy-mm-dd HH:MM:SS")
        return "'$formatted'"
    elseif value isa Dates.Date
        # PostgreSQL DATE format: 'YYYY-MM-DD'
        formatted = Dates.format(value, "yyyy-mm-dd")
        return "'$formatted'"
    else
        error("Unsupported literal type: $(typeof(value))")
    end
end

function compile_expr(dialect::PostgreSQLDialect, expr::Param,
                      params::Vector{Symbol})::String
    push!(params, expr.name)
    return placeholder(dialect, length(params))
end

# RawExpr: Return raw SQL without modification
function compile_expr(dialect::PostgreSQLDialect, expr::RawExpr,
                      params::Vector{Symbol})::String
    # Return raw SQL directly without any escaping or quoting
    return expr.sql
end

function compile_expr(dialect::PostgreSQLDialect, expr::BinaryOp,
                      params::Vector{Symbol})::String
    left_sql = compile_expr(dialect, expr.left, params)
    right_sql = compile_expr(dialect, expr.right, params)

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
        "ILIKE"  # PostgreSQL native case-insensitive LIKE
    elseif expr.op == :NOT_ILIKE
        "NOT ILIKE"
    else
        string(expr.op)
    end

    return "($left_sql $op_str $right_sql)"
end

function compile_expr(dialect::PostgreSQLDialect, expr::UnaryOp,
                      params::Vector{Symbol})::String
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

function compile_expr(dialect::PostgreSQLDialect, expr::FuncCall,
                      params::Vector{Symbol})::String
    func_name = string(expr.name)

    if isempty(expr.args)
        return "$func_name()"
    else
        args_sql = [compile_expr(dialect, arg, params) for arg in expr.args]
        args_str = Base.join(args_sql, ", ")
        return "$func_name($args_str)"
    end
end

function compile_expr(dialect::PostgreSQLDialect, expr::PlaceholderField,
                      params::Vector{Symbol})::String
    error("PlaceholderField($(expr.column)) must be resolved to ColRef before compilation.")
end

function compile_expr(dialect::PostgreSQLDialect, expr::BetweenOp,
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

function compile_expr(dialect::PostgreSQLDialect, expr::InOp,
                      params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, expr.expr, params)
    values_sql = [compile_expr(dialect, v, params) for v in expr.values]
    values_list = Base.join(values_sql, ", ")

    if expr.negated
        return "($expr_sql NOT IN ($values_list))"
    else
        return "($expr_sql IN ($values_list))"
    end
end

function compile_expr(dialect::PostgreSQLDialect, expr::Cast,
                      params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, expr.expr, params)
    target_type = uppercase(string(expr.target_type))
    return "CAST($expr_sql AS $target_type)"
end

function compile_expr(dialect::PostgreSQLDialect, expr::Subquery,
                      params::Vector{Symbol})::String
    subquery_sql, subquery_params = compile(dialect, expr.query)
    append!(params, subquery_params)
    return "($subquery_sql)"
end

function compile_expr(dialect::PostgreSQLDialect, expr::CaseExpr,
                      params::Vector{Symbol})::String
    parts = ["CASE"]

    for (condition, result) in expr.whens
        condition_sql = compile_expr(dialect, condition, params)
        result_sql = compile_expr(dialect, result, params)
        push!(parts, "WHEN $condition_sql THEN $result_sql")
    end

    if expr.else_expr !== nothing
        else_sql = compile_expr(dialect, expr.else_expr, params)
        push!(parts, "ELSE $else_sql")
    end

    push!(parts, "END")
    return Base.join(parts, " ")
end

"""
    compile_window_frame(dialect::PostgreSQLDialect, frame::WindowFrame) -> String

Compile a window frame specification into SQL.
"""
function compile_window_frame(dialect::PostgreSQLDialect, frame::WindowFrame)::String
    mode_str = string(frame.mode)

    start_str = if frame.start_bound isa Symbol
        replace(string(frame.start_bound), "_" => " ")
    elseif frame.start_bound < 0
        "$(abs(frame.start_bound)) PRECEDING"
    elseif frame.start_bound > 0
        "$(frame.start_bound) FOLLOWING"
    else
        "CURRENT ROW"
    end

    if frame.end_bound === nothing
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
        return "$mode_str BETWEEN $start_str AND $end_str"
    end
end

function compile_expr(dialect::PostgreSQLDialect, expr::WindowFunc,
                      params::Vector{Symbol})::String
    func_name = string(expr.name)

    if isempty(expr.args)
        func_call = "$(func_name)()"
    else
        args_sql = [compile_expr(dialect, arg, params) for arg in expr.args]
        args_str = Base.join(args_sql, ", ")
        func_call = "$(func_name)($args_str)"
    end

    over_parts = String[]

    if !isempty(expr.over.partition_by)
        partition_sql = [compile_expr(dialect, p, params) for p in expr.over.partition_by]
        partition_str = Base.join(partition_sql, ", ")
        push!(over_parts, "PARTITION BY $partition_str")
    end

    if !isempty(expr.over.order_by)
        order_sql = [begin
                         e_sql = compile_expr(dialect, e, params)
                         desc ? "$e_sql DESC" : "$e_sql"
                     end
                     for (e, desc) in expr.over.order_by]
        order_str = Base.join(order_sql, ", ")
        push!(over_parts, "ORDER BY $order_str")
    end

    if expr.over.frame !== nothing
        frame_str = compile_window_frame(dialect, expr.over.frame)
        push!(over_parts, frame_str)
    end

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
    compile(dialect::PostgreSQLDialect, query::Query) -> (String, Vector{Symbol})

Compile a Query AST into a SQL string and parameter list.
"""
function compile(dialect::PostgreSQLDialect,
                 query::From{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "SELECT * FROM $table"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::Where{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    table = get_primary_table(query)
    if table === nothing
        if contains_placeholder(query.condition)
            error("Cannot use placeholder syntax (_.) in multi-table queries.")
        end
        resolved_condition = query.condition
    else
        resolved_condition = resolve_placeholders(query.condition, table)
    end

    condition_sql = compile_expr(dialect, resolved_condition, params)
    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::Select{OutT})::Tuple{String, Vector{Symbol}} where {OutT}
    source_sql, params = compile(dialect, query.source)

    if isempty(query.fields)
        return (source_sql, params)
    end

    table = get_primary_table(query)
    resolved_fields = if table === nothing
        if any(contains_placeholder(f) for f in query.fields)
            error("Cannot use placeholder syntax (_.) in multi-table queries.")
        end
        query.fields
    else
        [resolve_placeholders(f, table) for f in query.fields]
    end

    fields_sql = [compile_expr(dialect, field, params) for field in resolved_fields]
    fields_str = Base.join(fields_sql, ", ")

    if startswith(source_sql, "SELECT * FROM")
        sql = "SELECT $fields_str FROM" * source_sql[14:end]
    else
        sql = "SELECT $fields_str FROM ($source_sql) AS sub"
    end

    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::Join{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

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

    table = quote_identifier(dialect, query.table)
    on_sql = compile_expr(dialect, query.on, params)

    sql = "$source_sql $join_type $table ON $on_sql"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::OrderBy{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

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

function compile(dialect::PostgreSQLDialect,
                 query::Limit{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)
    sql = "$source_sql LIMIT $(query.n)"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::Offset{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)
    sql = "$source_sql OFFSET $(query.n)"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::Distinct{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    if startswith(source_sql, "SELECT ")
        sql = "SELECT DISTINCT" * source_sql[7:end]
    else
        sql = "SELECT DISTINCT * FROM ($source_sql) AS sub"
    end

    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::GroupBy{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    if isempty(query.fields)
        return (source_sql, params)
    end

    fields_sql = [compile_expr(dialect, field, params) for field in query.fields]
    fields_str = Base.join(fields_sql, ", ")

    sql = "$source_sql GROUP BY $fields_str"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::Having{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)
    condition_sql = compile_expr(dialect, query.condition, params)
    sql = "$source_sql HAVING $condition_sql"
    return (sql, params)
end

#
# DML Compilation
#

function compile(dialect::PostgreSQLDialect,
                 query::InsertInto{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    columns = [quote_identifier(dialect, col) for col in query.columns]
    columns_str = Base.join(columns, ", ")
    sql = "INSERT INTO $table ($columns_str)"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::InsertValues{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

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

function compile(dialect::PostgreSQLDialect,
                 query::Update{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "UPDATE $table"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::UpdateSet{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

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

function compile(dialect::PostgreSQLDialect,
                 query::UpdateWhere{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    table = get_primary_table(query.source)
    resolved_condition = resolve_placeholders(query.condition, table)
    condition_sql = compile_expr(dialect, resolved_condition, params)

    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::DeleteFrom{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "DELETE FROM $table"
    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::DeleteWhere{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    table = get_primary_table(query.source)
    resolved_condition = resolve_placeholders(query.condition, table)
    condition_sql = compile_expr(dialect, resolved_condition, params)

    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

#
# RETURNING Clause Compilation
#

function compile(dialect::PostgreSQLDialect,
                 query::Returning{OutT})::Tuple{String, Vector{Symbol}} where {OutT}
    source_sql, params = compile(dialect, query.source)

    table = get_primary_table(query.source)

    resolved_fields = if table === nothing
        if any(contains_placeholder(f) for f in query.fields)
            error("Cannot use placeholder syntax (p_) in RETURNING clause for multi-table queries.")
        end
        query.fields
    else
        [resolve_placeholders(f, table) for f in query.fields]
    end

    fields_sql = [compile_expr(dialect, field, params) for field in resolved_fields]
    fields_str = Base.join(fields_sql, ", ")

    sql = "$source_sql RETURNING $fields_str"

    return (sql, params)
end

#
# ON CONFLICT (UPSERT) Compilation
#

function compile(dialect::PostgreSQLDialect,
                 query::OnConflict{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    conflict_sql = "ON CONFLICT"

    if query.target !== nothing && !isempty(query.target)
        target_cols = [quote_identifier(dialect, col) for col in query.target]
        conflict_sql *= " (" * Base.join(target_cols, ", ") * ")"
    end

    if query.action == :DO_NOTHING
        conflict_sql *= " DO NOTHING"
    elseif query.action == :DO_UPDATE
        set_parts = String[]
        for (col, expr) in query.updates
            col_name = quote_identifier(dialect, col)
            expr_sql = compile_expr(dialect, expr, params)
            push!(set_parts, "$col_name = $expr_sql")
        end
        conflict_sql *= " DO UPDATE SET " * Base.join(set_parts, ", ")

        if query.where_clause !== nothing
            where_sql = compile_expr(dialect, query.where_clause, params)
            conflict_sql *= " WHERE $where_sql"
        end
    else
        error("Invalid ON CONFLICT action: $(query.action)")
    end

    sql = "$source_sql $conflict_sql"

    return (sql, params)
end

#
# CTE Compilation
#

function compile(dialect::PostgreSQLDialect,
                 query::With{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]

    cte_parts = String[]
    for cte_def in query.ctes
        cte_name = quote_identifier(dialect, cte_def.name)

        if !isempty(cte_def.columns)
            column_list = Base.join([quote_identifier(dialect, col)
                                     for col in cte_def.columns],
                                    ", ")
            cte_name = "$cte_name ($column_list)"
        end

        cte_sql, cte_params = compile(dialect, cte_def.query)
        append!(params, cte_params)

        push!(cte_parts, "$cte_name AS ($cte_sql)")
    end

    main_sql, main_params = compile(dialect, query.main_query)
    append!(params, main_params)

    cte_clause = Base.join(cte_parts, ", ")
    sql = "WITH $cte_clause $main_sql"

    return (sql, params)
end

#
# Set Operations Compilation
#

function compile(dialect::PostgreSQLDialect,
                 query::SetUnion{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]

    left_sql, left_params = compile(dialect, query.left)
    append!(params, left_params)

    right_sql, right_params = compile(dialect, query.right)
    append!(params, right_params)

    op = query.all ? "UNION ALL" : "UNION"
    sql = "($left_sql) $op ($right_sql)"

    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::SetIntersect{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]

    left_sql, left_params = compile(dialect, query.left)
    append!(params, left_params)

    right_sql, right_params = compile(dialect, query.right)
    append!(params, right_params)

    op = query.all ? "INTERSECT ALL" : "INTERSECT"
    sql = "($left_sql) $op ($right_sql)"

    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 query::SetExcept{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]

    left_sql, left_params = compile(dialect, query.left)
    append!(params, left_params)

    right_sql, right_params = compile(dialect, query.right)
    append!(params, right_params)

    op = query.all ? "EXCEPT ALL" : "EXCEPT"
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
    compile_column_type(dialect::PostgreSQLDialect, type::Symbol) -> String

Map portable column types to PostgreSQL types.
"""
function compile_column_type(dialect::PostgreSQLDialect, type::Symbol)::String
    if type == :integer
        return "INTEGER"
    elseif type == :bigint
        return "BIGINT"
    elseif type == :real
        return "REAL"
    elseif type == :text
        return "TEXT"
    elseif type == :blob
        return "BYTEA"  # PostgreSQL uses BYTEA for binary data
    elseif type == :boolean
        return "BOOLEAN"
    elseif type == :timestamp
        return "TIMESTAMP"
    elseif type == :date
        return "DATE"
    elseif type == :uuid
        return "UUID"
    elseif type == :json
        return "JSONB"  # PostgreSQL prefers JSONB over JSON
    else
        error("Unknown column type: $type")
    end
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::PrimaryKeyConstraint,
                                   params::Vector{Symbol})::String
    return "PRIMARY KEY"
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::NotNullConstraint,
                                   params::Vector{Symbol})::String
    return "NOT NULL"
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::UniqueConstraint,
                                   params::Vector{Symbol})::String
    return "UNIQUE"
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::DefaultConstraint,
                                   params::Vector{Symbol})::String
    value_sql = compile_expr(dialect, constraint.value, params)
    return "DEFAULT $value_sql"
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::CheckConstraint,
                                   params::Vector{Symbol})::String
    condition_sql = compile_expr(dialect, constraint.condition, params)
    return "CHECK ($condition_sql)"
end

function compile_column_constraint(dialect::PostgreSQLDialect,
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

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::AutoIncrementConstraint,
                                   params::Vector{Symbol})::String
    # PostgreSQL uses SERIAL type instead of AUTOINCREMENT
    # This is handled by converting :integer -> SERIAL during type compilation
    # when AUTO_INCREMENT constraint is present
    # For now, we'll return empty and handle it in compile_column_def
    return ""
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::GeneratedConstraint,
                                   params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, constraint.expr, params)
    storage = constraint.stored ? "STORED" : ""
    return "GENERATED ALWAYS AS ($expr_sql) $storage"
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::CollationConstraint,
                                   params::Vector{Symbol})::String
    return "COLLATE \"$(constraint.collation)\""
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::OnUpdateConstraint,
                                   params::Vector{Symbol})::String
    # PostgreSQL does not support ON UPDATE in column definitions
    # This is MySQL-specific, would need to use triggers in PostgreSQL
    @warn "ON UPDATE constraint is not supported in PostgreSQL column definitions, ignoring"
    return ""
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::CommentConstraint,
                                   params::Vector{Symbol})::String
    # PostgreSQL column comments require a separate COMMENT ON COLUMN statement
    # Cannot be included inline in CREATE TABLE
    @warn "Column comments in PostgreSQL require separate COMMENT ON COLUMN statement, ignoring inline comment"
    return ""
end

function compile_column_constraint(dialect::PostgreSQLDialect,
                                   constraint::IdentityConstraint,
                                   params::Vector{Symbol})::String
    always_or_default = constraint.always ? "ALWAYS" : "BY DEFAULT"
    parts = ["GENERATED $always_or_default AS IDENTITY"]

    options = String[]
    if constraint.start !== nothing
        push!(options, "START WITH $(constraint.start)")
    end
    if constraint.increment !== nothing
        push!(options, "INCREMENT BY $(constraint.increment)")
    end

    if !isempty(options)
        options_str = Base.join(options, " ")
        push!(parts, "($options_str)")
    end

    return Base.join(parts, " ")
end

function compile_column_def(dialect::PostgreSQLDialect, column::ColumnDef,
                            params::Vector{Symbol})::String
    name = quote_identifier(dialect, column.name)

    # Check if AUTO_INCREMENT constraint is present
    has_auto_increment = any(c -> c isa AutoIncrementConstraint, column.constraints)

    # If AUTO_INCREMENT, convert type to SERIAL/BIGSERIAL
    if has_auto_increment
        if column.type == :integer
            type_sql = "SERIAL"
        elseif column.type == :bigint
            type_sql = "BIGSERIAL"
        else
            type_sql = compile_column_type(dialect, column.type)
        end
    else
        type_sql = compile_column_type(dialect, column.type)
    end

    parts = [name, type_sql]

    for constraint in column.constraints
        # Skip AutoIncrementConstraint as it's handled by SERIAL type
        if constraint isa AutoIncrementConstraint
            continue
        end

        constraint_sql = compile_column_constraint(dialect, constraint, params)
        # Skip empty constraint strings (from unsupported features)
        if !isempty(constraint_sql)
            push!(parts, constraint_sql)
        end
    end

    return Base.join(parts, " ")
end

function compile_table_constraint(dialect::PostgreSQLDialect,
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

function compile_table_constraint(dialect::PostgreSQLDialect,
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

function compile_table_constraint(dialect::PostgreSQLDialect,
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

function compile_table_constraint(dialect::PostgreSQLDialect,
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

function compile(dialect::PostgreSQLDialect,
                 ddl::CreateTable)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

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

    column_defs = [compile_column_def(dialect, col, params) for col in ddl.columns]
    constraint_defs = [compile_table_constraint(dialect, con, params)
                       for con in ddl.constraints]

    all_defs = vcat(column_defs, constraint_defs)
    defs_str = Base.join(all_defs, ", ")

    sql = Base.join(parts, " ") * " ($defs_str)"

    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 ddl::AlterTable)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    if isempty(ddl.operations)
        error("AlterTable must have at least one operation")
    end

    # PostgreSQL supports multiple operations in one ALTER TABLE
    table = quote_identifier(dialect, ddl.table)
    parts = ["ALTER TABLE $table"]

    op_parts = String[]
    for op in ddl.operations
        if op isa AddColumn
            column_def = compile_column_def(dialect, op.column, params)
            push!(op_parts, "ADD COLUMN $column_def")
        elseif op isa DropColumn
            col_name = quote_identifier(dialect, op.column)
            push!(op_parts, "DROP COLUMN $col_name")
        elseif op isa RenameColumn
            old_name = quote_identifier(dialect, op.old_name)
            new_name = quote_identifier(dialect, op.new_name)
            push!(op_parts, "RENAME COLUMN $old_name TO $new_name")
        elseif op isa AddTableConstraint
            constraint_sql = compile_table_constraint(dialect, op.constraint, params)
            push!(op_parts, "ADD $constraint_sql")
        elseif op isa DropConstraint
            constraint_name = quote_identifier(dialect, op.name)
            push!(op_parts, "DROP CONSTRAINT $constraint_name")
        elseif op isa AlterColumnSetDefault
            col_name = quote_identifier(dialect, op.column)
            default_sql = compile_expr(dialect, op.value, params)
            push!(op_parts, "ALTER COLUMN $col_name SET DEFAULT $default_sql")
        elseif op isa AlterColumnDropDefault
            col_name = quote_identifier(dialect, op.column)
            push!(op_parts, "ALTER COLUMN $col_name DROP DEFAULT")
        elseif op isa AlterColumnSetNotNull
            col_name = quote_identifier(dialect, op.column)
            push!(op_parts, "ALTER COLUMN $col_name SET NOT NULL")
        elseif op isa AlterColumnDropNotNull
            col_name = quote_identifier(dialect, op.column)
            push!(op_parts, "ALTER COLUMN $col_name DROP NOT NULL")
        elseif op isa AlterColumnSetType
            col_name = quote_identifier(dialect, op.column)
            type_sql = compile_column_type(dialect, op.type)
            if op.using_expr !== nothing
                using_sql = compile_expr(dialect, op.using_expr, params)
                push!(op_parts, "ALTER COLUMN $col_name TYPE $type_sql USING $using_sql")
            else
                push!(op_parts, "ALTER COLUMN $col_name TYPE $type_sql")
            end
        elseif op isa AlterColumnSetStatistics
            col_name = quote_identifier(dialect, op.column)
            push!(op_parts, "ALTER COLUMN $col_name SET STATISTICS $(op.target)")
        elseif op isa AlterColumnSetStorage
            col_name = quote_identifier(dialect, op.column)
            storage_mode = uppercase(string(op.storage))
            push!(op_parts, "ALTER COLUMN $col_name SET STORAGE $storage_mode")
        else
            error("Unknown ALTER TABLE operation: $(typeof(op))")
        end
    end

    push!(parts, Base.join(op_parts, ", "))
    sql = Base.join(parts, " ")

    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
                 ddl::DropTable)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    parts = ["DROP TABLE"]

    if ddl.if_exists
        push!(parts, "IF EXISTS")
    end

    table = quote_identifier(dialect, ddl.table)
    push!(parts, table)

    if ddl.cascade
        push!(parts, "CASCADE")
    end

    sql = Base.join(parts, " ")

    return (sql, params)
end

"""
    compile(dialect::PostgreSQLDialect, ddl::CreateIndex) -> (String, Vector{Symbol})

Compile a CREATE INDEX statement to SQL for PostgreSQL.

Supports:

  - Column indexes
  - Expression indexes
  - Partial indexes (WHERE clause)
  - Unique indexes
  - Index methods (BTREE, HASH, GIN, GIST, BRIN, SP-GIST)

# Example

```julia
# Column index
ddl = create_index(:idx_users_email, :users, [:email]; unique = true)
sql, params = compile(PostgreSQLDialect(), ddl)
# sql → "CREATE UNIQUE INDEX \"idx_users_email\" ON \"users\" (\"email\")"

# Expression index
ddl = create_index(:idx_users_lower_email, :users, Symbol[];
                   expr = [func(:lower, [col(:users, :email)])])
sql, params = compile(PostgreSQLDialect(), ddl)
# sql → "CREATE INDEX \"idx_users_lower_email\" ON \"users\" (lower(\"users\".\"email\"))"

# GIN index for JSONB
ddl = create_index(:idx_users_tags, :users, [:tags]; method = :gin)
sql, params = compile(PostgreSQLDialect(), ddl)
# sql → "CREATE INDEX \"idx_users_tags\" ON \"users\" USING GIN (\"tags\")"
```
"""
function compile(dialect::PostgreSQLDialect,
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

    # Index method (PostgreSQL-specific)
    if ddl.method !== nothing
        method_str = uppercase(string(ddl.method))
        push!(parts, "USING $method_str")
    end

    # Index columns or expressions
    if ddl.expressions !== nothing
        # Expression index
        exprs = [compile_expr(dialect, expr, params) for expr in ddl.expressions]
        exprs_str = Base.join(exprs, ", ")
        push!(parts, "($exprs_str)")
    else
        # Column index
        columns = [quote_identifier(dialect, col) for col in ddl.columns]
        columns_str = Base.join(columns, ", ")
        push!(parts, "($columns_str)")
    end

    # Partial index support (WHERE clause)
    if ddl.where !== nothing
        where_sql = compile_expr(dialect, ddl.where, params)
        push!(parts, "WHERE $where_sql")
    end

    sql = Base.join(parts, " ")

    return (sql, params)
end

function compile(dialect::PostgreSQLDialect,
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
