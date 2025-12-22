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

**Completed:** 13/13 phases | **Tests:** 2215 passing ✅

Core features implemented:

- ✅ Expression & Query AST (500 tests)
- ✅ SQLite, PostgreSQL & MySQL dialects (577 tests)
- ✅ Type-safe execution & codecs (251 tests)
- ✅ Transactions & migrations (105 tests)
- ✅ Window functions, set operations, UPSERT (267 tests)
- ✅ DDL support (227 tests)
- ✅ Connection pooling & batch operations (58 tests)
- ✅ Prepared statement caching (MySQL, PostgreSQL)
- ✅ **Query Plan Cache & Performance Tooling** (89 tests)
  - Query Plan Cache: 4.85-6.95x speedup
  - Performance profiling with `@timed_query`
  - EXPLAIN analysis and index detection

**Supported Databases:**
- **SQLite** - Full support (in-memory & file-based)
- **PostgreSQL** - Full support with advanced features (COPY, JSONB, UUID, Arrays)
- **MySQL** - Full support with JSON codec & prepared statement caching (MySQL 8.0+ tested)

See [**Implementation Status**](docs/implementation-status.md) for detailed breakdown.

---

## Features at a Glance

### Query Building
| Feature | SQLite | PostgreSQL | MySQL | Description |
|---------|--------|------------|-------|-------------|
| **SELECT** | ✅ | ✅ | ✅ | Basic and complex projections |
| **WHERE** | ✅ | ✅ | ✅ | Filtering with expressions |
| **JOIN** | ✅ | ✅ | ✅ | INNER, LEFT, RIGHT, FULL |
| **GROUP BY** | ✅ | ✅ | ✅ | Aggregation grouping |
| **HAVING** | ✅ | ✅ | ✅ | Post-aggregation filtering |
| **ORDER BY** | ✅ | ✅ | ✅ | ASC/DESC sorting |
| **LIMIT/OFFSET** | ✅ | ✅ | ✅ | Result pagination |
| **DISTINCT** | ✅ | ✅ | ✅ | Remove duplicates |
| **Subqueries** | ✅ | ✅ | ✅ | Nested SELECT expressions |
| **CTE (WITH)** | ✅ | ✅ | ✅ | Common Table Expressions |

### SQL Expressions & Operators
| Feature | SQLite | PostgreSQL | MySQL | Description |
|---------|--------|------------|-------|-------------|
| **Aggregate Functions** | ✅ | ✅ | ✅ | COUNT, SUM, AVG, MIN, MAX |
| **CASE Expressions** | ✅ | ✅ | ✅ | Conditional logic (CASE WHEN) |
| **CAST** | ✅ | ✅ | ✅ | Type conversion |
| **COALESCE** | ✅ | ✅ | ✅ | NULL handling (via func()) |
| **LIKE/ILIKE** | ✅ | ✅ | ✅ | Pattern matching |
| **IN/NOT IN** | ✅ | ✅ | ✅ | List membership |
| **BETWEEN** | ✅ | ✅ | ✅ | Range queries |
| **IS NULL/IS NOT NULL** | ✅ | ✅ | ✅ | NULL checking |
| **Arithmetic Operators** | ✅ | ✅ | ✅ | +, -, *, /, % |
| **Comparison Operators** | ✅ | ✅ | ✅ | =, !=, <, >, <=, >= |
| **Logical Operators** | ✅ | ✅ | ✅ | AND, OR, NOT |
| **String Functions** | ✅ | ✅ | ✅ | CONCAT, UPPER, LOWER, etc. (via func()) |
| **Math Functions** | ✅ | ✅ | ✅ | ROUND, ABS, POW, etc. (via func()) |
| **Date/Time Functions** | ✅ | ✅ | ✅ | NOW, DATE, etc. (via func()) |

