"""
# MySQL Dialect

MySQL/MariaDB dialect implementation for SQLSketch.

This dialect generates MySQL-compatible SQL from query and expression ASTs.

## Characteristics

- Identifier quoting: backticks (`` `identifier` ``)
- Placeholder syntax: `?` (positional)
- Rich DDL capabilities with some differences from PostgreSQL
- JSON support (MySQL 5.7+, MariaDB 10.2+)

## Supported Capabilities

- ✓ Basic SELECT/INSERT/UPDATE/DELETE
- ✓ Window functions (MySQL 8.0+)
- ✓ CTE (WITH clause, MySQL 8.0+)
- ✓ UPSERT (ON DUPLICATE KEY UPDATE)
- ✓ RETURNING clause (MariaDB 10.5+, MySQL not yet)
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
using JSON3

# Shared helper functions (resolve_placeholders, contains_placeholder, get_primary_table)
# are included in the main SQLSketch module before dialects

"""
    MySQLDialect(version::VersionNumber = v"8.0.0")

MySQL/MariaDB dialect for SQL generation.

# Fields

  - `version`: MySQL version (affects capability reporting)

# Example

```julia
dialect = MySQLDialect()
sql, params = compile(dialect, query)
```
"""
struct MySQLDialect <: Dialect
    version::VersionNumber
end

# Default constructor uses MySQL 8.0 (recent stable version)
MySQLDialect() = MySQLDialect(v"8.0.0")

#
# Helper Functions
#

"""
    quote_identifier(dialect::MySQLDialect, name::Symbol) -> String

Quote an identifier using MySQL backtick syntax.

# Example

```julia
quote_identifier(MySQLDialect(), :users) # → "`users`"
```
"""
function quote_identifier(dialect::MySQLDialect, name::Symbol)::String
    # Escape backticks by doubling them
    name_str = string(name)
    escaped = replace(name_str, "`" => "``")
    return "`$escaped`"
end

"""
    placeholder(dialect::MySQLDialect, idx::Int) -> String

Generate a positional parameter placeholder.

MySQL uses `?` for all positional parameters.

# Example

```julia
placeholder(MySQLDialect(), 1) # → "?"
placeholder(MySQLDialect(), 2) # → "?"
```
"""
function placeholder(dialect::MySQLDialect, idx::Int)::String
    return "?"
end

"""
    supports(dialect::MySQLDialect, cap::Capability) -> Bool

Check if MySQL supports a specific capability.

# Example

```julia
supports(MySQLDialect(), CAP_CTE)     # → true (MySQL 8.0+)
supports(MySQLDialect(), CAP_WINDOW)  # → true (MySQL 8.0+)
supports(MySQLDialect(), CAP_LATERAL) # → false
```
"""
function supports(dialect::MySQLDialect, cap::Capability)::Bool
    if cap == CAP_CTE
        # CTE (WITH clause) was added in MySQL 8.0
        return dialect.version >= v"8.0.0"
    elseif cap == CAP_RETURNING
        # RETURNING is not supported in MySQL (only MariaDB 10.5+)
        # For now, we return false for MySQL
        return false
    elseif cap == CAP_UPSERT
        # ON DUPLICATE KEY UPDATE is supported in all MySQL versions
        return true
    elseif cap == CAP_WINDOW
        # Window functions were added in MySQL 8.0
        return dialect.version >= v"8.0.0"
    elseif cap == CAP_LATERAL
        # LATERAL joins are not supported in MySQL
        return false
    elseif cap == CAP_BULK_COPY
        # LOAD DATA INFILE is available, but not COPY FROM
        return false
    elseif cap == CAP_SAVEPOINT
        # Savepoints are supported
        return true
    elseif cap == CAP_ADVISORY_LOCK
        # MySQL has GET_LOCK/RELEASE_LOCK functions
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
    compile_expr(dialect::MySQLDialect, expr::SQLExpr, params::Vector{Symbol}) -> String

Compile an expression AST into a SQL fragment.
"""
function compile_expr(dialect::MySQLDialect, expr::ColRef,
                      params::Vector{Symbol})::String
    table = quote_identifier(dialect, expr.table)
    column = quote_identifier(dialect, expr.column)
    return "$table.$column"
end

