"""
# Dialect Abstraction

This module defines the Dialect abstraction for SQLSketch.

A Dialect represents a database's SQL syntax and semantic differences.
Dialects are responsible for compiling Query ASTs and Expression ASTs
into database-specific SQL strings.

## Design Principles

- Dialects are **pure** – they do not manage connections or execute SQL
- Dialects handle SQL generation, identifier quoting, and placeholder syntax
- Dialects report supported features via a capability system
- Dialect implementations are independent of driver/client libraries

## Responsibilities

- Generate SQL strings from query ASTs
- Quote identifiers (tables, columns, aliases)
- Define placeholder syntax (`?`, `\$1`, etc.)
- Compile DDL statements
- Report supported features via capabilities

## Usage

```julia
dialect = SQLiteDialect()
sql, params = compile(dialect, query)
# sql    → "SELECT id, email FROM users WHERE active = ?"
# params → [:active]
```

See `docs/design.md` Section 10 for detailed design rationale.
"""

# TODO: Implement Dialect abstraction
# This is Phase 3 of the roadmap

"""
Abstract base type for all SQL dialects.

Dialect implementations must define:
- `compile(dialect, query)` → (sql::String, params::Vector{Symbol})
- `compile_expr(dialect, expr)` → sql_fragment::String
- `quote_identifier(dialect, name)` → quoted::String
- `placeholder(dialect, idx)` → placeholder::String
- `supports(dialect, capability)` → Bool
"""
abstract type Dialect end

# Capability enum
"""
Database capabilities that may or may not be supported by a given dialect.

# Capabilities
- `CAP_CTE` – Common Table Expressions (WITH clause)
- `CAP_RETURNING` – RETURNING clause in INSERT/UPDATE/DELETE
- `CAP_UPSERT` – ON CONFLICT / ON DUPLICATE KEY UPDATE
- `CAP_WINDOW` – Window functions
- `CAP_LATERAL` – LATERAL joins
- `CAP_BULK_COPY` – COPY FROM / LOAD DATA operations
- `CAP_SAVEPOINT` – Transaction savepoints
- `CAP_ADVISORY_LOCK` – Advisory locks
"""
@enum Capability begin
    CAP_CTE
    CAP_RETURNING
    CAP_UPSERT
    CAP_WINDOW
    CAP_LATERAL
    CAP_BULK_COPY
    CAP_SAVEPOINT
    CAP_ADVISORY_LOCK
end

# Placeholder functions - to be completed in Phase 3

# TODO: Implement compile(dialect::Dialect, query::Query)
# TODO: Implement compile_expr(dialect::Dialect, expr::Expr)
# TODO: Implement quote_identifier(dialect::Dialect, name::Symbol)
# TODO: Implement placeholder(dialect::Dialect, idx::Int)
# TODO: Implement supports(dialect::Dialect, cap::Capability)
