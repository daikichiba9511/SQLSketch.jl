# SQLSketch.jl

A type-safe, composable SQL query builder for Julia with PostgreSQL as the primary target.

## Overview

SQLSketch.jl provides a fluent API for constructing SQL queries that are checked at compile time while remaining transparent and inspectable. It's designed with PostgreSQL as the first-class target, supporting rich native types (UUID, JSONB, ARRAY) and advanced SQL features.

Key features:

- **Type-safe query building** - Output types tracked through the pipeline
- **SQL transparency** - All queries inspectable before execution
- **Shape-preserving semantics** - Predictable type transformations
- **PostgreSQL-first** - Full support for PostgreSQL features
- **Composable API** - Natural pipeline syntax with currying
- **Transaction support** - First-class transaction and savepoint handling
- **Migration system** - Timestamp-based migrations with checksums
- **DDL support** - Create tables, indexes, and constraints

## Quick Example

```julia
using SQLSketch
using SQLSketch.Drivers: PostgreSQLDriver

# Connect to PostgreSQL
driver = PostgreSQLDriver("host=localhost dbname=mydb user=myuser")

# Type-safe query building
struct User
    id::Int64
    email::String
    created_at::DateTime
end

q = from(:users) |>
    where(col(:users, :active) == literal(true)) |>
    order_by(col(:users, :created_at); desc=true) |>
    limit(10) |>
    select(User,
           col(:users, :id),
           col(:users, :email),
           col(:users, :created_at))

# Execute and get typed results
users = fetch_all(driver, q)
# Vector{User}
```

## Design Philosophy

SQLSketch follows these core principles:

1. **Type Safety First** - Query output types are tracked at compile time
2. **SQL Transparency** - Never hide the SQL; always inspectable
3. **Explicit over Implicit** - No magic; clear intent
4. **PostgreSQL-First** - Leverage PostgreSQL's rich feature set
5. **Test-Driven** - Comprehensive tests, database-optional when possible

See [Design](design.md) for detailed design rationale.

## Architecture: Core vs Extras

SQLSketch is structured in **two layers** with distinct purposes:

### Core Layer - Minimal, Explicit, Stable

The Core layer provides the **essential building blocks** for SQL interaction:

- **Query and Expression AST** - Type-safe query construction
- **Dialect abstraction** - PostgreSQL, SQLite support
- **Driver abstraction** - Connection and execution
- **CodecRegistry** - Type conversion between Julia and SQL
- **Transaction management** - ACID guarantees
- **DDL operations** - Schema creation and modification

**Core principles:**
- ✅ Type safety over convenience
- ✅ Explicit over implicit
- ✅ No magic, no hidden behavior
- ✅ All operations are inspectable
- ✅ Minimal dependencies

**Example - Core only:**

```julia
using SQLSketch.Core

# Explicit query construction
q = from(:users) |>
    where(col(:users, :id) == literal(42)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

# Execute with explicit connection
users = fetch_all(driver, q)
```

### Extras Layer - Convenient, Optional, Replaceable

The Extras layer provides **convenience features** built **on top of Core**:

**Current Extras:**
- **Placeholder syntax** (`p_`) - Syntactic sugar for single-table queries
- **Migration runner** - Timestamp-based schema migrations

**Future Extras (planned):**
- Repository pattern helpers
- CRUD shortcuts
- Query builder macros
- Active Record-style wrappers

**Extras principles:**
- ✅ Built entirely on Core APIs
- ✅ Optional - can be replaced with custom implementations
- ✅ Convenience over purity
- ✅ Can use "magic" for ergonomics

**Example - Using Extras:**

```julia
using SQLSketch.Extras

# Placeholder syntax sugar
user_id = p_(:user_id, Int64)
q = from(:users) |>
    where(col(:users, :id) == user_id) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

# Execute with parameters
user = fetch_one(driver, q, user_id => 42)
```

**Why this separation?**

1. **Clarity of purpose**: Core is stable and minimal; Extras can evolve freely
2. **Replaceability**: Don't like the Extras? Build your own on Core
3. **Learning curve**: Start with Core for fundamentals, add Extras for productivity
4. **Maintenance**: Core stays focused; Extras can experiment