function compile_expr(dialect::MySQLDialect, expr::Literal,
                      params::Vector{Symbol})::String
    value = expr.value

    if value === nothing || value === missing
        return "NULL"
    elseif value isa Bool
        # MySQL uses 1/0 for booleans (TINYINT(1))
        return value ? "1" : "0"
    elseif value isa Number
        return string(value)
    elseif value isa AbstractString
        # Escape single quotes by doubling them
        escaped = replace(string(value), "'" => "''")
        return "'$escaped'"
    elseif value isa Dates.DateTime
        # MySQL DATETIME format: 'YYYY-MM-DD HH:MM:SS'
        formatted = Dates.format(value, "yyyy-mm-dd HH:MM:SS")
        return "'$formatted'"
    elseif value isa Dates.Date
        # MySQL DATE format: 'YYYY-MM-DD'
        formatted = Dates.format(value, "yyyy-mm-dd")
        return "'$formatted'"
    elseif value isa Dict
        # MySQL JSON format: '{"key": "value"}' (MySQL 5.7+)
        json_str = JSON3.write(value)
        escaped = replace(json_str, "'" => "''")
        return "'$escaped'"
    else
        error("Unsupported literal type: $(typeof(value))")
    end
end

function compile_expr(dialect::MySQLDialect, expr::Param,
                      params::Vector{Symbol})::String
    push!(params, expr.name)
    return placeholder(dialect, length(params))
end

# RawExpr: Return raw SQL without modification
function compile_expr(dialect::MySQLDialect, expr::RawExpr,
                      params::Vector{Symbol})::String
    return expr.sql
end

