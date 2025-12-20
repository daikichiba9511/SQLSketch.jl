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
│      Extras Layer (future)        │  ← Optional convenience
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

## Current Implementation Status

**Completed Phases:** 11/12 | **Total Tests:** 1712 passing ✅

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

- ✅ **Phase 2: Query AST** (232 tests)

  - FROM, WHERE, SELECT, JOIN, ORDER BY
  - LIMIT, OFFSET, DISTINCT, GROUP BY, HAVING
  - **INSERT, UPDATE, DELETE** (DML operations)
  - Pipeline composition with `|>`
  - Shape-preserving and shape-changing semantics
  - Type-safe query transformations
  - **Curried API** for natural pipeline composition

- ✅ **Phase 3: Dialect Abstraction** (331 tests)

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

- ✅ **Phase 5: CodecRegistry** (115 tests)

  - Type-safe encoding/decoding between Julia and SQL
  - Built-in codecs (Int, Float64, String, Bool, Date, DateTime, UUID)
  - NULL/Missing handling
  - Row mapping to NamedTuples and structs

- ✅ **Phase 6: End-to-End Integration** (95 tests)

  - Query execution API (`fetch_all`, `fetch_one`, `fetch_maybe`)
  - **DML execution API (`execute`)**
  - Type-safe parameter binding
  - Full pipeline: Query AST → Dialect → Driver → CodecRegistry
  - Observability API (`sql`, `explain`)
  - Comprehensive integration tests
  - **Full CRUD operations** (SELECT, INSERT, UPDATE, DELETE)

- ✅ **Phase 7: Transaction Management** (26 tests)

  - **Transaction API (`transaction`)** - automatic commit/rollback
  - **Savepoint API (`savepoint`)** - nested transactions
  - Transaction-compatible query execution
  - SQLite implementation (BEGIN/COMMIT/ROLLBACK)
  - Comprehensive error handling and isolation tests

- ✅ **Phase 8: Migration Runner** (79 tests)

  - **Migration discovery and application** (`discover_migrations`, `apply_migrations`)
  - **Timestamp-based versioning** (YYYYMMDDHHMMSS format)
  - **SHA256 checksum validation** - detect modified migrations
  - **Automatic schema tracking** (`schema_migrations` table)
  - **Transaction-wrapped execution** - automatic rollback on failure
  - **Migration status and validation** (`migration_status`, `validate_migration_checksums`)
  - **Migration generation** (`generate_migration`) - create timestamped migration files
  - UP/DOWN migration section support

- ✅ **Phase 8.5: Window Functions** (79 tests)

  - **Window function AST** (`WindowFrame`, `Over`, `WindowFunc`)
  - **Ranking functions** (`row_number`, `rank`, `dense_rank`, `ntile`)
  - **Value functions** (`lag`, `lead`, `first_value`, `last_value`, `nth_value`)
  - **Aggregate window functions** (`win_sum`, `win_avg`, `win_min`, `win_max`, `win_count`)
  - **Frame specification** (ROWS/RANGE/GROUPS BETWEEN)
  - **OVER clause builder** (PARTITION BY, ORDER BY, frame)
  - **Full SQLite dialect support** - complete SQL generation

- ✅ **Phase 8.6: Set Operations** (102 tests)

  - **Set operation AST** (`SetUnion`, `SetIntersect`, `SetExcept`)
  - **UNION / UNION ALL** - combine query results
  - **INTERSECT** - find common rows
  - **EXCEPT** - find differences
  - **Pipeline API with currying** - natural composition
  - **Full SQLite dialect support** - complete SQL generation

- ✅ **Phase 8.7: UPSERT (ON CONFLICT)** (86 tests)

  - **OnConflict AST type** - UPSERT support
  - **ON CONFLICT DO NOTHING** - ignore conflicts
  - **ON CONFLICT DO UPDATE** - update on conflict
  - **Conflict target specification** - column-based targets
  - **Conditional updates with WHERE** - fine-grained control
  - **Pipeline API with currying** - natural composition
  - **Full SQLite dialect support** - complete SQL generation

