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
    export SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall
    export col, literal, param, func
    export is_null, is_not_null

    # Query AST (Phase 2)
    include("Core/query.jl")
    export Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy, Having, Join
    export from, where, select, order_by, limit, offset, distinct, group_by, having, join

    # Dialect abstraction (Phase 3)
    include("Core/dialect.jl")
    export Dialect, Capability
    export CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW, CAP_LATERAL, CAP_BULK_COPY, CAP_SAVEPOINT, CAP_ADVISORY_LOCK
    export compile, compile_expr, quote_identifier, placeholder, supports

    # Driver abstraction (Phase 4)
    include("Core/driver.jl")
    export Driver, Connection
    export connect, execute
end

# Dialect implementations
include("Dialects/sqlite.jl")

# Driver implementations
module Drivers
    using SQLite
    using DBInterface
    using ..Core
    include("Drivers/sqlite.jl")
    export SQLiteDriver, SQLiteConnection
end

# Re-export everything from Core for convenience
using .Core
export SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall
export col, literal, param, func
export is_null, is_not_null
export Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy, Having, Join
export from, where, select, order_by, limit, offset, distinct, group_by, having, join
export Dialect, Capability
export CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW, CAP_LATERAL, CAP_BULK_COPY, CAP_SAVEPOINT, CAP_ADVISORY_LOCK
export compile, compile_expr, quote_identifier, placeholder, supports
export Driver, Connection
export connect, execute

# Export Dialect implementations
export SQLiteDialect

# Re-export Driver implementations
using .Drivers
export SQLiteDriver, SQLiteConnection

end # module SQLSketch
