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

**Completed Phases:** 6/10 | **Total Tests:** 662+ passing ✅

- ✅ **Phase 1: Expression AST** (268 tests)
  - Column references, literals, parameters
  - Binary/unary operators with auto-wrapping
  - Function calls
  - Type-safe composition
  - **Placeholder syntax (`p_`)** - syntactic sugar for column references
  - **LIKE/ILIKE operators** - pattern matching
  - **BETWEEN operator** - range queries
  - **IN operator** - membership tests
  - **CAST expressions** - type conversion
  - **Subquery expressions** - nested queries (EXISTS, IN subquery)
  - **CASE expressions** - conditional logic

- ✅ **Phase 2: Query AST** (85 tests)
  - FROM, WHERE, SELECT, JOIN, ORDER BY
  - LIMIT, OFFSET, DISTINCT, GROUP BY, HAVING
  - **INSERT, UPDATE, DELETE** (DML operations)
  - Pipeline composition with `|>`
  - Shape-preserving and shape-changing semantics
  - Type-safe query transformations
  - **Curried API** for natural pipeline composition

- ✅ **Phase 3: Dialect Abstraction** (102 tests)
  - Dialect interface (compile, quote_identifier, placeholder, supports)
  - Capability system for feature detection
  - SQLite dialect implementation
  - Full SQL generation from query ASTs
  - **All expression types** (CAST, Subquery, CASE, BETWEEN, IN, LIKE)
  - Expression and query compilation
  - **DML compilation (INSERT, UPDATE, DELETE)**
  - **Placeholder resolution** (`p_` → `col(table, column)`)

- ✅ **Phase 4: Driver Abstraction** (41 tests)
  - Driver interface (connect, execute, close)
  - SQLiteDriver implementation
  - Connection management (in-memory and file-based)
  - Parameter binding with `?` placeholders
  - Query execution returning raw SQLite results

- ✅ **Phase 5: CodecRegistry** (112 tests)
  - Type-safe encoding/decoding between Julia and SQL
  - Built-in codecs (Int, Float64, String, Bool, Date, DateTime, UUID)
  - NULL/Missing handling
  - Row mapping to NamedTuples and structs

- ✅ **Phase 6: End-to-End Integration** (54 tests)
  - Query execution API (`fetch_all`, `fetch_one`, `fetch_maybe`)
  - **DML execution API (`execute_dml`)**
  - Type-safe parameter binding
  - Full pipeline: Query AST → Dialect → Driver → CodecRegistry
  - Observability API (`sql`, `explain`)
  - Comprehensive integration tests
  - **Full CRUD operations** (SELECT, INSERT, UPDATE, DELETE)

- ⏳ **Phase 7-10:** See [`docs/roadmap.md`](docs/roadmap.md) and [`docs/TODO.md`](docs/TODO.md)

---

## Example

