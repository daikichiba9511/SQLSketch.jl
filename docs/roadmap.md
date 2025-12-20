# SQLSketch.jl – Implementation Roadmap

**Last Updated:** 2025-12-20

This document outlines the phased implementation plan for SQLSketch.jl,
based on the design document (`design.md`).

---

## Implementation Philosophy

- **Test-driven**: Write tests before or alongside implementation
- **Bottom-up**: Build foundational abstractions first
- **Incremental**: Each phase should produce working, testable code
- **SQLite-first**: Use SQLite for rapid iteration and testing
- **Core-only initially**: Defer Easy layer until Core is stable

---

## Phase 1: Expression AST (Week 1-2)

**Goal**: Build the foundation for representing SQL expressions as typed ASTs.

### Tasks

1. Define core `Expr` types:
   - `ColRef` – column references (e.g., `users.id`)
   - `Literal` – literal values (e.g., `42`, `"hello"`)
   - `Param` – bound parameters (e.g., `:email`)
   - `BinaryOp` – binary operators (e.g., `=`, `<`, `AND`, `OR`)
   - `UnaryOp` – unary operators (e.g., `NOT`, `IS NULL`)
   - `FuncCall` – function calls (e.g., `COUNT(*)`, `LOWER(email)`)

2. Implement operator overloading for Julia operators:
   - `==`, `!=`, `<`, `>`, `<=`, `>=`
   - `&` (AND), `|` (OR), `!` (NOT)

3. Implement helper constructors:
   - `col(table::Symbol, column::Symbol)`
   - `param(T::Type, name::Symbol)`
   - `literal(value)`

4. Write comprehensive unit tests for expression construction

### Deliverables

- `src/Core/expr.jl`
- `test/core/expr_test.jl`
- All tests passing

### Success Criteria

```julia
# Should be able to write:
expr = col(:users, :email) == param(String, :email)
# → BinaryOp(=, ColRef(:users, :email), Param(String, :email))
```

---

## Phase 2: Query AST (Week 3-4) ✅ COMPLETED

**Goal**: Define query structure types and pipeline API.

### Tasks ✅

1. Define core query nodes:
   - `From{T}` – table source ✅
   - `Where{T}` – filter condition (shape-preserving) ✅
   - `Join{T}` – join operation ✅
   - `Select{OutT}` – projection (shape-changing) ✅
   - `OrderBy{T}` – ordering (shape-preserving) ✅
   - `Limit{T}` – limit/offset (shape-preserving) ✅
   - `GroupBy{T}`, `Having{T}`, `Distinct{T}` ✅
   - **DML nodes**: `InsertInto`, `Update`, `DeleteFrom` ✅
   - **CTE nodes**: `CTE`, `With{T}` ✅
   - **RETURNING support** ✅

2. Implement pipeline API:
   - `from(table::Symbol)` → `From{NamedTuple}` ✅
   - `where(q, expr)` → shape-preserving transformation ✅
   - `select(q, OutT, fields...)` → shape-changing transformation ✅
   - `order_by(q, field; desc=false)` ✅
   - `limit(q, n)` ✅
   - **Curried versions for natural pipeline composition** ✅

3. Define placeholder API (optional sugar):
   - Placeholder type `p_` ✅
   - Expansion to explicit `ColRef` ✅

4. Implement query composition (pipeline chaining with `|>`) ✅

5. Write unit tests for query construction ✅

### Deliverables ✅

- `src/Core/query.jl` ✅
- `test/core/query_test.jl` ✅ (202 tests)
- All tests passing ✅

### Success Criteria ✅

```julia
# Should be able to write:
q = from(:users) |>
    where(col(:users, :active) == literal(true)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email)) |>
    limit(10)

# Query AST should be well-typed and inspectable
```

---

## Phase 3: Dialect Abstraction (Week 5-6)

**Goal**: Compile Query AST into SQL strings.

### Tasks

1. Define `Dialect` abstract type and interface:
   - `compile(dialect, query)` → `(sql::String, params::Vector)`
   - `quote_identifier(dialect, name)` → quoted identifier
   - `placeholder(dialect, idx)` → parameter placeholder