- ✅ **Phase 10: DDL Support** (227 tests)

  - **DDL AST** (`CreateTable`, `AlterTable`, `DropTable`, `CreateIndex`, `DropIndex`)
  - **Column constraints** (PRIMARY KEY, NOT NULL, UNIQUE, DEFAULT, CHECK, FOREIGN KEY)
  - **Table constraints** (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK)
  - **Portable column types** (`:integer`, `:text`, `:boolean`, `:timestamp`, etc.)
  - **Pipeline API with currying** - natural schema composition
  - **Full SQLite DDL compilation** - complete DDL SQL generation
  - **156 DDL AST unit tests** + **71 SQLite DDL compilation tests**

- ✅ **Phase 11: PostgreSQL Dialect** (102 tests)

  - **PostgreSQLDialect implementation** - full SQL generation
  - **PostgreSQL-specific features**
    - Identifier quoting with `"` (double quotes)
    - Placeholder syntax `$1`, `$2`, ... (numbered positional)
    - Native `BOOLEAN` type (TRUE/FALSE)
    - Native `ILIKE` operator
    - Native `UUID` type
    - `JSONB` support
    - `ARRAY` types
    - `BYTEA` (binary data)
  - **PostgreSQLDriver implementation** (LibPQ.jl)
    - Connection management (libpq connection strings)
    - Transaction support (BEGIN/COMMIT/ROLLBACK)
    - Savepoint support (nested transactions)
    - Query execution with positional parameters
  - **PostgreSQL-specific Codecs**
    - Native UUID codec
    - JSONB codec (Dict/Vector serialization)
    - Array codecs (Integer[], Text[], generic arrays)
    - Native Boolean/Date/DateTime codecs
  - **Full DDL support** - CREATE TABLE, ALTER TABLE, DROP TABLE, CREATE INDEX, DROP INDEX
  - **Capability support** - CTE, RETURNING, UPSERT, WINDOW, LATERAL, BULK_COPY, SAVEPOINT, ADVISORY_LOCK
  - **Integration tests** - comprehensive PostgreSQL compatibility tests

- ⏳ **Phase 12: Documentation** - See [`docs/roadmap.md`](docs/roadmap.md) and [`docs/TODO.md`](docs/TODO.md)

---

## Example