```julia
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers

# Import execution functions
import SQLSketch.Core: fetch_all, fetch_one, fetch_maybe, execute_dml, sql

# Connect to database
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# Create tables
execute(db, """
    CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        email TEXT NOT NULL,
        age INTEGER,
        status TEXT DEFAULT 'active',
        created_at TEXT
    )
""", [])

execute(db, """
    CREATE TABLE orders (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        total REAL,
        FOREIGN KEY (user_id) REFERENCES users(id)
    )
""", [])

# ========================================
# Basic Query - Explicit column references with col()
# ========================================

# col() makes table and column references explicit and clear
q1 = from(:users) |>
    where(col(:users, :status) == literal("active")) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

# Generated SQL:
# SELECT `users`.`id`, `users`.`email`
# FROM `users`
# WHERE (`users`.`status` = 'active')

# ========================================
# Placeholder Syntax - Convenient sugar for single-table queries
# ========================================

# p_ is syntactic sugar: p_.column expands to col(inferred_table, :column)
# More concise for simple queries, but table name is implicit
q2 = from(:users) |>
    where(p_.status == "active") |>
    select(NamedTuple, p_.id, p_.email)

# Generated SQL (same as q1):
# SELECT `users`.`id`, `users`.`email`
# FROM `users`
# WHERE (`users`.`status` = 'active')

# ========================================
# Advanced Features - CASE, BETWEEN, LIKE
# ========================================

q3 = from(:users) |>
    where(p_.age |> between(18, 65)) |>
    where(p_.email |> like("%@gmail.com")) |>
    select(NamedTuple,
           p_.id,
           p_.email,
           # CASE expression for age categories
           case_expr([
               (p_.age < 18, "minor"),
               (p_.age < 65, "adult")
           ], "senior")) |>
    order_by(p_.created_at; desc=true) |>
    limit(10)

# Generated SQL:
# SELECT `users`.`id`, `users`.`email`,
#   CASE WHEN (`users`.`age` < 18) THEN 'minor'
#        WHEN (`users`.`age` < 65) THEN 'adult'
#        ELSE 'senior' END
# FROM `users`
# WHERE ((`users`.`age` BETWEEN 18 AND 65) AND (`users`.`email` LIKE '%@gmail.com'))
# ORDER BY `users`.`created_at` DESC
# LIMIT 10

# ========================================
# JOIN Query - Explicit col() is important for clarity
# ========================================

# When joining tables, explicit col() makes it clear which table each column belongs to
q4 = from(:users) |>
    join(:orders, col(:orders, :user_id) == col(:users, :id)) |>
    where(col(:users, :status) == literal("active")) |>
    select(NamedTuple,
           col(:users, :id),
           col(:users, :email),
           col(:orders, :total))

# Generated SQL:
# SELECT `users`.`id`, `users`.`email`, `orders`.`total`
# FROM `users`
# INNER JOIN `orders` ON (`orders`.`user_id` = `users`.`id`)
# WHERE (`users`.`status` = 'active')

# ========================================
# Subquery Example
# ========================================

active_users = subquery(
    from(:users) |>
    where(p_.status == "active") |>
    select(NamedTuple, p_.id)
)

q5 = from(:orders) |>
    where(in_subquery(p_.user_id, active_users)) |>
    select(NamedTuple, p_.id, p_.user_id, p_.total)

# Generated SQL:
# SELECT `orders`.`id`, `orders`.`user_id`, `orders`.`total`
# FROM `orders`
# WHERE (`orders`.`user_id` IN (SELECT `users`.`id` FROM `users` WHERE (`users`.`status` = 'active')))

# ========================================
# Inspect SQL before execution
# ========================================

sql_str = sql(dialect, q4)
println(sql_str)  # View the generated SQL

# ========================================
# Execute queries and get typed results
# ========================================

users = fetch_all(db, dialect, registry, q2)  # Returns Vector{NamedTuple}
user = fetch_one(db, dialect, registry, q2)   # Returns NamedTuple (errors if not exactly 1 row)
maybe_user = fetch_maybe(db, dialect, registry, q2)  # Returns Union{NamedTuple, Nothing}

# ========================================
# DML Operations (INSERT, UPDATE, DELETE)
# ========================================

# INSERT with literals
insert_q = insert_into(:users, [:email, :age, :status]) |>
    values([[literal("alice@example.com"), literal(25), literal("active")]])
execute_dml(db, dialect, insert_q)
# Generated SQL:
# INSERT INTO `users` (`email`, `age`, `status`) VALUES ('alice@example.com', 25, 'active')

# INSERT with parameters (type-safe binding)
insert_q2 = insert_into(:users, [:email, :age, :status]) |>
    values([[param(String, :email), param(Int, :age), param(String, :status)]])
execute_dml(db, dialect, insert_q2, (email="bob@example.com", age=30, status="active"))
# Generated SQL:
# INSERT INTO `users` (`email`, `age`, `status`) VALUES (?, ?, ?)
# Params: ["bob@example.com", 30, "active"]

# UPDATE with WHERE
update_q = update(:users) |>
    set(:status => param(String, :status)) |>
    where(col(:users, :email) == param(String, :email))
execute_dml(db, dialect, update_q, (status="inactive", email="alice@example.com"))
# Generated SQL:
# UPDATE `users` SET `status` = ? WHERE (`users`.`email` = ?)
# Params: ["inactive", "alice@example.com"]

# DELETE with WHERE
delete_q = delete_from(:users) |>
    where(col(:users, :status) == literal("inactive"))
execute_dml(db, dialect, delete_q)
# Generated SQL:
# DELETE FROM `users` WHERE (`users`.`status` = 'inactive')

close(db)
```

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
    transaction.jl   # Transaction management ⏳
    migrations.jl    # Migration runner ⏳
  Dialects/          # Dialect implementations
    sqlite.jl        # SQLite SQL generation ✅
  Drivers/           # Driver implementations
    sqlite.jl        # SQLite execution ✅

test/                # Test suite (662+ tests)
  core/
    expr_test.jl     # Expression tests ✅ (268)
    query_test.jl    # Query tests ✅ (85)
    codec_test.jl    # Codec tests ✅ (112)
  dialects/
    sqlite_test.jl   # SQLite dialect tests ✅ (102)
  drivers/
    sqlite_test.jl   # SQLite driver tests ✅ (41)
  integration/
    end_to_end_test.jl  # Integration tests ✅ (54)

docs/                # Documentation
  design.md          # Design document
  roadmap.md         # Implementation roadmap
  TODO.md            # Task breakdown
  CLAUDE.md          # Implementation guidelines
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
Total: 662+ tests passing ✅

Phase 1 (Expression AST):        268 tests (CAST, Subquery, CASE, BETWEEN, IN, LIKE)
Phase 2 (Query AST):              85 tests (includes DML: INSERT/UPDATE/DELETE)
Phase 3 (Dialect Abstraction):   102 tests (includes DML compilation + all expressions)
Phase 4 (Driver Abstraction):     41 tests
Phase 5 (CodecRegistry):         112 tests
Phase 6 (End-to-End Integration): 54 tests (includes DML execution)
Phase 7 (Transactions):           ⏳ Not yet implemented
Phase 8 (Migrations):             ⏳ Not yet implemented
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

### Current Dependencies

- **SQLite.jl** - SQLite database driver ✅
- **DBInterface.jl** - Database interface abstraction ✅
- **Dates** (stdlib) - Date/DateTime type support ✅
- **UUIDs** (stdlib) - UUID type support ✅

### Future Dependencies

- LibPQ.jl (Phase 9 - PostgreSQL support)
- MySQL.jl (Future - MySQL support)

---

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md) for the complete implementation plan.

**Progress:**
- ✅ Phase 1-3 (Expressions, Queries, Dialect): 6 weeks - **COMPLETED**
- ✅ Phase 4-6 (Driver, Codec, Integration): 6 weeks - **COMPLETED**
- ⏳ Phase 7-8 (Transactions, Migrations): 2 weeks - **NEXT**
- ⏳ Phase 9 (PostgreSQL): 2 weeks
- ⏳ Phase 10 (Documentation): 2+ weeks

**Estimated Total:** ~18 weeks for Core layer (60% complete)

---

## License

MIT License
