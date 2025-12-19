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

# Core modules
include("Core/expr.jl")
include("Core/query.jl")
include("Core/dialect.jl")
include("Core/driver.jl")
include("Core/codec.jl")
include("Core/execute.jl")
include("Core/transaction.jl")
include("Core/migrations.jl")

# Dialect implementations
include("Dialects/sqlite.jl")

# Driver implementations
include("Drivers/sqlite.jl")

# Re-export Core APIs
# TODO: Add exports as APIs are implemented

end # module SQLSketch