### Data Manipulation
| Feature | SQLite | PostgreSQL | MySQL | Description |
|---------|--------|------------|-------|-------------|
| **INSERT** | ✅ | ✅ | ✅ | Single and multi-row |
| **UPDATE** | ✅ | ✅ | ✅ | Conditional updates |
| **DELETE** | ✅ | ✅ | ✅ | Conditional deletes |
| **UPSERT** | ✅ | ✅ | ✅ | ON CONFLICT (INSERT...ON DUPLICATE KEY) |
| **RETURNING** | ✅ | ✅ | ❌ | Return modified rows |
| **Batch INSERT** | ✅ | ✅ (COPY) | ✅ | High-performance bulk inserts |

### Advanced Features
| Feature | SQLite | PostgreSQL | MySQL | Description |
|---------|--------|------------|-------|-------------|
| **Window Functions** | ✅ | ✅ | ✅ | OVER, PARTITION BY, ROW_NUMBER, RANK, etc. |
| **Set Operations** | ✅ | ✅ | ✅ | UNION, INTERSECT, EXCEPT |
| **Transactions** | ✅ | ✅ | ✅ | BEGIN, COMMIT, ROLLBACK |
| **Savepoints** | ✅ | ✅ | ✅ | Nested transactions |
| **Prepared Statements** | ❌ | ✅ | ✅ | Statement caching (10-20% speedup) |
| **Connection Pooling** | ❌ | ✅ | ✅ | Thread-safe connection reuse |

### DDL (Schema Management)
| Feature | SQLite | PostgreSQL | MySQL | Description |
|---------|--------|------------|-------|-------------|
| **CREATE TABLE** | ✅ | ✅ | ✅ | Table creation with constraints |
| **ALTER TABLE** | ✅ | ✅ | ✅ | Add/drop columns |
| **DROP TABLE** | ✅ | ✅ | ✅ | Table deletion |
| **CREATE INDEX** | ✅ | ✅ | ✅ | Index creation (UNIQUE, multi-column) |
| **DROP INDEX** | ✅ | ✅ | ✅ | Index deletion |
| **PRIMARY KEY** | ✅ | ✅ | ✅ | Column and table constraints |
| **FOREIGN KEY** | ✅ | ✅ | ✅ | Referential integrity |
| **UNIQUE** | ✅ | ✅ | ✅ | Uniqueness constraints |
| **NOT NULL** | ✅ | ✅ | ✅ | Non-null constraints |
| **DEFAULT** | ✅ | ✅ | ✅ | Default values |
| **CHECK** | ✅ | ✅ | ✅ | Custom validation |
| **AUTO_INCREMENT** | ✅ | ✅ (SERIAL) | ✅ | Auto-incrementing IDs |
| **Migrations** | ✅ | ✅ | ✅ | Version-based schema migrations |
| **CREATE VIEW** | ❌ | ❌ | ❌ | Not yet supported |
| **Triggers** | ❌ | ❌ | ❌ | Not yet supported |
| **Stored Procedures** | ❌ | ❌ | ❌ | Not yet supported |

### Type Support
| Feature | SQLite | PostgreSQL | MySQL | Description |
|---------|--------|------------|-------|-------------|
| **Integer, Float, String** | ✅ | ✅ | ✅ | Basic types |
| **Boolean** | ✅ | ✅ | ✅ | Native or emulated |
| **Date, DateTime** | ✅ | ✅ | ✅ | Temporal types |
| **UUID** | ✅ | ✅ (native) | ✅ | Universally unique identifiers |
| **JSON** | ✅ | ✅ (JSONB) | ✅ | JSON documents |
| **Arrays** | ❌ | ✅ (native) | ❌ | Native array support |
| **NULL/Missing** | ✅ | ✅ | ✅ | Null handling |

