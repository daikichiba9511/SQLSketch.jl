"""
# Query AST

This module defines the query abstract syntax tree (AST) for SQLSketch.

Queries represent complete SQL statements (SELECT, INSERT, UPDATE, DELETE)
as structured, composable values.

## Design Principles

- Queries follow SQL's **logical evaluation order** (FROM → WHERE → SELECT → ORDER BY → LIMIT)
- Output SQL follows SQL's **syntactic order**
- Most operations are **shape-preserving** (only `select` changes the output type)
- Queries are built via a pipeline API using `|>`

## Query Types

- `From{T}` – table source
- `Where{T}` – filter condition (shape-preserving)
- `Join{T}` – join operation (shape-preserving)
- `Select{OutT}` – projection (shape-changing)
- `OrderBy{T}` – ordering (shape-preserving)
- `Limit{T}` – limit/offset (shape-preserving)

## Usage

```julia
q = from(:users) |>
    where(col(:users, :active) == true) |>
    select(NamedTuple, col(:users, :id), col(:users, :email)) |>
    order_by(col(:users, :created_at), desc=true) |>
    limit(10)
```

See `docs/design.md` Section 6 for detailed design rationale.
"""

# TODO: Implement query AST types and pipeline API
# This is Phase 2 of the roadmap

"""
Abstract base type for all query nodes.

Each query node is parameterized by its output type `T`.
"""
abstract type Query{T} end

# Placeholder implementations - to be completed in Phase 2

# TODO: Implement From{T}
# TODO: Implement Where{T}
# TODO: Implement Join{T}
# TODO: Implement Select{OutT}
# TODO: Implement OrderBy{T}
# TODO: Implement Limit{T}
# TODO: Implement Offset{T}
# TODO: Implement Distinct{T}
# TODO: Implement GroupBy{T}
# TODO: Implement Having{T}

# TODO: Implement pipeline API
# from(table::Symbol) -> From{NamedTuple}
# where(q::Query, expr::Expr) -> Where{T}
# select(q::Query, OutT::Type, fields...) -> Select{OutT}
# order_by(q::Query, field::Expr; desc=false) -> OrderBy{T}
# limit(q::Query, n::Int) -> Limit{T}