See [Design - Core vs Extras Layer](design.md#5-core-vs-extras-layer) for more details.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/daikichiba9511/SQLSketch.jl")
```

## Database Support

### PostgreSQL (Primary)

SQLSketch is designed with PostgreSQL as the primary target:

```julia
using SQLSketch.Drivers: PostgreSQLDriver
driver = PostgreSQLDriver("host=localhost dbname=mydb user=myuser password=mypass")
```

**Supported PostgreSQL features:**
- Native types: UUID, JSONB, ARRAY, BYTEA, TIMESTAMP WITH TIME ZONE
- Advanced SQL: CTEs, Window Functions, RETURNING, ON CONFLICT
- Full DDL support: CREATE/ALTER/DROP TABLE, CREATE/DROP INDEX
- Transaction features: Savepoints, advisory locks

### SQLite (Development/Testing)

SQLite is supported for fast local development and CI testing:

```julia
using SQLSketch.Drivers: SQLiteDriver
driver = SQLiteDriver(":memory:")  # In-memory
# or
driver = SQLiteDriver("dev.db")     # File-based
```

**Use SQLite for:**
- Fast local development
- Integration tests in CI
- Prototyping
- Development with eventual PostgreSQL deployment

## Getting Started

Start with the [Getting Started Guide](getting-started.md) for a step-by-step introduction.

Then explore:

- **[Tutorial](tutorial.md)** - Learn by building a complete application
- **[API Reference](api.md)** - Complete function and type documentation
- **[Performance Guide](performance.md)** - Optimize query performance with columnar API
- **[Design](design.md)** - Understand the architecture and design decisions

## Features

### Type-Safe Query Building

Output types are tracked through the pipeline:

```julia
q1 = from(:users)  # Query{NamedTuple}

q2 = q1 |> where(col(:users, :active) == literal(true))
# Still Query{NamedTuple} - shape-preserving

q3 = q2 |> select(User, col(:users, :id), col(:users, :email))
# Query{User} - shape-changing
```

### Parameterized Queries

Safe parameter binding with type checking:

```julia
user_id = p_(:user_id, Int64)
email = p_(:email, String)

q = from(:users) |>
    where((col(:users, :id) == user_id) & (col(:users, :email) == email)) |>
    select(User, col(:users, :id), col(:users, :email))

user = fetch_one(driver, q, user_id => 42, email => "user@example.com")
```

### DML with RETURNING

```julia
q = insert_into(:users, [:email, :active]) |>
    values([literal("new@example.com"), literal(true)]) |>
    returning(col(:users, :id), col(:users, :created_at))

result = fetch_one(driver, q)  # NamedTuple{(:id, :created_at)}
```

### Transactions and Savepoints

```julia
result = transaction(driver) do tx
    user_id = fetch_one(tx, insert_user_query)

    savepoint(tx, :create_profile) do sp
        execute(sp, create_profile_query)
    end

    user_id
end
```

### DDL Operations

```julia
q = create_table(:users) |>
    add_column(:id, :integer) |>
    add_column(:email, :text) |>
    add_column(:created_at, :timestamp) |>
    primary_key(:id) |>
    not_null(:email) |>
    unique_constraint(:email)

execute(driver, q)
```

### Window Functions

```julia
q = from(:sales) |>
    select(NamedTuple,
           col(:sales, :product),
           col(:sales, :amount),
           row_number() |> over(order_by(:amount; desc=true)))
```

### Set Operations

```julia
q1 = from(:users_2024) |> select(NamedTuple, col(:users_2024, :email))
q2 = from(:users_2025) |> select(NamedTuple, col(:users_2025, :email))

q = set_union(q1, q2, all=false)  # UNION (deduplicated)
```

### Migration System

```julia
using SQLSketch.Extras: apply_migrations, migration_status

# Apply all pending migrations
applied = apply_migrations(conn, dialect, "migrations/")

# Check status
status = migration_status(conn, dialect, "migrations/")
```

## Project Status

**⚠️ Note: This is a toy project for learning purposes.**

SQLSketch.jl is a personal learning project to explore:
- Type-safe query builder design in Julia
- PostgreSQL-first API design
- Fluent pipeline APIs with currying
- Julia's type system and multiple dispatch

**Current status:**
- Phase 11 (PostgreSQL Dialect) completed
- 1712 passing tests
- Current phase: **Phase 12 - Documentation**

**Not recommended for production use.** This project is intended as a learning exercise and exploration of Julia's capabilities.

## License

MIT License - see LICENSE file for details.