2. Define `Capability` enum:
   - `CAP_CTE`, `CAP_RETURNING`, `CAP_UPSERT`, etc.
   - `supports(dialect, capability)` → Bool

3. Implement `SQLiteDialect`:
   - Expression compilation
   - Query compilation (FROM, WHERE, SELECT, JOIN, ORDER BY, LIMIT)
   - Identifier quoting (`` `identifier` ``)
   - Placeholder syntax (`?`)
   - Capability reporting

4. Write extensive unit tests:
   - Test SQL generation for various query shapes
   - Test parameter ordering
   - Test identifier quoting edge cases
   - **No database required** – pure string generation

### Deliverables

- `src/Core/dialect.jl`
- `src/Dialects/sqlite.jl`
- `test/dialects/sqlite_test.jl`
- All tests passing

### Success Criteria

```julia
q = from(:users) |> where(col(:users, :id) == param(Int, :id))
sql, params = compile(SQLiteDialect(), q)

# sql    → "SELECT * FROM `users` WHERE `users`.`id` = ?"
# params → [:id]
```

---

## Phase 4: Driver Abstraction (Week 7-8)

**Goal**: Execute SQL and manage connections.

### Tasks

1. Define `Driver` abstract type and interface:
   - `connect(driver, config)` → connection handle
   - `execute(conn, sql, params)` → raw result
   - `close(conn)`

2. Define `Transaction` interface:
   - `transaction(f, conn)` → executes `f(tx)`, commits or rolls back
   - Transaction handles should be connection-compatible

3. Implement `SQLiteDriver`:
   - Use `SQLite.jl` and `DBInterface.jl`
   - Connection management
   - Query execution
   - Transaction support

4. Write integration tests:
   - In-memory SQLite database
   - Basic CRUD operations
   - Transaction commit/rollback

### Deliverables

- `src/Core/driver.jl`
- `src/Drivers/sqlite.jl`
- `test/drivers/sqlite_test.jl`
- All tests passing

### Success Criteria

```julia
db = connect(SQLiteDriver(), ":memory:")
execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")
execute(db, "INSERT INTO users (email) VALUES (?)", ["test@example.com"])
result = execute(db, "SELECT * FROM users")
# → raw SQLite.Query result
close(db)
```

---

## Phase 5: CodecRegistry (Week 9-10)

**Goal**: Type-safe encoding/decoding between Julia and SQL.

### Tasks

1. Define `Codec` interface:
   - `encode(codec, value)` → database-compatible value
   - `decode(codec, dbvalue)` → Julia value

2. Define `CodecRegistry`:
   - Register codecs by Julia type
   - `get_codec(registry, T::Type)` → Codec

3. Implement default codecs:
   - `Int`, `Float64`, `String`, `Bool`
   - `Date`, `DateTime`
   - `UUID` (as TEXT for SQLite)
   - `Missing` (NULL policy)

4. Implement row mapping:
   - `map_row(registry, ::Type{NamedTuple}, row)` → NamedTuple
   - `map_row(registry, ::Type{T}, row)` → T (struct construction)

5. Write unit tests for encode/decode logic

6. Write integration tests for end-to-end type conversion

### Deliverables

- `src/Core/codec.jl`
- `test/core/codec_test.jl`
- All tests passing

### Success Criteria

```julia
registry = CodecRegistry()
register!(registry, Int, IntCodec())
register!(registry, String, StringCodec())

# Encode
encoded = encode(get_codec(registry, Int), 42)
# → 42

# Decode
decoded = decode(get_codec(registry, String), "hello")
# → "hello"

# NULL handling
decoded = decode(get_codec(registry, Union{Int, Missing}), missing)
# → missing
```

---

## Phase 6: End-to-End Integration (Week 11-12)

**Goal**: Complete query execution pipeline.

### Tasks

