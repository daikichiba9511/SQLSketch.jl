"""
# SQLSketch.jl

An experimental typed SQL query builder for Julia, exploring the design of a
composable SQL core with minimal hidden magic.

## Design Philosophy

  - SQL is always visible and inspectable
  - Query APIs follow SQL's logical evaluation order
  - Output SQL follows SQL's syntactic order
  - Strong typing at query boundaries
  - Clear separation between core primitives and convenience layers

## Architecture

SQLSketch is designed as a two-layer system:

  - **Core Layer**: Essential primitives for building, compiling, and executing SQL
  - **Easy Layer** (future): Optional convenience abstractions

This module re-exports the Core layer APIs.

See `docs/design.md` for detailed design rationale.
See `docs/roadmap.md` for implementation plan.
"""
module SQLSketch

# Core submodule
module Core
# Expression AST (Phase 1)
include("Core/expr.jl")
export SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall, BetweenOp, InOp
export Cast, Subquery
export PlaceholderField, Placeholder, p_
export col, literal, param, func
export is_null, is_not_null
export like, not_like, ilike, not_ilike
export between, not_between
export in_list, not_in_list
export cast, subquery, exists, not_exists, in_subquery, not_in_subquery

# Query AST (Phase 2 + DML)
include("Core/query.jl")
export Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy, Having, Join
export InsertInto, InsertValues, Update, UpdateSet, UpdateWhere, DeleteFrom, DeleteWhere
export from, where, select, order_by, limit, offset, distinct, group_by, having, join
export insert_into, values, update, set, delete_from

# Dialect abstraction (Phase 3)
include("Core/dialect.jl")
export Dialect, Capability
export CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW, CAP_LATERAL, CAP_BULK_COPY,
       CAP_SAVEPOINT, CAP_ADVISORY_LOCK
export compile, compile_expr, quote_identifier, placeholder, supports

# Driver abstraction (Phase 4)
include("Core/driver.jl")
export Driver, Connection
export connect, execute

# CodecRegistry (Phase 5)
include("Core/codec.jl")
export Codec, CodecRegistry
export encode, decode
export register!, get_codec
export map_row
export IntCodec, Float64Codec, StringCodec, BoolCodec
export DateCodec, DateTimeCodec, UUIDCodec

# Query Execution (Phase 6)
include("Core/execute.jl")
export fetch_all, fetch_one, fetch_maybe
export sql, explain, execute_dml
end

# Dialect implementations
include("Dialects/sqlite.jl")

# Driver implementations
module Drivers
using ..Core: Driver, Connection, connect, execute
include("Drivers/sqlite.jl")
export SQLiteDriver, SQLiteConnection
end

# Re-export everything from Core for convenience
using .Core
export SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall, BetweenOp, InOp
export Cast, Subquery
export PlaceholderField, Placeholder, p_
export col, literal, param, func
export is_null, is_not_null
export like, not_like, ilike, not_ilike
export between, not_between
export in_list, not_in_list
export cast, subquery, exists, not_exists, in_subquery, not_in_subquery
export Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy, Having, Join
export InsertInto, InsertValues, Update, UpdateSet, UpdateWhere, DeleteFrom, DeleteWhere
export from, where, select, order_by, limit, offset, distinct, group_by, having, join
export insert_into, values, update, set, delete_from
export Dialect, Capability
export CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW, CAP_LATERAL, CAP_BULK_COPY,
       CAP_SAVEPOINT, CAP_ADVISORY_LOCK
export compile, compile_expr, quote_identifier, placeholder, supports
export Driver, Connection
export connect, execute
export Codec, CodecRegistry
export encode, decode
export register!, get_codec
export map_row
export IntCodec, Float64Codec, StringCodec, BoolCodec
export DateCodec, DateTimeCodec, UUIDCodec

# Query execution (Phase 6)
export fetch_all, fetch_one, fetch_maybe
export sql, explain, execute_dml

# Export Dialect implementations
export SQLiteDialect

# Re-export Driver implementations
using .Drivers
export SQLiteDriver, SQLiteConnection

end # module SQLSketch
