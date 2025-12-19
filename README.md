**[日本語版 README はこちら / Japanese README](README.ja.md)**

---

⚠️ **Maintenance Notice**

**This is a toy project and is NOT actively maintained.**

This package was created as an educational/experimental exploration of typed SQL query builder design in Julia.
While the code is functional, it should not be used in production environments.
Issues and pull requests may not receive responses.

---

> ⚠️ **Status**
>
> SQLSketch.jl is currently a **sample / experimental package** developed by
> [@daikichiba9511](https://github.com/daikichiba9511).
>
> The primary goal of this repository is to explore and document a
> _Julia-native approach to SQL query building_, focusing on:
> - Type-safe query composition
> - Inspectable SQL generation
> - Clear abstraction boundaries
>
> APIs may change without notice until a stable release is announced.

# SQLSketch.jl

**An experimental typed SQL query builder for Julia.**

SQLSketch.jl provides a lightweight, composable way to build SQL queries with strong typing
and minimal hidden magic.

The core idea is simple:

> **SQL should always be visible and inspectable.
> Query APIs should follow SQL's logical evaluation order.
> Types should guide correctness without getting in the way.**

---

## Design Goals

- SQL is always visible and inspectable
- Query APIs follow SQL's logical evaluation order
- Output SQL follows SQL's syntactic order
- Strong typing at query boundaries
- Minimal hidden magic
- Clear separation between core primitives and convenience layers
- SQLite-first development with PostgreSQL / MySQL compatibility

---

## Architecture

SQLSketch is designed as a two-layer system:

```
┌─────────────────────────────────┐
│      Easy Layer (future)        │  ← Optional convenience
│  Repository, CRUD, Relations    │
└─────────────────────────────────┘
               ↓
┌─────────────────────────────────┐
│         Core Layer              │  ← Essential primitives
│  Query → Compile → Execute      │
│  Expr, Dialect, Driver, Codec   │
└─────────────────────────────────┘
```

### Core Layer
- `Expr` – Expression AST (column refs, literals, operators)
- `Query` – Query AST (FROM, WHERE, SELECT, JOIN, etc.)
- `Dialect` – SQL generation (SQLite, PostgreSQL, MySQL)
- `Driver` – Connection and execution
- `CodecRegistry` – Type conversion

### Easy Layer (Future)
- Repository pattern
- CRUD helpers
- Relation preloading
- Schema macros

---

## Current Implementation Status

**Completed Phases:** 3/10

- ✅ **Phase 1: Expression AST** (135 tests passing)
  - Column references, literals, parameters
  - Binary/unary operators with auto-wrapping
  - Function calls
  - Type-safe composition

- ✅ **Phase 2: Query AST** (482 tests passing)
  - FROM, WHERE, SELECT, JOIN, ORDER BY
  - LIMIT, OFFSET, DISTINCT, GROUP BY, HAVING
  - Pipeline composition with `|>`
  - Shape-preserving and shape-changing semantics
  - Type-safe query transformations

- ✅ **Phase 3: Dialect Abstraction** (102 tests passing)
  - Dialect interface (compile, quote_identifier, placeholder, supports)
  - Capability system for feature detection
  - SQLite dialect implementation
  - Full SQL generation from query ASTs
  - Expression and query compilation

- ⏳ **Phase 4-10:** See [`docs/roadmap.md`](docs/roadmap.md) and [`docs/TODO.md`](docs/TODO.md)

---

## Example

```julia
using SQLSketch

# Build query with type-safe composition
q = from(:users) |>
    where(col(:users, :active) == true) |>
    select(NamedTuple, col(:users, :id), col(:users, :email)) |>
    order_by(col(:users, :created_at), desc=true) |>
    limit(10)

# Compile to SQL
dialect = SQLiteDialect()
sql, params = compile(dialect, q)

println(sql)
# => "SELECT `users`.`id`, `users`.`email` FROM `users`
#     WHERE (`users`.`active` = 1) ORDER BY `users`.`created_at` DESC LIMIT 10"

# Execute and get typed results (Phase 4+)
# db = connect(SQLiteDriver(), ":memory:")
# users = all(db, q)  # Returns Vector{NamedTuple}
```

---

## Project Structure

```
src/
  Core/              # Core layer implementation
    expr.jl          # Expression AST ✅
    query.jl         # Query AST ✅
    dialect.jl       # Dialect abstraction ✅
    driver.jl        # Driver abstraction ⏳
    codec.jl         # Type conversion ⏳
    execute.jl       # Query execution ⏳
    transaction.jl   # Transaction management ⏳
    migrations.jl    # Migration runner ⏳
  Dialects/          # Dialect implementations
    sqlite.jl        # SQLite SQL generation ✅
  Drivers/           # Driver implementations
    sqlite.jl        # SQLite execution ⏳

test/                # Test suite
  core/
    expr_test.jl     # Expression tests ✅
    query_test.jl    # Query tests ✅
  dialects/
    sqlite_test.jl   # SQLite dialect tests ✅
  drivers/
  integration/

docs/                # Documentation
  design.md          # Design document
  roadmap.md         # Implementation roadmap
  TODO.md            # Task breakdown
```

---

## Development

### Running Tests

```bash
# Run all tests
julia --project -e 'using Pkg; Pkg.test()'

# Run specific test file
julia --project test/core/expr_test.jl
```

### Starting REPL

```bash
julia --project
```

### Current Test Status

```
Test Summary:         | Pass  Total
Expression AST        |  135    135
Query AST             |  482    482
SQLite Dialect        |  102    102
──────────────────────────────────
Total                 |  719    719
```

---

## Documentation

- [`docs/design.md`](docs/design.md) – Design philosophy and architecture
- [`docs/roadmap.md`](docs/roadmap.md) – Phased implementation plan (10 phases)
- [`docs/TODO.md`](docs/TODO.md) – Detailed task breakdown (400+ tasks)

---

## Design Principles

### 1. SQL is Always Visible

```julia
# Bad: Hidden SQL
users = User.where(active: true).limit(10)

# Good: Inspectable SQL
q = from(:users) |> where(col(:users, :active) == true) |> limit(10)
sql(q)  # Show me the SQL
```

### 2. Logical Evaluation Order

Query construction follows SQL's logical order:
```
FROM → WHERE → SELECT → ORDER BY → LIMIT
```

Not SQL's syntactic order:
```
SELECT → FROM → WHERE → ORDER BY → LIMIT
```

### 3. Type Safety at Boundaries

```julia
# Query knows its output type
q::Query{User} = from(:users) |> select(User, ...)

# Execution is type-safe
users::Vector{User} = all(db, q)
```

### 4. Minimal Hidden Magic

- No implicit schema reading
- No automatic relation loading
- No global state
- Explicit is better than implicit

---

## What SQLSketch.jl Is _Not_

- ❌ A full-featured ORM
- ❌ A replacement for raw SQL
- ❌ A schema migration tool (migrations are minimal)
- ❌ An ActiveRecord clone
- ❌ Production-ready (it's a toy project!)

It is a **typed SQL query builder**, by design.

---

## Requirements

- Julia **1.9+** (as specified in Project.toml)

Future dependencies (will be added as implementation progresses):
- SQLite.jl (Phase 4)
- DBInterface.jl (Phase 4)
- Dates (Phase 5)
- UUIDs (Phase 5)

---

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md) for the complete implementation plan.

**Estimated Timeline:**
- Phase 1-3 (Expressions, Queries, Dialect): 6 weeks ✅ **COMPLETED**
- Phase 4-6 (Driver, Codec, Integration): 6 weeks
- Phase 7-8 (Transactions, Migrations): 2 weeks
- Phase 9 (PostgreSQL): 2 weeks
- Phase 10 (Documentation): 2+ weeks

**Total:** ~16 weeks for Core layer

---

## License

MIT License