### Performance Optimizations
| Feature | SQLite | PostgreSQL | MySQL | Description |
|---------|--------|------------|-------|-------------|
| **Query Plan Cache** | ✅ | ✅ | ✅ | 4.85-6.95x compilation speedup |
| **Prepared Stmt Cache** | ❌ | ✅ | ✅ | 10-20% execution speedup |
| **Connection Pool** | ❌ | ✅ | ✅ | 4-5x speedup (concurrent) |
| **Batch INSERT** | ✅ | ✅ (COPY) | ✅ | 1.35x-2016x speedup |
| **Columnar Fetch** | ✅ | ✅ | ✅ | 8-10x faster for analytics |
| **@timed_query** | ✅ | ✅ | ✅ | Performance profiling |
| **EXPLAIN analysis** | ✅ | ✅ | ✅ | Query plan inspection |

**Legend:**
- ✅ Fully supported
- ❌ Not supported
- 🔶 Partial support

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
    inner_join(:orders, col(:orders, :user_id) == col(:users, :id)) |>
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

**6. High-Performance Analytics with Columnar API**

```julia
using SQLSketch

# Define columnar struct (fields as Vectors)
struct SalesColumnar
    product_name::Vector{String}
    revenue::Vector{Float64}
    quantity::Vector{Int}
end

# Query large dataset
q = from(:sales) |>
    inner_join(:products, col(:products, :id) == col(:sales, :product_id)) |>
    select(NamedTuple,
           col(:products, :name),
           col(:sales, :revenue),
           col(:sales, :quantity))

# Fetch in columnar format (8-10x faster for large datasets!)
sales = fetch_all_columnar(db, dialect, registry, q, SalesColumnar)

# Direct column operations (extremely fast)
total_revenue = sum(sales.revenue)
total_quantity = sum(sales.quantity)
```

**Performance comparison:**

| API | 500 rows | 1667 rows | Best for |
|-----|----------|-----------|----------|
| `fetch_all` (row-based) | ~327 μs | ~2.5 ms | CRUD, small datasets |
| `fetch_all_columnar` (columnar) | ~252 μs | ~1.1 ms | Analytics, large datasets |

**Speedup:** 8-10x faster for analytics workloads

**7. Connection Pooling for High Concurrency**

```julia
using SQLSketch

# Create connection pool
pool = ConnectionPool(PostgreSQLDriver(),
                      "postgresql://localhost/mydb";
                      min_size=2, max_size=10)

# Resource-safe pattern (recommended)
with_connection(pool) do conn
    users = fetch_all(conn, dialect, registry, query)
end

# Cleanup
close(pool)
```

**Performance benefits:**
- >80% reduction in connection overhead
- 5-10x faster for short queries
- Better resource utilization under high concurrency

**8. Using MySQL**

```julia
using SQLSketch
using SQLSketch.Drivers: MySQLDriver

# Connect to MySQL
driver = MySQLDriver()
db = connect(driver, "localhost", "mydb"; user="root", password="secret")
dialect = MySQLDialect()
registry = CodecRegistry()

# MySQL-specific: JSON support
using SQLSketch.Codecs.MySQL
MySQL.register_mysql_codecs!(registry)

# Query with JSON column
q = from(:users) |>
    where(col(:users, :active) == literal(true)) |>
    select(NamedTuple, col(:users, :id), col(:users, :metadata))

results = fetch_all(db, dialect, registry, q)
close(db)
```

**MySQL features:**
- Native JSON type support (MySQL 5.7+)
- Prepared statement caching (10-20% speedup)
- Full DDL support
- **Note:** MariaDB may work via MySQL protocol compatibility but is not explicitly tested

**9. DDL - Create Table**

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
    mysql.jl         # MySQL SQL generation ✅
    shared_helpers.jl # Shared helper functions ✅
  Drivers/           # Driver implementations
    sqlite.jl        # SQLite execution ✅
    postgresql.jl    # PostgreSQL execution ✅
    mysql.jl         # MySQL execution ✅
  Codecs/            # Database-specific codecs
    postgresql.jl    # PostgreSQL-specific codecs (UUID, JSONB, Array) ✅
    mysql.jl         # MySQL-specific codecs (JSON, BLOB, Date, DateTime) ✅

test/                # Test suite (2126 tests)
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
    inner_join(:users, col(:recent_orders, :user_id) == col(:users, :id)) |>
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
