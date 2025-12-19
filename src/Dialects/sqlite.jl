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

# TODO: Implement SQLiteDialect
# This is Phase 3 of the roadmap

# Placeholder implementation - to be completed in Phase 3

# struct SQLiteDialect <: Dialect
#     # SQLite version info for capability checks
#     version::VersionNumber
# end
#
# SQLiteDialect() = SQLiteDialect(v"3.35.0")  # Default to recent version
#
# # Implement Dialect interface:
# # - compile(dialect::SQLiteDialect, query::Query)
# # - compile_expr(dialect::SQLiteDialect, expr::Expr)
# # - quote_identifier(dialect::SQLiteDialect, name::Symbol)
# # - placeholder(dialect::SQLiteDialect, idx::Int)
# # - supports(dialect::SQLiteDialect, cap::Capability)
