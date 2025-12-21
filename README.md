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
>
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
- **PostgreSQL-first development** with SQLite / MySQL compatibility

---

## Architecture

SQLSketch is designed as a two-layer system:

```
┌─────────────────────────────────┐
│      Extras Layer (future)      │  ← Optional convenience
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

### Extras Layer (Future)

- Repository pattern
- CRUD helpers
- Relation preloading
- Schema macros

---

## Status

**Completed:** 12/12 phases | **Tests:** 1712 passing ✅

Core features implemented:

- ✅ Expression & Query AST (500 tests)
- ✅ SQLite & PostgreSQL dialects (433 tests)
- ✅ Type-safe execution & codecs (251 tests)
- ✅ Transactions & migrations (105 tests)
- ✅ Window functions, set operations, UPSERT (267 tests)
- ✅ DDL support (227 tests)

See [**Implementation Status**](docs/implementation-status.md) for detailed breakdown.

---

## Example

### Quick Start

```julia
using SQLSketch          # Core query building functions
using SQLSketch.Drivers  # Database drivers

# Connect to database
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# Build and execute query
q = from(:users) |>
    where(col(:users, :status) == literal("active")) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

users = fetch_all(db, dialect, registry, q)
# => Vector{NamedTuple{(:id, :email), ...}}

close(db)
```

### Common Use Cases

**1. Basic Query with WHERE and ORDER BY**

```julia
using SQLSketch

q = from(:users) |>
    where(col(:users, :age) > literal(18)) |>
    select(NamedTuple, col(:users, :id), col(:users, :name)) |>
    order_by(col(:users, :name))
```

**2. JOIN Query**

```julia
using SQLSketch

q = from(:users) |>
    innerjoin(:orders, col(:orders, :user_id) == col(:users, :id)) |>
    where(col(:users, :status) == literal("active")) |>
    select(NamedTuple, col(:users, :name), col(:orders, :total))
```

**3. INSERT with Parameters**

```julia
using SQLSketch

insert_q = insert_into(:users, [:email, :age]) |>
    insert_values([[param(String, :email), param(Int, :age)]])

execute(db, dialect, insert_q, (email="alice@example.com", age=25))
```

**4. Transaction with Multiple Operations**

```julia
using SQLSketch

transaction(db) do tx
    execute(tx, dialect,
        insert_into(:users, [:email]) |>
        insert_values([[literal("user@example.com")]]))

    execute(tx, dialect,
        insert_into(:orders, [:user_id, :total]) |>
        insert_values([[literal(1), literal(99.99)]]))
end
```

**5. Database Migrations**

```julia
using SQLSketch

# Apply pending migrations
applied = apply_migrations(db, "db/migrations")

# Check status
status = migration_status(db, "db/migrations")
```

**6. DDL - Create Table**

```julia
using SQLSketch

table = create_table(:users) |>
    add_column(:id, :integer; primary_key=true) |>
    add_column(:email, :text; nullable=false) |>
    add_column(:status, :text; default=literal("active"))

execute(db, dialect, table)
```

See [`examples/`](examples/) for more complete examples.

---

## Project Structure

```
src/
  Core/              # Core layer implementation
    expr.jl          # Expression AST ✅
    query.jl         # Query AST ✅
    dialect.jl       # Dialect abstraction ✅
    driver.jl        # Driver abstraction ✅
    codec.jl         # Type conversion ✅
    execute.jl       # Query execution ✅
    transaction.jl   # Transaction management ✅
    migrations.jl    # Migration runner ✅
    ddl.jl           # DDL support ✅
  Dialects/          # Dialect implementations
    sqlite.jl        # SQLite SQL generation ✅
    postgresql.jl    # PostgreSQL SQL generation ✅
    shared_helpers.jl # Shared helper functions ✅
  Drivers/           # Driver implementations
    sqlite.jl        # SQLite execution ✅
    postgresql.jl    # PostgreSQL execution ✅
  Codecs/            # Database-specific codecs
    postgresql.jl    # PostgreSQL-specific codecs (UUID, JSONB, Array) ✅

