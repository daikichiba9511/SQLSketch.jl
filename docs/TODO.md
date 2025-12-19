# SQLSketch.jl – Implementation TODO

Task breakdown based on `design.md` and `roadmap.md`.

**Legend:**
- ✅ Completed
- 🚧 In Progress
- ⏳ Pending
- 🔄 Blocked/Depends on other tasks

**Last Updated:** 2025-12-20

---

## Phase 1: Expression AST ✅ COMPLETED

### Core Types ✅
- [x] Define `SQLExpr` abstract type
- [x] Implement `ColRef` struct
- [x] Implement `Literal` struct
- [x] Implement `Param` struct
- [x] Implement `BinaryOp` struct
- [x] Implement `UnaryOp` struct
- [x] Implement `FuncCall` struct
- [x] Implement `BetweenOp` struct
- [x] Implement `InOp` struct
- [x] Implement `Cast` struct
- [x] Implement `Subquery` struct
- [x] Implement `CaseExpr` struct
- [x] Implement `PlaceholderField` struct

### Constructors ✅
- [x] `col(table, column)` helper
- [x] `literal(value)` helper
- [x] `param(T, name)` helper
- [x] `func(name, args)` helper
- [x] `between(expr, low, high)` helper
- [x] `not_between(expr, low, high)` helper
- [x] `in_list(expr, values)` helper
- [x] `not_in_list(expr, values)` helper
- [x] `cast(expr, target_type)` helper
- [x] `subquery(query)` helper
- [x] `case_expr(whens, else_result)` helper

