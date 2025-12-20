"""
# Shared Dialect Helper Functions

Common utility functions used by multiple dialect implementations.
These include placeholder resolution and primary table extraction.
"""

using ..Core: SQLExpr, PlaceholderField, ColRef, Literal, Param, BinaryOp, UnaryOp,
              FuncCall,
              BetweenOp, InOp, Cast, Subquery, CaseExpr, WindowFunc, Over
using ..Core: Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy, Having,
              Join
using ..Core: InsertInto, InsertValues, Update, UpdateSet, UpdateWhere, DeleteFrom,
              DeleteWhere

#
# Placeholder Resolution
#

"""
    resolve_placeholders(expr::SQLExpr, table::Symbol) -> SQLExpr

Resolve PlaceholderField expressions to ColRef expressions using the given table name.
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
    return expr
end

function resolve_placeholders(expr::CaseExpr, table::Symbol)::CaseExpr
    resolved_whens = Tuple{SQLExpr, SQLExpr}[(resolve_placeholders(cond, table),
                                              resolve_placeholders(result, table))
                                             for (cond, result) in expr.whens]
    resolved_else = if expr.else_expr === nothing
        nothing
    else
        resolve_placeholders(expr.else_expr, table)
    end
    return CaseExpr(resolved_whens, resolved_else)
end

function resolve_placeholders(expr::WindowFunc, table::Symbol)::WindowFunc
    resolved_args = [resolve_placeholders(arg, table) for arg in expr.args]
    resolved_partition_by = [resolve_placeholders(p, table) for p in expr.over.partition_by]
    resolved_order_by = [(resolve_placeholders(e, table), desc)
                         for (e, desc) in expr.over.order_by]
    resolved_over = Over(resolved_partition_by, resolved_order_by, expr.over.frame)
    return WindowFunc(expr.name, resolved_args, resolved_over)
end

#
# Placeholder Detection
#

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
    return false
end

function contains_placeholder(expr::CaseExpr)::Bool
    for (cond, result) in expr.whens
        if contains_placeholder(cond) || contains_placeholder(result)
            return true
        end
    end
    if expr.else_expr !== nothing && contains_placeholder(expr.else_expr)
        return true
    end
    return false
end

function contains_placeholder(expr::WindowFunc)::Bool
    if any(contains_placeholder(arg) for arg in expr.args)
        return true
    end
    if any(contains_placeholder(p) for p in expr.over.partition_by)
        return true
    end
    if any(contains_placeholder(e) for (e, _) in expr.over.order_by)
        return true
    end
    return false
end

#
# Primary Table Extraction
#

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
    return nothing
end

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
