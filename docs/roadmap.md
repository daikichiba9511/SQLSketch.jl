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

## Phase 2: Query AST (Week 3-4)

**Goal**: Define query structure types and pipeline API.

### Tasks

1. Define core query nodes:
   - `From{T}` – table source
   - `Where{T}` – filter condition (shape-preserving)
   - `Join{T}` – join operation
   - `Select{OutT}` – projection (shape-changing)
   - `OrderBy{T}` – ordering (shape-preserving)
   - `Limit{T}` – limit/offset (shape-preserving)

2. Implement pipeline API:
   - `from(table::Symbol)` → `From{NamedTuple}`
   - `where(q, expr)` → shape-preserving transformation
   - `select(q, OutT, fields...)` → shape-changing transformation
   - `order_by(q, field; desc=false)`
   - `limit(q, n)`

3. Define placeholder API (optional sugar):
   - Placeholder type `_`
   - Expansion to explicit `ColRef`

4. Implement query composition (pipeline chaining with `|>`)

5. Write unit tests for query construction

### Deliverables

- `src/Core/query.jl`
- `test/core/query_test.jl`
- All tests passing

### Success Criteria

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

## Phase 7: Transactions (Week 13)

**Goal**: Reliable transaction support.

### Tasks

1. Implement transaction API:
   - `transaction(f, conn)` → commit on success, rollback on exception
   - Transaction handles compatible with query execution

2. Add isolation level support (if capabilities allow)

3. Add savepoint support (if capabilities allow)

4. Write tests:
   - Commit on success
   - Rollback on exception
   - Nested transactions (if supported)

### Deliverables

- `src/Core/transaction.jl`
- `test/core/transaction_test.jl`
- All tests passing

### Success Criteria

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

## Phase 8: Migration Runner (Week 14)

**Goal**: Minimal schema management.

### Tasks

1. Implement migration runner:
   - `apply_migrations(db, migrations_dir)`
   - Track applied migrations in `schema_migrations` table
   - Apply migrations in deterministic order
   - Prevent re-application

2. Support raw SQL migrations

3. Support DDL operations compiled via Dialect (optional)

4. Write tests:
   - Initial schema creation
   - Incremental migrations
   - Idempotency

### Deliverables

- `src/Core/migrations.jl`
- `test/core/migrations_test.jl`
- All tests passing

### Success Criteria

```julia
# migrations/001_create_users.sql
# CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT);

apply_migrations(db, "migrations/")
# → users table created, migration tracked

apply_migrations(db, "migrations/")
# → no-op, already applied
```

---

## Phase 9: PostgreSQL Dialect (Week 15-16)

**Goal**: Validate multi-database abstraction.

### Tasks

1. Implement `PostgreSQLDialect`:
   - SQL generation
   - Identifier quoting (`"identifier"`)
   - Placeholder syntax (`$1`, `$2`, ...)
   - Capability reporting (CTE, RETURNING, UPSERT)

2. Implement `PostgreSQLDriver` (basic)

3. Add PostgreSQL-specific codecs:
   - UUID (native PostgreSQL type)
   - JSONB
   - Arrays

4. Write compatibility tests

### Deliverables

- `src/Dialects/postgresql.jl`
- `src/Drivers/postgresql.jl`
- `test/dialects/postgresql_test.jl`
- Compatibility tests passing

---

## Phase 10: Documentation (Week 17+)

**Goal**: User-facing documentation and examples.

### Tasks

1. Write getting-started guide
2. Write API reference
3. Write design rationale document
4. Create example applications
5. Write migration guide

### Deliverables

- `docs/getting_started.md`
- `docs/api.md`
- `examples/` directory

---

## Optional Future Work (Post-v0.1)

- MySQL Dialect
- Easy Layer (Repository pattern, CRUD helpers)
- Relation preloading
- Schema definition macros
- DDL generation
- Query optimization hints
- Connection pooling
- Prepared statement caching

---

## Milestones

| Phase | Duration | Milestone |
|-------|----------|-----------|
| 1-3   | 6 weeks  | **M1**: Query construction and SQL generation (no database) |
| 4-6   | 6 weeks  | **M2**: Full SQLite integration with type safety |
| 7-8   | 2 weeks  | **M3**: Transactions and migrations |
| 9     | 2 weeks  | **M4**: PostgreSQL support (validation of abstraction) |
| 10    | 2+ weeks | **M5**: Documentation and examples |

---

## Success Metrics

- All tests pass on Julia 1.9+
- Test coverage > 90%
- No database required for 60%+ of tests
- Generated SQL is valid and performant
- API feels natural to Julia developers
- Design.md goals are met