```julia
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers

# Import core query building functions
import SQLSketch.Core: from, where, select, order_by, limit, offset, distinct, group_by, having
import SQLSketch.Core: innerjoin, leftjoin, rightjoin, fulljoin  # Aliases to avoid Base.join conflict
import SQLSketch.Core: col, literal, param, func, p_
import SQLSketch.Core: between, like, case_expr
import SQLSketch.Core: subquery, in_subquery

# Import DML functions
import SQLSketch.Core: insert_into, insert_values  # insert_values is alias for values (Base.values conflict)
import SQLSketch.Core: update, set, delete_from

# Import DDL functions
import SQLSketch.Core: create_table, add_column, add_foreign_key

# Import execution functions
import SQLSketch.Core: fetch_all, fetch_one, fetch_maybe, execute, sql

# Import transaction functions
import SQLSketch.Core: transaction, savepoint

# Connect to database
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# Create tables using DDL API
users_table = create_table(:users) |>
    add_column(:id, :integer; primary_key=true) |>
    add_column(:email, :text; nullable=false) |>
    add_column(:age, :integer) |>
    add_column(:status, :text; default=literal("active")) |>
    add_column(:created_at, :timestamp)

execute(db, dialect, users_table)

orders_table = create_table(:orders) |>
    add_column(:id, :integer; primary_key=true) |>
    add_column(:user_id, :integer) |>
    add_column(:total, :real) |>
    add_foreign_key([:user_id], :users, [:id])

execute(db, dialect, orders_table)

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
    innerjoin(:orders, col(:orders, :user_id) == col(:users, :id)) |>
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
    insert_values([[literal("alice@example.com"), literal(25), literal("active")]])
execute(db, dialect, insert_q)
# Generated SQL:
# INSERT INTO `users` (`email`, `age`, `status`) VALUES ('alice@example.com', 25, 'active')

# INSERT with parameters (type-safe binding)
insert_q2 = insert_into(:users, [:email, :age, :status]) |>
    insert_values([[param(String, :email), param(Int, :age), param(String, :status)]])
execute(db, dialect, insert_q2, (email="bob@example.com", age=30, status="active"))
# Generated SQL:
# INSERT INTO `users` (`email`, `age`, `status`) VALUES (?, ?, ?)
# Params: ["bob@example.com", 30, "active"]

# UPDATE with WHERE
update_q = update(:users) |>
    set(:status => param(String, :status)) |>
    where(col(:users, :email) == param(String, :email))
execute(db, dialect, update_q, (status="inactive", email="alice@example.com"))
# Generated SQL:
# UPDATE `users` SET `status` = ? WHERE (`users`.`email` = ?)
# Params: ["inactive", "alice@example.com"]

# DELETE with WHERE
delete_q = delete_from(:users) |>
    where(col(:users, :status) == literal("inactive"))
execute(db, dialect, delete_q)
# Generated SQL:
# DELETE FROM `users` WHERE (`users`.`status` = 'inactive')

# ========================================
# Transactions - Atomic Operations
# ========================================

# Basic transaction - automatic commit/rollback
transaction(db) do tx
    # Insert user
    execute(tx, dialect,
                insert_into(:users, [:email, :age, :status]) |>
                insert_values([[literal("charlie@example.com"), literal(35), literal("active")]]))

    # Insert order for the user
    execute(tx, dialect,
                insert_into(:orders, [:user_id, :total]) |>
                insert_values([[literal(3), literal(150.0)]]))

    # Both inserts commit together, or both rollback on error
end

# Transaction with query execution
users = transaction(db) do tx
    # Queries work inside transactions too!
    q = from(:users) |>
        where(col(:users, :status) == literal("active")) |>
        select(NamedTuple, col(:users, :id), col(:users, :email))

    fetch_all(tx, dialect, registry, q)
end

# Nested transactions using savepoints
transaction(db) do tx
    execute(tx, dialect,
                insert_into(:users, [:email, :age, :status]) |>
                insert_values([[literal("david@example.com"), literal(40), literal("active")]]))

    # Savepoint for risky operation
    try
        savepoint(tx, :risky_update) do sp
            execute(sp, dialect,
                        update(:users) |>
                        set(:status => literal("suspended")) |>
                        where(col(:users, :age) > literal(30)))

            # If something fails here, only the UPDATE rolls back
            # The INSERT above will still commit
        end
    catch e
        # Savepoint rolled back, but outer transaction continues
    end
end

# ========================================
# Database Migrations
# ========================================

# Import migration functions
import SQLSketch.Core: apply_migrations, migration_status, generate_migration

# Generate a new migration file
migration_path = generate_migration("db/migrations", "add_user_roles")
# Creates: db/migrations/20250120150000_add_user_roles.sql

# Migration file format (db/migrations/20250120150000_add_user_roles.sql):
# -- UP
# ALTER TABLE users ADD COLUMN role TEXT DEFAULT 'user';
#
# -- DOWN
# ALTER TABLE users DROP COLUMN role;

# Apply all pending migrations
applied = apply_migrations(db, dialect, "db/migrations")
println("Applied $(length(applied)) migrations")

# Check migration status
status = migration_status(db, dialect, "db/migrations")
for s in status
    status_icon = s.applied ? "✓" : "✗"
    println("$status_icon $(s.migration.version) $(s.migration.name)")
end

# Migration features:
# - Timestamp-based versioning (YYYYMMDDHHMMSS)
# - SHA256 checksum validation (detects modified migrations)
# - Transaction-wrapped (automatic rollback on failure)
# - Idempotent (safe to run multiple times)

# ========================================
# Window Functions - Ranking, Running Totals, Moving Averages
# ========================================

# Import window function constructors
import SQLSketch.Core: row_number, rank, dense_rank, ntile, lag, lead
import SQLSketch.Core: win_sum, win_avg, win_min, win_max, win_count
import SQLSketch.Core: over, window_frame, first_value, last_value, nth_value

# Employee ranking within each department
ranking_q = from(:employees) |>
    select(NamedTuple,
           col(:employees, :name),
           col(:employees, :department),
           col(:employees, :salary),
           row_number(over(partition_by = [col(:employees, :department)],
                          order_by = [(col(:employees, :salary), true)])))
# Generated SQL:
# SELECT `employees`.`name`, `employees`.`department`, `employees`.`salary`,
#   ROW_NUMBER() OVER (PARTITION BY `employees`.`department` ORDER BY `employees`.`salary` DESC)
# FROM `employees`

# Running total with frame specification
running_total_q = from(:sales) |>
    select(NamedTuple,
           col(:sales, :date),
           col(:sales, :amount),
           win_sum(col(:sales, :amount),
                  over(order_by = [(col(:sales, :date), false)],
                       frame = window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW))))
# Generated SQL:
# SELECT `sales`.`date`, `sales`.`amount`,
#   SUM(`sales`.`amount`) OVER (ORDER BY `sales`.`date` ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
# FROM `sales`

# 7-day moving average
moving_avg_q = from(:sales) |>
    select(NamedTuple,
           col(:sales, :date),
           col(:sales, :amount),
           win_avg(col(:sales, :amount),
                  over(order_by = [(col(:sales, :date), false)],
                       frame = window_frame(:ROWS, -6, :CURRENT_ROW))))
# Generated SQL:
# SELECT `sales`.`date`, `sales`.`amount`,
#   AVG(`sales`.`amount`) OVER (ORDER BY `sales`.`date` ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
# FROM `sales`

# Compare to previous row (LAG function)
lag_q = from(:sales) |>
    select(NamedTuple,
           col(:sales, :date),
           col(:sales, :amount),
           lag(col(:sales, :amount), over(order_by = [(col(:sales, :date), false)])))
# Generated SQL:
# SELECT `sales`.`date`, `sales`.`amount`,
#   LAG(`sales`.`amount`, 1) OVER (ORDER BY `sales`.`date`)
# FROM `sales`

# See examples/window_functions.jl for more examples

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

### Current Test Status

```
Total: 1712 tests passing ✅