test/                # Test suite (1712 tests)
  core/
    expr_test.jl     # Expression tests ✅ (268)
    query_test.jl    # Query tests ✅ (232)
    window_test.jl   # Window function tests ✅ (79)
    set_operations_test.jl  # Set operations tests ✅ (102)
    upsert_test.jl   # UPSERT tests ✅ (86)
    codec_test.jl    # Codec tests ✅ (115)
    transaction_test.jl  # Transaction tests ✅ (26)
    migrations_test.jl   # Migration tests ✅ (79)
    ddl_test.jl      # DDL tests ✅ (156)
  dialects/
    sqlite_test.jl   # SQLite dialect tests ✅ (331)
    postgresql_test.jl  # PostgreSQL dialect tests ✅ (102)
  drivers/
    sqlite_test.jl   # SQLite driver tests ✅ (41)
  integration/
    end_to_end_test.jl  # Integration tests ✅ (95)
    postgresql_integration_test.jl  # PostgreSQL integration tests ✅

docs/                # Documentation
  design.md          # Design document
  roadmap.md         # Implementation roadmap
  TODO.md            # Task breakdown
  CLAUDE.md          # Implementation guidelines for Claude
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

See [`docs/implementation-status.md`](docs/implementation-status.md) for complete test breakdown.

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

Query construction follows SQL's **logical evaluation order**, not its syntactic order.

#### SQL Logical Evaluation Order (what SQL actually does)

```
1. WITH (CTE)              — Define common table expressions
2. FROM                    — Identify source tables
3. JOIN                    — Combine tables (INNER, LEFT, RIGHT, FULL)
4. WHERE                   — Filter rows before grouping
5. GROUP BY                — Group rows for aggregation
6. HAVING                  — Filter groups after aggregation
7. Window Functions        — Compute over partitions (OVER clause)
8. SELECT                  — Project columns (shape-changing)
9. DISTINCT                — Remove duplicate rows
10. Set Operations         — Combine queries (UNION, INTERSECT, EXCEPT)
11. ORDER BY               — Sort result rows
12. LIMIT / OFFSET         — Restrict result set size
```

SQLSketch.jl pipeline API follows this logical order:

```julia
# Example query using logical evaluation order
q = with(:recent_orders,
         from(:orders) |>
         where(col(:orders, :created_at) > literal("2024-01-01"))) |>
    from(:recent_orders) |>
    innerjoin(:users, col(:recent_orders, :user_id) == col(:users, :id)) |>
    where(col(:users, :active) == literal(true)) |>
    group_by(col(:users, :id), col(:users, :email)) |>
    having(func(:COUNT, col(:recent_orders, :id)) > literal(5)) |>
    select(NamedTuple,
           col(:users, :id),
           col(:users, :email),
           func(:COUNT, col(:recent_orders, :id))) |>
    order_by(func(:COUNT, col(:recent_orders, :id)); desc=true) |>
    limit(10)
```

This contrasts with SQL's **syntactic order** (how SQL is written):

```sql
WITH recent_orders AS (...)
SELECT ...
FROM recent_orders
JOIN users ON ...
WHERE ...
GROUP BY ...
HAVING ...
ORDER BY ...
LIMIT ...
```

By following logical order, SQLSketch.jl makes query transformations predictable and type-safe.

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

- Julia **1.12+** (as specified in Project.toml)

### Current Dependencies

**Database Drivers:**

- **SQLite.jl** - SQLite database driver ✅
- **LibPQ.jl** - PostgreSQL database driver ✅
- **DBInterface.jl** - Database interface abstraction ✅

**Type Support:**

- **Dates** (stdlib) - Date/DateTime type support ✅
- **UUIDs** (stdlib) - UUID type support ✅
- **JSON3** - JSON/JSONB serialization (PostgreSQL) ✅
- **SHA** (stdlib) - Migration checksum validation ✅

**Development Tools:**

- **JET** - Static analysis and type checking ✅
- **JuliaFormatter** - Code formatting ✅

### Future Dependencies

- MySQL.jl (MySQL support)
- MariaDB.jl (MariaDB support)

---

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md) for the complete implementation plan and [`docs/implementation-status.md`](docs/implementation-status.md) for detailed status.

---

## License

MIT License