### Operator Overloading ✅
- [x] Comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`)
- [x] Logical operators (`&`, `|`, `!`)
- [x] Arithmetic operators (`+`, `-`, `*`, `/`)
- [x] Auto-wrap literals in comparison operators
- [x] Auto-wrap literals in arithmetic operators
- [x] NULL checking helpers (`is_null`, `is_not_null`)
- [x] Pattern matching operators (`like`, `not_like`, `ilike`, `not_ilike`)

### Advanced Features ✅
- [x] `IN` operator support (`in_list`, `not_in_list`)
- [x] `BETWEEN` operator support (`between`, `not_between`)
- [x] `LIKE` / `ILIKE` operator support
- [x] Subquery expressions (`subquery`, `exists`, `not_exists`, `in_subquery`, `not_in_subquery`)
- [x] `CASE` expressions (`case_expr`)
- [x] Type casting expressions (`cast`)
- [x] Placeholder API (`p_` for column references)

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
- [x] LIKE/ILIKE operator tests
- [x] BETWEEN operator tests
- [x] IN operator tests
- [x] CAST expression tests
- [x] Subquery expression tests
- [x] CASE expression tests
- [x] Placeholder tests

**Total Expression Tests:** 268 passing ✅

---

## Phase 2: Query AST ✅ COMPLETED

### Core Query Types ✅
- [x] Define `Query{T}` abstract type
- [x] Implement `From{T}` struct
- [x] Implement `Where{T}` struct (shape-preserving)
- [x] Implement `Join{T}` struct (shape-preserving)
- [x] Implement `Select{OutT}` struct (shape-changing)
- [x] Implement `OrderBy{T}` struct (shape-preserving)
- [x] Implement `Limit{T}` struct (shape-preserving)
- [x] Implement `Offset{T}` struct (shape-preserving)
- [x] Implement `Distinct{T}` struct (shape-preserving)
- [x] Implement `GroupBy{T}` struct
- [x] Implement `Having{T}` struct

### Pipeline API ✅
- [x] `from(table::Symbol)` → `From{NamedTuple}`
- [x] `where(q::Query, expr::Expr)` → `Where{T}`
- [x] `join(q::Query, table, on)` → `Join{T}`
- [x] `select(q::Query, OutT::Type, fields...)` → `Select{OutT}`
- [x] `order_by(q::Query, field::Expr; desc=false)` → `OrderBy{T}`
- [x] `limit(q::Query, n::Int)` → `Limit{T}`
- [x] `offset(q::Query, n::Int)` → `Offset{T}`
- [x] `distinct(q::Query)` → `Distinct{T}`
- [x] `group_by(q::Query, fields...)` → `GroupBy{T}`
- [x] `having(q::Query, expr::Expr)` → `Having{T}`

### Query Composition ✅
- [x] Implement pipeline chaining with `|>`
- [x] Type-safe query transformations
- [x] Shape-preserving vs shape-changing semantics

### Tests ✅
- [x] Create `test/core/query_test.jl`
- [x] Test `from()` construction
- [x] Test `where()` chaining
- [x] Test `select()` type changes
- [x] Test `join()` operations
- [x] Test `order_by()` operations
- [x] Test `limit()` and `offset()`
- [x] Test complex query pipelines
- [x] Test type safety and inference

### DML Operations ✅
- [x] `INSERT INTO` statement (`insert_into`, `values`)
- [x] `UPDATE` statement (`update`, `set`)
- [x] `DELETE FROM` statement (`delete_from`)
- [x] WHERE clause support for DML

### CTE Support ✅
- [x] CTE (Common Table Expressions) support (WITH clause)
  - [x] `CTE` struct for defining CTEs
  - [x] `With{T}` query node
  - [x] `cte(name, query)` helper with optional column aliases
  - [x] `with(ctes, main_query)` helper (single and multiple CTEs)
  - [x] SQL compilation for CTEs
  - [x] End-to-end execution tests
  - [x] Nested CTE references support

### Future Enhancements ⏳
- [ ] UNION / INTERSECT / EXCEPT
- [ ] Window functions (OVER clause)
- [ ] UPSERT (ON CONFLICT) support

---

## Phase 3: Dialect Abstraction ✅ COMPLETED

### Dialect Interface ✅
- [x] Define `Dialect` abstract type
- [x] Define `Capability` enum
- [x] `compile(dialect, query)` → `(sql, params)` interface
- [x] `compile_expr(dialect, expr)` → SQL fragment interface
- [x] `quote_identifier(dialect, name)` → quoted identifier
- [x] `placeholder(dialect, idx)` → parameter placeholder
- [x] `supports(dialect, capability)` → Bool

### SQLite Dialect ✅
- [x] Implement `SQLiteDialect` struct
- [x] Implement expression compilation
  - [x] Compile `ColRef`
  - [x] Compile `Literal`
  - [x] Compile `Param`
  - [x] Compile `BinaryOp`
  - [x] Compile `UnaryOp`
  - [x] Compile `FuncCall`
  - [x] Compile `BetweenOp`
  - [x] Compile `InOp`
  - [x] Compile `Cast`
  - [x] Compile `Subquery`
  - [x] Compile `CaseExpr`
  - [x] Compile `PlaceholderField` (with resolution)
- [x] Implement query compilation
  - [x] Compile `From`
  - [x] Compile `Where`
  - [x] Compile `Select`
  - [x] Compile `Join`
  - [x] Compile `OrderBy`
  - [x] Compile `Limit` / `Offset`
  - [x] Compile `GroupBy` / `Having`
  - [x] Compile `Distinct`
  - [x] Compile `InsertInto` / `InsertValues`
  - [x] Compile `Update` / `UpdateSet` / `UpdateWhere`
  - [x] Compile `DeleteFrom` / `DeleteWhere`
- [x] Identifier quoting (backticks)
- [x] Placeholder syntax (`?`)
- [x] Placeholder field resolution (`p_` support)
- [x] Capability reporting
  - [x] CTE support
  - [x] RETURNING support (SQLite 3.35+)
  - [x] UPSERT support
  - [x] Window functions

### Tests ✅
- [x] Create `test/dialects/sqlite_test.jl`
- [x] Test expression compilation
- [x] Test query compilation (all query types)
- [x] Test identifier quoting edge cases
- [x] Test parameter ordering
- [x] Test capability reporting
- [x] Test SQL string generation (no DB required)

### Future Enhancements ⏳
- [ ] DDL compilation (CREATE TABLE, ALTER TABLE, etc.)
- [ ] UPSERT (ON CONFLICT) compilation
- [ ] CTE (WITH clause) compilation

---

## Phase 4: Driver Abstraction ✅ COMPLETED

### Driver Interface ✅
- [x] Define `Driver` abstract type
- [x] Define `Connection` abstract type
- [x] `connect(driver, config)` → Connection interface
- [x] `execute(conn, sql, params)` → raw result interface
- [x] `close(conn)` interface
- [x] Error normalization strategy

### SQLite Driver ✅
- [x] Implement `SQLiteDriver` struct
- [x] Implement `SQLiteConnection` struct
- [x] Add `SQLite.jl` dependency to Project.toml
- [x] Add `DBInterface.jl` dependency to Project.toml
- [x] Implement connection management
  - [x] Connect to file database
  - [x] Connect to in-memory database (`:memory:`)
  - [ ] Connection pooling (future)
- [x] Implement query execution
  - [x] Execute SQL with positional parameters
  - [x] Return raw `SQLite.Query` results
- [x] Implement connection cleanup
  - [x] Close connection
  - [x] Release resources
- [x] Error handling and normalization

### Tests ✅
- [x] Create `test/drivers/sqlite_test.jl`
- [x] Test in-memory database connection
- [x] Test file database connection
- [x] Test query execution
- [x] Test parameter binding
- [x] Test connection cleanup
- [x] Test error handling

### Future Enhancements ⏳
- [ ] Prepared statement caching
- [ ] Query cancellation
- [ ] Timeout support
- [ ] Connection pooling

---

## Phase 5: CodecRegistry ✅ COMPLETED

### Codec Interface ✅
- [x] Define `Codec` abstract type
- [x] Define `CodecRegistry` struct
- [x] `encode(codec, value)` → database value
- [x] `decode(codec, dbvalue)` → Julia value
- [x] `register!(registry, T, codec)`
- [x] `get_codec(registry, T)` → Codec

### Default Codecs ✅
- [x] Implement `IntCodec`
- [x] Implement `Float64Codec`
- [x] Implement `StringCodec`
- [x] Implement `BoolCodec`
- [x] Implement `DateCodec`
- [x] Implement `DateTimeCodec`
- [x] Implement `UUIDCodec` (as TEXT for SQLite)
- [x] Implement `MissingCodec` (NULL policy)
- [x] Add `Dates` dependency to Project.toml
- [x] Add `UUIDs` dependency to Project.toml

### Row Mapping ✅
- [x] `map_row(registry, ::Type{NamedTuple}, row)` → NamedTuple
- [x] `map_row(registry, ::Type{T}, row)` → T (struct construction)
- [x] Column name normalization
- [x] Missing field handling
- [x] Type conversion error handling

### NULL Handling ✅
- [x] Define global NULL policy (Missing-based)
- [x] Encode `missing` → NULL
- [x] Decode NULL → `missing`
- [x] Support `Union{T, Missing}` types

### Tests ✅
- [x] Create `test/core/codec_test.jl`
- [x] Test basic type codecs (Int, Float64, String, Bool)
- [x] Test Date/DateTime codecs
- [x] Test UUID codec
- [x] Test NULL/Missing handling
- [x] Test row mapping to NamedTuple
- [x] Test row mapping to structs
- [x] Test encode/decode round-trips
- [x] Test error handling

### Future Enhancements ⏳
- [ ] JSON codec
- [ ] Array codec (PostgreSQL)
- [ ] Custom user-defined codecs
- [ ] Enum codecs

---

## Phase 6: End-to-End Integration ✅ COMPLETED

### Query Execution API ✅
- [x] Implement `fetch_all(conn, dialect, registry, query, params)` → `Vector{OutT}`
- [x] Implement `fetch_one(conn, dialect, registry, query, params)` → `OutT`
- [x] Implement `fetch_maybe(conn, dialect, registry, query, params)` → `Union{OutT, Nothing}`
- [x] Implement parameter binding from NamedTuple
- [x] Integrate Query → Compile → Execute → Map pipeline

### Observability ✅
- [x] `sql(query)` → SQL string for inspection
- [x] `explain(conn, query)` → EXPLAIN output
- [ ] Query logging hooks (optional) - Future
- [ ] Performance metrics hooks (optional) - Future

### Integration ✅
- [x] Wire Query AST → Dialect compilation
- [x] Wire Driver execution
- [x] Wire CodecRegistry decoding
- [x] End-to-end type flow

### Tests ✅
- [x] Create `test/integration/end_to_end_test.jl`
- [x] Test full SELECT query execution
- [x] Test `fetch_all()` with various query types
- [x] Test `fetch_one()` with exactly one row
- [x] Test `fetch_one()` error on zero rows
- [x] Test `fetch_one()` error on multiple rows
- [x] Test `fetch_maybe()` with zero rows
- [x] Test `fetch_maybe()` with one row
- [x] Test complex queries (joins, aggregates)
- [x] Test type conversion end-to-end
- [x] Test parameter binding

### DML Execution ✅
- [x] INSERT execution via `execute_dml`
- [x] UPDATE execution via `execute_dml`
- [x] DELETE execution via `execute_dml`

### Future Enhancements ⏳
- [ ] Batch INSERT operations
- [ ] Streaming results (large datasets)
- [ ] Result pagination
- [ ] RETURNING clause support

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

**Completed Phases:** 6/10
**Total Tasks Completed:** ~290/400+
**Current Phase:** Phase 7 (Transactions) ⏳

**Next Immediate Tasks:**
1. Begin Phase 7: Transaction Management
2. Implement transaction API (transaction, commit, rollback)
3. Wire transaction support into query execution
4. Write comprehensive transaction tests

**Blockers:** None

**Notes:**
- Phase 1 (Expression AST) completed successfully with **268 tests passing** ✅
  - All major SQL expression types implemented (CAST, Subquery, CASE)
  - Placeholder API (`p_`) fully functional
  - Pattern matching (LIKE/ILIKE), BETWEEN, IN operators
- Phase 2 (Query AST) completed successfully with **85 tests passing** ✅
  - Full DML support (INSERT, UPDATE, DELETE)
  - Curried pipeline API for natural SQL composition
- Phase 3 (Dialect Abstraction) completed successfully with **102 tests passing** ✅
  - Complete SQLite dialect implementation
  - All expression types compile correctly to SQL
- Phase 4 (Driver Abstraction) completed successfully with **41 tests passing** ✅
- Phase 5 (CodecRegistry) completed successfully with **112 tests passing** ✅
- Phase 6 (End-to-End Integration) completed successfully with **54 integration tests passing** ✅
- **Total: 662+ tests passing** ✅
- Full query execution pipeline operational
- Type-safe parameter binding working
- DML operations (INSERT/UPDATE/DELETE) working
- Observability API (sql, explain) implemented
- Ready to proceed with Phase 7 (Transactions)