Phase 1 (Expression AST):         268 tests (CAST, Subquery, CASE, BETWEEN, IN, LIKE)
Phase 2 (Query AST):              232 tests (DML, CTE, RETURNING)
Phase 3 (SQLite Dialect):         331 tests (DML + CTE + DDL compilation, all expressions)
Phase 4 (Driver Abstraction):      41 tests (SQLite driver)
Phase 5 (CodecRegistry):          115 tests (type conversion, NULL handling)
Phase 6 (End-to-End Integration):  95 tests (DML execution, CTE, full pipeline)
Phase 7 (Transactions):            26 tests (transaction, savepoint, rollback)
Phase 8 (Migrations):              79 tests (discovery, application, checksum validation)
Phase 8.5 (Window Functions):      79 tests (ranking, value, aggregate window functions)
Phase 8.6 (Set Operations):       102 tests (UNION, INTERSECT, EXCEPT)
Phase 8.7 (UPSERT):                86 tests (ON CONFLICT DO NOTHING/UPDATE)
Phase 10 (DDL Support):           227 tests (CREATE/ALTER/DROP TABLE, CREATE/DROP INDEX)
Phase 11 (PostgreSQL Dialect):    102 tests (PostgreSQL SQL generation, driver, codecs)
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

See [`docs/roadmap.md`](docs/roadmap.md) for the complete implementation plan.

**Progress:**

- ✅ Phase 1-3 (Expressions, Queries, SQLite Dialect): 6 weeks - **COMPLETED**
- ✅ Phase 4-6 (Driver, Codec, Integration): 6 weeks - **COMPLETED**
- ✅ Phase 7-8 (Transactions, Migrations): 2 weeks - **COMPLETED**
- ✅ Phase 8.5-8.7 (Window Functions, Set Operations, UPSERT): 1 week - **COMPLETED**
- ✅ Phase 10 (DDL Support): 1 week - **COMPLETED**
- ✅ Phase 11 (PostgreSQL Dialect): 2 weeks - **COMPLETED**
- ⏳ Phase 12 (Documentation): 2+ weeks - **NEXT**

**Current Status:** 11/12 phases complete (91.7%)

---

## License

MIT License