1. Implement query execution API:
   - `fetch_all(conn, dialect, registry, query)` → `Vector{OutT}`
   - `fetch_one(conn, dialect, registry, query)` → `OutT` (error if not exactly one row)
   - `fetch_maybe(conn, dialect, registry, query)` → `Union{OutT, Nothing}`

2. Integrate all components:
   - Query AST → Dialect → SQL
   - Driver → Execution → Raw results
   - CodecRegistry → Mapped results

3. Implement observability hooks:
   - `sql(query)` → SQL string for inspection
   - `explain(conn, query)` → EXPLAIN output

4. Write comprehensive integration tests:
   - Full CRUD workflows
   - Complex queries (joins, subqueries)
   - Type conversion edge cases
   - Error handling

### Deliverables

- `src/Core/execute.jl`
- `test/integration/end_to_end_test.jl`
- All tests passing

### Success Criteria

```julia
db = connect(SQLiteDriver(), ":memory:")
execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")

# Insert
q_insert = insert_into(:users, [:email]) |> values([param(String, :email)])
execute(db, q_insert, (email="test@example.com",))

# Query
q = from(:users) |>
    where(col(:users, :email) == param(String, :email)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

result = fetch_all(db, dialect, registry, q, (email="test@example.com",))
# → [(id=1, email="test@example.com")]
```

---

## Phase 7: Transactions (Week 13) ✅ COMPLETED

**Goal**: Reliable transaction support.

### Tasks ✅

1. Implement transaction API:
   - `transaction(f, conn)` → commit on success, rollback on exception ✅
   - Transaction handles compatible with query execution ✅

2. Add isolation level support (if capabilities allow) - Future

3. Add savepoint support (if capabilities allow) ✅

4. Write tests:
   - Commit on success ✅
   - Rollback on exception ✅
   - Nested transactions (savepoints) ✅

### Deliverables ✅

- `src/Core/transaction.jl` ✅
- `test/core/transaction_test.jl` ✅ (26 tests)
- All tests passing ✅

### Success Criteria ✅

```julia
transaction(db) do tx
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["user1@example.com"])
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["user2@example.com"])
end
# → both inserts committed

transaction(db) do tx
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["user3@example.com"])
    error("Oops!")
end
# → rollback, no data inserted
```

---

## Phase 8: Migration Runner (Week 14) ✅ COMPLETED

**Goal**: Minimal schema management.

### Tasks ✅

1. Implement migration runner:
   - `apply_migrations(db, migrations_dir)` ✅
   - `generate_migration(dir, name)` ✅
   - Track applied migrations in `schema_migrations` table ✅
   - Apply migrations in deterministic order ✅
   - Prevent re-application ✅
   - SHA256 checksum validation ✅

2. Support raw SQL migrations ✅

3. Support DDL operations compiled via Dialect (optional) - Future

4. Write tests:
   - Initial schema creation ✅
   - Incremental migrations ✅
   - Idempotency ✅
   - Checksum validation ✅
   - Transaction-wrapped execution ✅

### Deliverables ✅

- `src/Core/migrations.jl` ✅
- `test/core/migrations_test.jl` ✅ (79 tests)
- All tests passing ✅

### Success Criteria ✅

```julia
# migrations/001_create_users.sql
# CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT);

apply_migrations(db, "migrations/")
# → users table created, migration tracked

apply_migrations(db, "migrations/")
# → no-op, already applied
```

---

## Phase 8.5: Window Functions ✅ COMPLETED

**Goal**: Add comprehensive window function support.

### Tasks ✅

1. Define window function AST types:
   - `WindowFrame` – frame specification (ROWS/RANGE/GROUPS BETWEEN ...) ✅
   - `Over` – OVER clause with PARTITION BY, ORDER BY, and frame ✅
   - `WindowFunc` – window function expression ✅

2. Implement window function constructors:
   - **Ranking functions**: `row_number()`, `rank()`, `dense_rank()`, `ntile()` ✅
   - **Value functions**: `lag()`, `lead()`, `first_value()`, `last_value()`, `nth_value()` ✅
   - **Aggregate window functions**: `win_sum()`, `win_avg()`, `win_min()`, `win_max()`, `win_count()` ✅

