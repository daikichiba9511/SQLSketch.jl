"""
# Placeholder Syntactic Sugar

This module provides optional syntactic sugar for single-table queries via
the `p_` placeholder syntax.

## Design Philosophy

Placeholders are **optional convenience features** in the Easy layer:
- They simplify single-table queries
- They are resolved to explicit `ColRef` during compilation
- The Core layer never depends on placeholders

## Usage

```julia
using SQLSketch

# Instead of explicit table references:
from(:users) |>
where(col(:users, :email) == param(String, :email))

# You can use placeholders:
from(:users) |>
where(p_.email == param(String, :email))
```

## Implementation Note

Placeholders are resolved in the dialect compilation layer via
`resolve_placeholders()` in shared_helpers.jl.
"""

# Import Core types using relative path
# We're in SQLSketch.Extras, so ..Core refers to SQLSketch.Core
using ..Core: SQLExpr

# ============================================================================ #
# Types
# ============================================================================ #

"""
    PlaceholderField(column::Symbol)

Represents a placeholder field reference (e.g., `p_.email`).

This is syntactic sugar that gets resolved to a `ColRef` during query compilation.
The table name is inferred from the query context.

# Fields

  - `column::Symbol` – column name

# Example

```julia
where(p_.email == param(String, :email))
# Resolves to: where(col(:users, :email) == param(String, :email))
# (assuming FROM users context)
```

# Notes

Placeholders are **optional syntactic sugar**. The Core layer always accepts
explicit `ColRef` expressions. Placeholders simplify single-table queries but
may be ambiguous in multi-table JOINs.

See `docs/design.md` Section 9 for design rationale.
"""
struct PlaceholderField <: SQLExpr
    column::Symbol
end

"""
    Placeholder

Placeholder type for syntactic sugar. Use via the exported constant `p_`.

# Example

```julia
# Instead of:
where(col(:users, :email) == param(String, :email))

# You can write:
where(p_.email == param(String, :email))
```

The table name is automatically inferred from the query context.

Note: Uses `p_` because Julia reserves underscore-only identifiers
for write-only variables.
"""
struct Placeholder end

"""
    const p_ = Placeholder()

Global placeholder constant for convenient field access.

Note: Uses `p_` instead of `_` because Julia reserves underscore-only
identifiers for write-only variables.

# Usage

```julia
from(:users) |>
where(p_.age > literal(18)) |>
select(NamedTuple, p_.id, p_.email)
```

Internally, `p_.column` creates a `PlaceholderField(:column)` which is resolved
to `ColRef(table, :column)` during query compilation.
"""
const p_ = Placeholder()

# ============================================================================ #
# Property access
# ============================================================================ #

"""
    Base.getproperty(::Placeholder, name::Symbol) -> PlaceholderField

Enables `p_.column` syntax for placeholder field access.
"""
Base.getproperty(::Placeholder, name::Symbol)::PlaceholderField = PlaceholderField(name)

# ============================================================================ #
# Equality and hashing (for Dict/Set support)
# ============================================================================ #

Base.isequal(a::PlaceholderField, b::PlaceholderField)::Bool = a.column == b.column
Base.hash(a::PlaceholderField, h::UInt)::UInt = hash(a.column, h)
