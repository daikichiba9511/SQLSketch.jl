# SQLSketch.jl – Implementation TODO

Task breakdown based on `design.md` and `roadmap.md`.

**Legend:**
- ✅ Completed
- 🚧 In Progress
- ⏳ Pending
- 🔄 Blocked/Depends on other tasks

**Last Updated:** 2025-12-18

---

## Phase 1: Expression AST ✅ COMPLETED

### Core Types ✅
- [x] Define `Expr` abstract type
- [x] Implement `ColRef` struct
- [x] Implement `Literal` struct
- [x] Implement `Param` struct
- [x] Implement `BinaryOp` struct
- [x] Implement `UnaryOp` struct
- [x] Implement `FuncCall` struct

### Constructors ✅
- [x] `col(table, column)` helper
- [x] `literal(value)` helper
- [x] `param(T, name)` helper
- [x] `func(name, args)` helper

### Operator Overloading ✅
- [x] Comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`)
- [x] Logical operators (`&`, `|`, `!`)
- [x] Arithmetic operators (`+`, `-`, `*`, `/`)
- [x] Auto-wrap literals in comparison operators
- [x] Auto-wrap literals in arithmetic operators
- [x] NULL checking helpers (`is_null`, `is_not_null`)

### Tests ✅
- [x] Column reference tests
- [x] Literal tests
- [x] Parameter tests
- [x] Binary operator tests (comparison)
- [x] Binary operator tests (logical)
- [x] Binary operator tests (arithmetic)
- [x] Unary operator tests
- [x] Function call tests
- [x] Expression composition tests
- [x] Type hierarchy tests
- [x] Immutability tests

### Future Enhancements ⏳
- [ ] `IN` operator support
- [ ] `BETWEEN` operator support
- [ ] `LIKE` / `ILIKE` operator support
- [ ] Subquery expressions
- [ ] `CASE` expressions
- [ ] Type casting expressions
- [ ] Placeholder API (`_` for column references)

---

## Phase 2: Query AST ⏳ PENDING

### Core Query Types ⏳
- [ ] Define `Query{T}` abstract type
- [ ] Implement `From{T}` struct
- [ ] Implement `Where{T}` struct (shape-preserving)
- [ ] Implement `Join{T}` struct (shape-preserving)
- [ ] Implement `Select{OutT}` struct (shape-changing)
- [ ] Implement `OrderBy{T}` struct (shape-preserving)
- [ ] Implement `Limit{T}` struct (shape-preserving)
- [ ] Implement `Offset{T}` struct (shape-preserving)
- [ ] Implement `Distinct{T}` struct (shape-preserving)
- [ ] Implement `GroupBy{T}` struct
- [ ] Implement `Having{T}` struct

### Pipeline API ⏳
- [ ] `from(table::Symbol)` → `From{NamedTuple}`
- [ ] `where(q::Query, expr::Expr)` → `Where{T}`
- [ ] `join(q::Query, table, on)` → `Join{T}`
- [ ] `select(q::Query, OutT::Type, fields...)` → `Select{OutT}`
- [ ] `order_by(q::Query, field::Expr; desc=false)` → `OrderBy{T}`
- [ ] `limit(q::Query, n::Int)` → `Limit{T}`
- [ ] `offset(q::Query, n::Int)` → `Offset{T}`
- [ ] `distinct(q::Query)` → `Distinct{T}`
- [ ] `group_by(q::Query, fields...)` → `GroupBy{T}`
- [ ] `having(q::Query, expr::Expr)` → `Having{T}`

### Query Composition ⏳
- [ ] Implement pipeline chaining with `|>`
- [ ] Type-safe query transformations
- [ ] Shape-preserving vs shape-changing semantics

### Tests ⏳
- [ ] Create `test/core/query_test.jl`
- [ ] Test `from()` construction
- [ ] Test `where()` chaining
- [ ] Test `select()` type changes
- [ ] Test `join()` operations
- [ ] Test `order_by()` operations
- [ ] Test `limit()` and `offset()`
- [ ] Test complex query pipelines
- [ ] Test type safety and inference

### Future Enhancements ⏳
- [ ] Placeholder API (`_` for column references in queries)
- [ ] Subquery support (queries as expressions)
- [ ] CTE (Common Table Expressions) support
- [ ] UNION / INTERSECT / EXCEPT

---

## Phase 3: Dialect Abstraction ⏳ PENDING

### Dialect Interface ⏳
- [ ] Define `Dialect` abstract type
- [ ] Define `Capability` enum
- [ ] `compile(dialect, query)` → `(sql, params)` interface
- [ ] `compile_expr(dialect, expr)` → SQL fragment interface
- [ ] `quote_identifier(dialect, name)` → quoted identifier
- [ ] `placeholder(dialect, idx)` → parameter placeholder
- [ ] `supports(dialect, capability)` → Bool

### SQLite Dialect ⏳
- [ ] Implement `SQLiteDialect` struct
- [ ] Implement expression compilation
  - [ ] Compile `ColRef`
  - [ ] Compile `Literal`
  - [ ] Compile `Param`
  - [ ] Compile `BinaryOp`
  - [ ] Compile `UnaryOp`
  - [ ] Compile `FuncCall`
- [ ] Implement query compilation
  - [ ] Compile `From`
  - [ ] Compile `Where`
  - [ ] Compile `Select`
  - [ ] Compile `Join`
  - [ ] Compile `OrderBy`
  - [ ] Compile `Limit` / `Offset`
  - [ ] Compile `GroupBy` / `Having`
  - [ ] Compile `Distinct`
- [ ] Identifier quoting (backticks)
- [ ] Placeholder syntax (`?`)
- [ ] Capability reporting
  - [ ] CTE support
  - [ ] RETURNING support (SQLite 3.35+)
  - [ ] UPSERT support
  - [ ] Window functions

### Tests ⏳
- [ ] Create `test/dialects/sqlite_test.jl`
- [ ] Test expression compilation
- [ ] Test query compilation (all query types)
- [ ] Test identifier quoting edge cases
- [ ] Test parameter ordering
- [ ] Test capability reporting
- [ ] Test SQL string generation (no DB required)

### Future Enhancements ⏳
- [ ] DDL compilation (CREATE TABLE, ALTER TABLE, etc.)
- [ ] INSERT / UPDATE / DELETE statement compilation
- [ ] UPSERT (ON CONFLICT) compilation

---

## Phase 4: Driver Abstraction ⏳ PENDING

### Driver Interface ⏳
- [ ] Define `Driver` abstract type
- [ ] Define `Connection` abstract type
- [ ] `connect(driver, config)` → Connection interface
- [ ] `execute(conn, sql, params)` → raw result interface
- [ ] `close(conn)` interface
- [ ] Error normalization strategy

### SQLite Driver ⏳
- [ ] Implement `SQLiteDriver` struct
- [ ] Implement `SQLiteConnection` struct
- [ ] Add `SQLite.jl` dependency to Project.toml
- [ ] Add `DBInterface.jl` dependency to Project.toml
- [ ] Implement connection management
  - [ ] Connect to file database
  - [ ] Connect to in-memory database (`:memory:`)
  - [ ] Connection pooling (future)
- [ ] Implement query execution
  - [ ] Execute SQL with positional parameters
  - [ ] Return raw `SQLite.Query` results
- [ ] Implement connection cleanup
  - [ ] Close connection
  - [ ] Release resources
- [ ] Error handling and normalization

### Tests ⏳
- [ ] Create `test/drivers/sqlite_test.jl`
- [ ] Test in-memory database connection
- [ ] Test file database connection
- [ ] Test query execution
- [ ] Test parameter binding
- [ ] Test connection cleanup
- [ ] Test error handling

### Future Enhancements ⏳
- [ ] Prepared statement caching
- [ ] Query cancellation
- [ ] Timeout support
- [ ] Connection pooling

---

## Phase 5: CodecRegistry ⏳ PENDING

### Codec Interface ⏳
- [ ] Define `Codec` abstract type
- [ ] Define `CodecRegistry` struct
- [ ] `encode(codec, value)` → database value
- [ ] `decode(codec, dbvalue)` → Julia value
- [ ] `register!(registry, T, codec)`
- [ ] `get_codec(registry, T)` → Codec

### Default Codecs ⏳
- [ ] Implement `IntCodec`
- [ ] Implement `Float64Codec`
- [ ] Implement `StringCodec`
- [ ] Implement `BoolCodec`
- [ ] Implement `DateCodec`
- [ ] Implement `DateTimeCodec`
- [ ] Implement `UUIDCodec` (as TEXT for SQLite)
- [ ] Implement `MissingCodec` (NULL policy)
- [ ] Add `Dates` dependency to Project.toml
- [ ] Add `UUIDs` dependency to Project.toml

### Row Mapping ⏳
- [ ] `map_row(registry, ::Type{NamedTuple}, row)` → NamedTuple
- [ ] `map_row(registry, ::Type{T}, row)` → T (struct construction)
- [ ] Column name normalization
- [ ] Missing field handling
- [ ] Type conversion error handling

### NULL Handling ⏳
- [ ] Define global NULL policy (Missing-based)
- [ ] Encode `missing` → NULL
- [ ] Decode NULL → `missing`
- [ ] Support `Union{T, Missing}` types

### Tests ⏳
- [ ] Create `test/core/codec_test.jl`
- [ ] Test basic type codecs (Int, Float64, String, Bool)
- [ ] Test Date/DateTime codecs
- [ ] Test UUID codec
- [ ] Test NULL/Missing handling
- [ ] Test row mapping to NamedTuple
- [ ] Test row mapping to structs
- [ ] Test encode/decode round-trips
- [ ] Test error handling

### Future Enhancements ⏳
- [ ] JSON codec
- [ ] Array codec (PostgreSQL)
- [ ] Custom user-defined codecs
- [ ] Enum codecs

---

## Phase 6: End-to-End Integration ⏳ PENDING

### Query Execution API ⏳
- [ ] Implement `all(conn, query, params)` → `Vector{OutT}`
- [ ] Implement `one(conn, query, params)` → `OutT`
- [ ] Implement `maybeone(conn, query, params)` → `Union{OutT, Nothing}`
- [ ] Implement parameter binding from NamedTuple
- [ ] Integrate Query → Compile → Execute → Map pipeline

### Observability ⏳
- [ ] `sql(query)` → SQL string for inspection
- [ ] `explain(conn, query)` → EXPLAIN output
- [ ] Query logging hooks (optional)
- [ ] Performance metrics hooks (optional)

### Integration ⏳
- [ ] Wire Query AST → Dialect compilation
- [ ] Wire Driver execution
- [ ] Wire CodecRegistry decoding
- [ ] End-to-end type flow

### Tests ⏳
- [ ] Create `test/integration/end_to_end_test.jl`
- [ ] Test full SELECT query execution
- [ ] Test `all()` with various query types
- [ ] Test `one()` with exactly one row
- [ ] Test `one()` error on zero rows
- [ ] Test `one()` error on multiple rows
- [ ] Test `maybeone()` with zero rows
- [ ] Test `maybeone()` with one row
- [ ] Test complex queries (joins, aggregates)
- [ ] Test type conversion end-to-end
- [ ] Test parameter binding

### Future Enhancements ⏳
- [ ] INSERT / UPDATE / DELETE execution
- [ ] Batch operations
- [ ] Streaming results (large datasets)
- [ ] Result pagination

---

## Phase 7: Transactions ⏳ PENDING

### Transaction Interface ⏳
- [ ] Define `Transaction` abstract type
- [ ] `transaction(f, conn)` → commit on success, rollback on error
- [ ] Transaction handles compatible with query execution
- [ ] Nested transaction support (if DB supports)

### SQLite Transactions ⏳
- [ ] Implement SQLite transaction support
- [ ] BEGIN TRANSACTION
- [ ] COMMIT
- [ ] ROLLBACK
- [ ] Savepoint support (if needed)

### Tests ⏳
- [ ] Create `test/core/transaction_test.jl`
- [ ] Test successful commit
- [ ] Test rollback on exception
- [ ] Test query execution within transaction
- [ ] Test nested transactions (if supported)
- [ ] Test transaction isolation

### Future Enhancements ⏳
- [ ] Isolation level control
- [ ] Read-only transactions
- [ ] Deferred/immediate transactions (SQLite)

---

## Phase 8: Migration Runner ⏳ PENDING

### Migration Infrastructure ⏳
- [ ] Define migration file format (raw SQL)
- [ ] `schema_migrations` table schema
- [ ] `create_migrations_table(db)`
- [ ] `discover_migrations(migrations_dir)` → sorted list
- [ ] `apply_migration(db, migration)`
- [ ] Track applied migrations

### Migration API ⏳
- [ ] `apply_migrations(db, migrations_dir)`
- [ ] `list_migrations(db)` → applied migrations
- [ ] `migration_status(db, migrations_dir)` → pending vs applied
- [ ] Idempotent migration application

### Tests ⏳
- [ ] Create `test/core/migrations_test.jl`
- [ ] Test initial schema creation
- [ ] Test incremental migrations
- [ ] Test idempotency (re-running same migrations)
- [ ] Test migration ordering
- [ ] Test tracking in `schema_migrations`

### Future Enhancements ⏳
- [ ] Migration rollback
- [ ] Migration diffing
- [ ] DDL-based migrations (not just raw SQL)
- [ ] Online migrations

---

## Phase 9: PostgreSQL Dialect ⏳ PENDING

### PostgreSQL Dialect ⏳
- [ ] Implement `PostgreSQLDialect` struct
- [ ] Expression compilation
- [ ] Query compilation
- [ ] Identifier quoting (double quotes)
- [ ] Placeholder syntax (`$1`, `$2`, ...)
- [ ] Capability reporting
  - [ ] CTE support
  - [ ] RETURNING support
  - [ ] UPSERT support (ON CONFLICT)
  - [ ] LATERAL joins
  - [ ] Window functions
  - [ ] Arrays

### PostgreSQL Driver ⏳
- [ ] Implement `PostgreSQLDriver` struct
- [ ] Implement `PostgreSQLConnection` struct
- [ ] Add `LibPQ.jl` dependency (or similar)
- [ ] Connection management
- [ ] Query execution

### PostgreSQL Codecs ⏳
- [ ] UUID codec (native PostgreSQL type)
- [ ] JSONB codec
- [ ] Array codec
- [ ] Enum codec

### Tests ⏳
- [ ] Create `test/dialects/postgresql_test.jl`
- [ ] Create `test/drivers/postgresql_test.jl`
- [ ] Test SQL generation differences vs SQLite
- [ ] Test PostgreSQL-specific features
- [ ] Test compatibility

---

## Phase 10: Documentation ⏳ PENDING

### User Documentation ⏳
- [ ] Getting started guide (`docs/getting_started.md`)
- [ ] API reference (`docs/api.md`)
- [ ] Design rationale document (already exists: `design.md`)
- [ ] Tutorial: Building queries
- [ ] Tutorial: Type-safe queries
- [ ] Tutorial: Transactions
- [ ] Tutorial: Migrations

### Examples ⏳
- [ ] Create `examples/` directory
- [ ] Example: Basic CRUD application
- [ ] Example: Query composition
- [ ] Example: Transaction handling
- [ ] Example: Migration workflow
- [ ] Example: Multi-database support

### Developer Documentation ⏳
- [ ] Contributing guide
- [ ] Architecture overview
- [ ] Adding new dialects guide
- [ ] Adding new codecs guide

### Migration Guides ⏳
- [ ] Migration guide from raw SQL
- [ ] Migration guide from other query builders

---

## Optional Future Work (Post-v0.1)

### Additional Dialects ⏳
- [ ] MySQL Dialect
- [ ] MariaDB Dialect
- [ ] DuckDB Dialect

### Easy Layer ⏳
- [ ] Repository pattern
- [ ] CRUD helpers
- [ ] Relation preloading
- [ ] Association macros
- [ ] Validation integration
- [ ] Schema definition macros

### Query Features ⏳
- [ ] Subqueries as expressions
- [ ] CTEs (WITH clause)
- [ ] Window functions
- [ ] UNION / INTERSECT / EXCEPT
- [ ] Recursive CTEs

### DDL Support ⏳
- [ ] CREATE TABLE
- [ ] ALTER TABLE
- [ ] DROP TABLE
- [ ] CREATE INDEX
- [ ] DDL compilation via Dialect

### Performance ⏳
- [ ] Prepared statement caching
- [ ] Connection pooling
- [ ] Query plan caching
- [ ] Lazy query evaluation
- [ ] Streaming results

### Tooling ⏳
- [ ] Query formatter
- [ ] Query linter
- [ ] Performance analyzer
- [ ] Schema visualizer

---

## Project Infrastructure

### Build & CI ⏳
- [ ] Set up GitHub Actions CI
- [ ] Test on Julia 1.9+
- [ ] Test coverage reporting
- [ ] Benchmark suite

### Project Files ⏳
- [x] `Project.toml` (created, needs dependency updates)
- [x] `README.md` (created)
- [ ] `LICENSE` file
- [ ] `.gitignore`
- [ ] Code of Conduct
- [ ] Contributing guidelines

### Quality ⏳
- [ ] Set up formatter (JuliaFormatter.jl)
- [ ] Set up linter
- [ ] Establish code style guide
- [ ] Target >90% test coverage

---

## Current Status Summary

**Completed Phases:** 1/10
**Total Tasks Completed:** ~30/400+
**Current Phase:** Phase 2 (Query AST) ⏳

**Next Immediate Tasks:**
1. Begin Phase 2: Query AST implementation
2. Define Query{T} abstract type and core query nodes
3. Implement pipeline API (from, where, select, etc.)
4. Write comprehensive tests for query construction

**Blockers:** None

**Notes:**
- Phase 1 (Expression AST) completed successfully with 135 tests passing
- Ready to proceed with Phase 2
- Roadmap estimates 16-17 weeks for full Core layer implementation