3. Implement frame specification:
   - `window_frame()` – create frame specs with ROWS/RANGE/GROUPS modes ✅
   - Support for PRECEDING, FOLLOWING, CURRENT ROW, UNBOUNDED bounds ✅
   - Both single and range bounds ✅

4. Implement OVER clause builder:
   - `over()` – create OVER clauses with PARTITION BY, ORDER BY, and frames ✅

5. Add SQL compilation for window functions in SQLite dialect ✅

6. Write comprehensive tests ✅

### Deliverables ✅

- `src/Core/expr.jl` (window function types added) ✅
- `src/Dialects/sqlite.jl` (window function compilation) ✅
- `test/core/window_test.jl` ✅ (79 tests)
- All tests passing ✅

### Success Criteria ✅

```julia
# Ranking within partitions
from(:employees) |>
    select(NamedTuple,
           col(:employees, :name),
           col(:employees, :department),
           row_number(over(partition_by=[col(:employees, :department)],
                          order_by=[(col(:employees, :salary), true)])))

# Running totals with frames
from(:sales) |>
    select(NamedTuple,
           col(:sales, :date),
           win_sum(col(:sales, :amount),
                  over(order_by=[(col(:sales, :date), false)],
                       frame=window_frame(:ROWS, :UNBOUNDED_PRECEDING, :CURRENT_ROW))))
```

**Test Count**: 79 passing tests
**Total Tests**: 1274 passing ✅

---

## Phase 8.6: Set Operations (UNION / INTERSECT / EXCEPT) ✅ COMPLETED

**Goal**: Add set operation support for combining query results.

### Tasks ✅

1. Define set operation AST types:
   - `SetUnion` – UNION / UNION ALL operation ✅
   - `SetIntersect` – INTERSECT operation ✅
   - `SetExcept` – EXCEPT operation ✅

2. Implement set operation constructors:
   - `union(left, right; all=false)` – combine with UNION ✅
   - `intersect(left, right)` – find common rows ✅
   - `except(left, right)` – find difference ✅
   - Curried versions for pipeline composition ✅

3. Add SQL compilation for set operations in SQLite dialect ✅

4. Support chaining and nesting of set operations ✅

5. Write comprehensive tests ✅

### Deliverables ✅

- `src/Core/query.jl` (set operation types added) ✅
- `src/Dialects/sqlite.jl` (set operation compilation) ✅
- `test/core/set_operations_test.jl` ✅ (102 tests)
- All tests passing ✅

### Success Criteria ✅

```julia
# Combine active users from two tables
from(:users) |>
    where(col(:users, :active) == literal(true)) |>
    select(NamedTuple, col(:users, :email)) |>
    union(
        from(:legacy_users) |>
        where(col(:legacy_users, :active) == literal(true)) |>
        select(NamedTuple, col(:legacy_users, :email))
    )
# → SELECT `users`.`email` FROM `users` WHERE `users`.`active` = 1
#   UNION
#   SELECT `legacy_users`.`email` FROM `legacy_users` WHERE `legacy_users`.`active` = 1

# Find users in both tables
q1 = from(:users) |> select(NamedTuple, col(:users, :email))
q2 = from(:legacy_users) |> select(NamedTuple, col(:legacy_users, :email))
q1 |> intersect(q2)
```

**Test Count**: 102 passing tests
**Total Tests**: 1297 passing ✅

---

## Phase 8.7: UPSERT (ON CONFLICT) ✅ COMPLETED

**Goal**: Add UPSERT support for handling insert conflicts.

### Tasks ✅

1. Define UPSERT AST type:
   - `OnConflict{T}` – ON CONFLICT clause ✅

2. Implement UPSERT constructors:
   - `on_conflict_do_nothing(target=nothing)` – ignore conflicts ✅
   - `on_conflict_do_update(target, updates...; where=nothing)` – update on conflict ✅
   - Curried versions for pipeline composition ✅

3. Support conflict target specification:
   - Specific columns ✅
   - No target (any constraint) ✅