function compile_expr(dialect::MySQLDialect, expr::BinaryOp,
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
        # MySQL doesn't have ILIKE, emulate with UPPER
        return "(UPPER($left_sql) LIKE UPPER($right_sql))"
    elseif expr.op == :NOT_ILIKE
        return "(UPPER($left_sql) NOT LIKE UPPER($right_sql))"
    else
        string(expr.op)
    end

    return "($left_sql $op_str $right_sql)"
end

function compile_expr(dialect::MySQLDialect, expr::UnaryOp,
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

function compile_expr(dialect::MySQLDialect, expr::FuncCall,
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

function compile_expr(dialect::MySQLDialect, expr::PlaceholderField,
                      params::Vector{Symbol})::String
    error("PlaceholderField($(expr.column)) must be resolved to ColRef before compilation.")
end

function compile_expr(dialect::MySQLDialect, expr::BetweenOp,
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

function compile_expr(dialect::MySQLDialect, expr::InOp,
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

function compile_expr(dialect::MySQLDialect, expr::Cast,
                      params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, expr.expr, params)
    target_type = uppercase(string(expr.target_type))
    return "CAST($expr_sql AS $target_type)"
end

function compile_expr(dialect::MySQLDialect, expr::Subquery,
                      params::Vector{Symbol})::String
    subquery_sql, subquery_params = compile(dialect, expr.query)
    append!(params, subquery_params)
    return "($subquery_sql)"
end

function compile_expr(dialect::MySQLDialect, expr::CaseExpr,
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
    compile_window_frame(dialect::MySQLDialect, frame::WindowFrame) -> String

Compile a window frame specification into SQL.
"""
function compile_window_frame(dialect::MySQLDialect, frame::WindowFrame)::String
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

function compile_expr(dialect::MySQLDialect, expr::WindowFunc,
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
    compile(dialect::MySQLDialect, query::Query) -> (String, Vector{Symbol})

Compile a Query AST into a SQL string and parameter list.
"""
function compile(dialect::MySQLDialect,
                 query::From{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "SELECT * FROM $table"
    return (sql, params)
end

function compile(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
                 query::Join{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    join_type = if query.kind == :inner
        "INNER JOIN"
    elseif query.kind == :left
        "LEFT JOIN"
    elseif query.kind == :right
        "RIGHT JOIN"
    elseif query.kind == :full
        # MySQL doesn't support FULL OUTER JOIN, warn user
        error("MySQL does not support FULL OUTER JOIN. Use UNION of LEFT and RIGHT JOIN instead.")
    else
        error("Unsupported join kind: $(query.kind)")
    end

    table = quote_identifier(dialect, query.table)
    on_sql = compile_expr(dialect, query.on, params)

    sql = "$source_sql $join_type $table ON $on_sql"
    return (sql, params)
end

function compile(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
                 query::Limit{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)
    sql = "$source_sql LIMIT $(query.n)"
    return (sql, params)
end

function compile(dialect::MySQLDialect,
                 query::Offset{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)
    sql = "$source_sql OFFSET $(query.n)"
    return (sql, params)
end

function compile(dialect::MySQLDialect,
                 query::Distinct{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    if startswith(source_sql, "SELECT ")
        sql = "SELECT DISTINCT" * source_sql[7:end]
    else
        sql = "SELECT DISTINCT * FROM ($source_sql) AS sub"
    end

    return (sql, params)
end

function compile(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
                 query::Having{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)
    condition_sql = compile_expr(dialect, query.condition, params)
    sql = "$source_sql HAVING $condition_sql"
    return (sql, params)
end

#
# DML Compilation
#

function compile(dialect::MySQLDialect,
                 query::InsertInto{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    columns = [quote_identifier(dialect, col) for col in query.columns]
    columns_str = Base.join(columns, ", ")
    sql = "INSERT INTO $table ($columns_str)"
    return (sql, params)
end

function compile(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
                 query::Update{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "UPDATE $table"
    return (sql, params)
end

function compile(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
                 query::UpdateWhere{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    table = get_primary_table(query.source)
    resolved_condition = resolve_placeholders(query.condition, table)
    condition_sql = compile_expr(dialect, resolved_condition, params)

    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

function compile(dialect::MySQLDialect,
                 query::DeleteFrom{T})::Tuple{String, Vector{Symbol}} where {T}
    params = Symbol[]
    table = quote_identifier(dialect, query.table)
    sql = "DELETE FROM $table"
    return (sql, params)
end

function compile(dialect::MySQLDialect,
                 query::DeleteWhere{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    table = get_primary_table(query.source)
    resolved_condition = resolve_placeholders(query.condition, table)
    condition_sql = compile_expr(dialect, resolved_condition, params)

    sql = "$source_sql WHERE $condition_sql"
    return (sql, params)
end

#
# RETURNING Clause Compilation (MariaDB only)
#

function compile(dialect::MySQLDialect,
                 query::Returning{OutT})::Tuple{String, Vector{Symbol}} where {OutT}
    # RETURNING is not supported in MySQL, only in MariaDB 10.5+
    # For now, we'll generate the SQL but note that it won't work in MySQL
    if dialect.version < v"10.5.0"
        @warn "RETURNING clause is only supported in MariaDB 10.5+, not in MySQL"
    end

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
# ON CONFLICT (UPSERT) Compilation - MySQL uses ON DUPLICATE KEY UPDATE
#

function compile(dialect::MySQLDialect,
                 query::OnConflict{T})::Tuple{String, Vector{Symbol}} where {T}
    source_sql, params = compile(dialect, query.source)

    if query.action == :DO_NOTHING
        # MySQL doesn't have "DO NOTHING" syntax
        # We can emulate it with IGNORE
        # Replace "INSERT INTO" with "INSERT IGNORE INTO"
        if startswith(source_sql, "INSERT INTO")
            sql = replace(source_sql, "INSERT INTO" => "INSERT IGNORE INTO"; count = 1)
            return (sql, params)
        else
            error("ON CONFLICT DO NOTHING can only be used with INSERT statements")
        end
    elseif query.action == :DO_UPDATE
        # MySQL uses ON DUPLICATE KEY UPDATE instead of ON CONFLICT
        # Note: MySQL doesn't support specifying target columns
        if query.target !== nothing && !isempty(query.target)
            @warn "MySQL's ON DUPLICATE KEY UPDATE does not support target column specification. The target will be determined by PRIMARY KEY or UNIQUE constraints."
        end

        set_parts = String[]
        for (col, expr) in query.updates
            col_name = quote_identifier(dialect, col)
            expr_sql = compile_expr(dialect, expr, params)
            push!(set_parts, "$col_name = $expr_sql")
        end

        upsert_sql = "ON DUPLICATE KEY UPDATE " * Base.join(set_parts, ", ")

        if query.where_clause !== nothing
            @warn "MySQL's ON DUPLICATE KEY UPDATE does not support WHERE clause in the UPDATE part. The WHERE clause will be ignored."
        end

        sql = "$source_sql $upsert_sql"
        return (sql, params)
    else
        error("Invalid ON CONFLICT action: $(query.action)")
    end
end

#
# CTE Compilation
#

function compile(dialect::MySQLDialect,
                 query::With{T})::Tuple{String, Vector{Symbol}} where {T}
    # CTE requires MySQL 8.0+
    if dialect.version < v"8.0.0"
        error("CTE (WITH clause) requires MySQL 8.0 or later")
    end

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

function compile(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
                 query::SetIntersect{T})::Tuple{String, Vector{Symbol}} where {T}
    # MySQL doesn't support INTERSECT directly (even in 8.0)
    # We'd need to emulate it with JOIN or EXISTS
    error("MySQL does not support INTERSECT. Use INNER JOIN with DISTINCT instead.")
end

function compile(dialect::MySQLDialect,
                 query::SetExcept{T})::Tuple{String, Vector{Symbol}} where {T}
    # MySQL doesn't support EXCEPT directly (even in 8.0)
    # We'd need to emulate it with LEFT JOIN WHERE NULL or NOT EXISTS
    error("MySQL does not support EXCEPT. Use LEFT JOIN with WHERE IS NULL instead.")
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
    compile_column_type(dialect::MySQLDialect, type::Symbol) -> String

Map portable column types to MySQL types.
"""
function compile_column_type(dialect::MySQLDialect, type::Symbol)::String
    if type == :integer
        return "INT"
    elseif type == :bigint
        return "BIGINT"
    elseif type == :real
        return "DOUBLE"
    elseif type == :text
        return "TEXT"
    elseif type == :varchar
        return "VARCHAR(255)"  # Default length 255 (can be indexed)
    elseif type == :blob
        return "BLOB"
    elseif type == :boolean
        return "TINYINT(1)"  # MySQL convention for boolean
    elseif type == :timestamp
        return "DATETIME"
    elseif type == :date
        return "DATE"
    elseif type == :uuid
        return "CHAR(36)"  # UUIDs stored as CHAR(36)
    elseif type == :json
        return "JSON"  # MySQL 5.7+
    else
        error("Unknown column type: $type")
    end
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::PrimaryKeyConstraint,
                                   params::Vector{Symbol})::String
    return "PRIMARY KEY"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::NotNullConstraint,
                                   params::Vector{Symbol})::String
    return "NOT NULL"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::UniqueConstraint,
                                   params::Vector{Symbol})::String
    return "UNIQUE"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::DefaultConstraint,
                                   params::Vector{Symbol})::String
    value_sql = compile_expr(dialect, constraint.value, params)
    return "DEFAULT $value_sql"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::CheckConstraint,
                                   params::Vector{Symbol})::String
    # CHECK constraints are supported in MySQL 8.0.16+
    condition_sql = compile_expr(dialect, constraint.condition, params)
    return "CHECK ($condition_sql)"
end

function compile_column_constraint(dialect::MySQLDialect,
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

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::AutoIncrementConstraint,
                                   params::Vector{Symbol})::String
    return "AUTO_INCREMENT"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::GeneratedConstraint,
                                   params::Vector{Symbol})::String
    expr_sql = compile_expr(dialect, constraint.expr, params)
    storage = constraint.stored ? "STORED" : "VIRTUAL"
    return "GENERATED ALWAYS AS ($expr_sql) $storage"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::CollationConstraint,
                                   params::Vector{Symbol})::String
    return "COLLATE $(constraint.collation)"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::OnUpdateConstraint,
                                   params::Vector{Symbol})::String
    # MySQL supports ON UPDATE for TIMESTAMP/DATETIME columns
    value_sql = compile_expr(dialect, constraint.value, params)
    return "ON UPDATE $value_sql"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::CommentConstraint,
                                   params::Vector{Symbol})::String
    # MySQL supports COMMENT in column definition
    escaped = replace(constraint.comment, "'" => "''")
    return "COMMENT '$escaped'"
end

function compile_column_constraint(dialect::MySQLDialect,
                                   constraint::IdentityConstraint,
                                   params::Vector{Symbol})::String
    # MySQL doesn't have IDENTITY, use AUTO_INCREMENT instead
    @warn "IDENTITY constraint is not supported in MySQL, using AUTO_INCREMENT instead"
    return "AUTO_INCREMENT"
end

function compile_column_def(dialect::MySQLDialect, column::ColumnDef,
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

function compile_table_constraint(dialect::MySQLDialect,
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

function compile_table_constraint(dialect::MySQLDialect,
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

function compile_table_constraint(dialect::MySQLDialect,
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

function compile_table_constraint(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
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

function compile(dialect::MySQLDialect,
                 ddl::AlterTable)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    if isempty(ddl.operations)
        error("AlterTable must have at least one operation")
    end

    # MySQL supports multiple operations in one ALTER TABLE
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
            push!(op_parts, "MODIFY COLUMN $col_name NOT NULL")
        elseif op isa AlterColumnDropNotNull
            col_name = quote_identifier(dialect, op.column)
            push!(op_parts, "MODIFY COLUMN $col_name NULL")
        elseif op isa AlterColumnSetType
            col_name = quote_identifier(dialect, op.column)
            type_sql = compile_column_type(dialect, op.type)
            if op.using_expr !== nothing
                @warn "MySQL ALTER COLUMN TYPE does not support USING clause, ignoring"
            end
            push!(op_parts, "MODIFY COLUMN $col_name $type_sql")
        elseif op isa AlterColumnSetStatistics
            @warn "MySQL does not support ALTER COLUMN SET STATISTICS (PostgreSQL-specific)"
        elseif op isa AlterColumnSetStorage
            @warn "MySQL does not support ALTER COLUMN SET STORAGE (PostgreSQL-specific)"
        else
            error("Unknown ALTER TABLE operation: $(typeof(op))")
        end
    end

    push!(parts, Base.join(op_parts, ", "))
    sql = Base.join(parts, " ")

    return (sql, params)
end

function compile(dialect::MySQLDialect,
                 ddl::DropTable)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    parts = ["DROP TABLE"]

    if ddl.if_exists
        push!(parts, "IF EXISTS")
    end

    table = quote_identifier(dialect, ddl.table)
    push!(parts, table)

    if ddl.cascade
        # MySQL doesn't support CASCADE in DROP TABLE, but FOREIGN_KEY_CHECKS can be used
        @warn "MySQL does not support CASCADE in DROP TABLE. Consider using SET FOREIGN_KEY_CHECKS=0."
    end

    sql = Base.join(parts, " ")

    return (sql, params)
end

function compile(dialect::MySQLDialect,
                 ddl::CreateIndex)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    parts = ["CREATE"]

    if ddl.unique
        push!(parts, "UNIQUE")
    end

    push!(parts, "INDEX")

    # MySQL doesn't support IF NOT EXISTS for CREATE INDEX (before MySQL 5.7)
    # MySQL 5.7+ supports it
    if ddl.if_not_exists && dialect.version >= v"5.7.0"
        push!(parts, "IF NOT EXISTS")
    elseif ddl.if_not_exists
        @warn "IF NOT EXISTS for CREATE INDEX requires MySQL 5.7+, ignoring"
    end

    name = quote_identifier(dialect, ddl.name)
    push!(parts, name)

    push!(parts, "ON")

    table = quote_identifier(dialect, ddl.table)
    push!(parts, table)

    # Index method (USING clause)
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

    # MySQL doesn't support partial indexes (WHERE clause) directly
    # This is a PostgreSQL feature
    if ddl.where !== nothing
        @warn "MySQL does not support partial indexes (WHERE clause). Use generated columns with indexes instead."
    end

    sql = Base.join(parts, " ")

    return (sql, params)
end

function compile(dialect::MySQLDialect,
                 ddl::DropIndex)::Tuple{String, Vector{Symbol}}
    params = Symbol[]

    parts = ["DROP INDEX"]

    # MySQL supports IF EXISTS for DROP INDEX (MySQL 5.7+)
    if ddl.if_exists && dialect.version >= v"5.7.0"
        push!(parts, "IF EXISTS")
    elseif ddl.if_exists
        @warn "IF EXISTS for DROP INDEX requires MySQL 5.7+, ignoring"
    end

    name = quote_identifier(dialect, ddl.name)
    push!(parts, name)

    # Note: MySQL's DROP INDEX syntax requires ON table_name
    # But our DDL structure doesn't store the table name
    # This is a limitation - we'll document it
    @warn "MySQL DROP INDEX requires ON table_name, but table is not stored in DropIndex. Use ALTER TABLE ... DROP INDEX instead."

    sql = Base.join(parts, " ")

    return (sql, params)
end