4. Support conditional updates with WHERE clause ✅

5. Add SQL compilation for UPSERT in SQLite dialect ✅

6. Write comprehensive tests ✅

### Deliverables ✅

- `src/Core/query.jl` (OnConflict type added) ✅
- `src/Dialects/sqlite.jl` (UPSERT compilation) ✅
- `test/core/upsert_test.jl` ✅ (86 tests)
- All tests passing ✅

### Success Criteria ✅

```julia
# Ignore conflicts
insert_into(:users, [:id, :email]) |>
    values([[param(Int, :id), param(String, :email)]]) |>
    on_conflict_do_nothing()
# → INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT DO NOTHING

# Update on conflict
insert_into(:users, [:id, :email, :name]) |>
    values([[param(Int, :id), param(String, :email), param(String, :name)]]) |>
    on_conflict_do_update(
        [:email],
        :name => col(:excluded, :name),
        :updated_at => func(:CURRENT_TIMESTAMP, SQLExpr[])
    )
# → INSERT INTO `users` (`id`, `email`, `name`) VALUES (?, ?, ?)
#   ON CONFLICT (`email`) DO UPDATE SET
#   `name` = `excluded`.`name`, `updated_at` = CURRENT_TIMESTAMP()

# Conditional update with WHERE
insert_into(:users, [:id, :email, :version]) |>
    values([[param(Int, :id), param(String, :email), param(Int, :version)]]) |>
    on_conflict_do_update(
        [:email],
        :version => col(:excluded, :version);
        where = col(:users, :version) < col(:excluded, :version)
    )
```

**Test Count**: 86 passing tests
**Total Tests**: 1383 passing ✅

---

## Phase 11: PostgreSQL Dialect (Week 15-16) ✅ COMPLETED

**Goal**: Validate multi-database abstraction.

### Tasks ✅

1. Implement `PostgreSQLDialect`: ✅
   - SQL generation ✅
   - Identifier quoting (`"identifier"`) ✅
   - Placeholder syntax (`$1`, `$2`, ...) ✅
   - Capability reporting (CTE, RETURNING, UPSERT, WINDOW, LATERAL, BULK_COPY, SAVEPOINT, ADVISORY_LOCK) ✅

2. Implement `PostgreSQLDriver` ✅
   - LibPQ.jl integration ✅
   - Connection management (libpq connection strings) ✅
   - Transaction support (BEGIN/COMMIT/ROLLBACK) ✅
   - Savepoint support (nested transactions) ✅

3. Add PostgreSQL-specific codecs: ✅
   - UUID (native PostgreSQL type) ✅
   - JSONB (Dict/Vector serialization) ✅
   - Arrays (Integer[], Text[], generic arrays) ✅
   - Boolean (native BOOLEAN) ✅
   - Date/DateTime (native DATE/TIMESTAMP) ✅

4. Write compatibility tests ✅
   - 102 PostgreSQL dialect tests ✅
   - Comprehensive integration tests ✅
   - Comparison tests with SQLite ✅

5. Full DDL support: ✅
   - CREATE TABLE, ALTER TABLE, DROP TABLE ✅
   - CREATE INDEX, DROP INDEX ✅
   - Portable column type mapping ✅

### Deliverables ✅

- `src/Dialects/postgresql.jl` ✅
- `src/Drivers/postgresql.jl` ✅
- `src/Codecs/postgresql.jl` ✅
- `test/dialects/postgresql_test.jl` ✅ (102 tests)
- `test/integration/postgresql_integration_test.jl` ✅
- Compatibility tests passing ✅

### Status

✅ **COMPLETED** - Full PostgreSQL support with comprehensive dialect, driver, and codec implementations

**Test Count**: 102 passing tests
**Total Tests**: 1712 passing ✅

---

## Phase 10: DDL Support (Week 17)

**Goal**: Type-safe schema definition with DDL operations.

### Tasks

1. ✅ Design DDL AST (CreateTable, AlterTable, DropTable, CreateIndex, DropIndex)
2. ✅ Implement column constraints (PRIMARY KEY, NOT NULL, UNIQUE, DEFAULT, CHECK, FOREIGN KEY)
3. ✅ Implement table constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK)
4. ✅ Create portable column type system
5. ✅ Implement pipeline API with currying
6. ✅ Add DDL compilation to SQLite dialect
7. ✅ Write comprehensive unit tests (156 tests)
8. ✅ Write dialect-specific compilation tests (71 tests)
9. ✅ Add docstrings to all public functions

### Deliverables

- ✅ `src/Core/ddl.jl` - DDL AST types and pipeline API
- ✅ DDL compilation in `src/Dialects/sqlite.jl`
- ✅ `test/core/ddl_test.jl` - DDL AST unit tests
- ✅ DDL compilation tests in `test/dialects/sqlite_test.jl`
- ✅ 227 total DDL tests

### Status

✅ **COMPLETED** - Full DDL support with type-safe schema definitions

---

## Phase 12: Documentation (Week 18+) ✅ COMPLETED

**Goal**: User-facing documentation and examples.

### Tasks ✅

1. Write getting-started guide ✅
2. Write API reference ✅
3. Write design rationale document ✅
4. Create example applications ✅
5. Write migration guide ✅

### Deliverables ✅

- `docs/src/getting-started.md` ✅
- `docs/src/api.md` ✅
- `docs/src/tutorial.md` ✅ (includes examples)
- `docs/src/index.md` ✅
- Complete documentation site structure ✅

### Status

✅ **COMPLETED** - Full documentation with getting started guide, API reference, and comprehensive tutorial

---

## Optional Future Work (Post-v0.1)

- MySQL Dialect
- ~~Set operations (UNION, INTERSECT, EXCEPT)~~ ✅ **COMPLETED in Phase 8.6**
- Recursive CTEs (WITH RECURSIVE)
- ~~UPSERT (INSERT ... ON CONFLICT)~~ ✅ **COMPLETED in Phase 8.7**
- ~~Window Functions~~ ✅ **COMPLETED in Phase 8.5**
- ~~DDL operations (CREATE TABLE, ALTER TABLE, etc.)~~ ✅ **COMPLETED in Phase 10**
- Easy Layer (Repository pattern, CRUD helpers)
- Relation preloading
- Schema definition macros
- Query optimization hints
- Connection pooling
- Prepared statement caching
- Batch insert/update operations
- Streaming results for large datasets

---

## Milestones

| Phase | Duration | Milestone | Status |
|-------|----------|-----------|--------|
| 1-3   | 6 weeks  | **M1**: Query construction and SQL generation (no database) | ✅ COMPLETED |
| 4-6   | 6 weeks  | **M2**: Full SQLite integration with type safety | ✅ COMPLETED |
| 7-8   | 2 weeks  | **M3**: Transactions and migrations | ✅ COMPLETED |
| 8.5-8.7 | 1 week | **M3.5**: Advanced SQL features (Window Functions, Set Operations, UPSERT) | ✅ COMPLETED |
| 10    | 1 week   | **M4**: DDL support with type-safe schema definitions | ✅ COMPLETED |
| 11    | 2 weeks  | **M5**: PostgreSQL support (validation of abstraction) | ✅ COMPLETED |
| 12    | 2+ weeks | **M6**: Documentation and examples | ✅ COMPLETED |

---

## Success Metrics

- ✅ All tests pass on Julia 1.9+ (1712 tests passing)
- ✅ Test coverage > 90%
- ✅ No database required for 60%+ of tests
- ✅ Generated SQL is valid and performant
- ✅ API feels natural to Julia developers
- ✅ Design.md goals are met
- ✅ Multi-database abstraction validated (SQLite + PostgreSQL)

## Current Status

**All phases completed successfully! 🎉**

- 1712 total tests passing ✅
- Full SQLite support
- Full PostgreSQL support
- Advanced SQL features (Window Functions, Set Operations, UPSERT, DDL)
- Transaction and migration support
- Type-safe query execution pipeline
- Complete documentation suite
- **Ready for v0.1.0 release!**
