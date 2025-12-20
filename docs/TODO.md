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
- [x] `INSERT INTO` statement (`insert_into`, `insert_values`)
- [x] `UPDATE` statement (`update`, `set`)
- [x] `DELETE FROM` statement (`delete_from`)
- [x] WHERE clause support for DML
- [x] `RETURNING` clause support for DML (SQLite 3.35+)

### CTE Support ✅
- [x] CTE (Common Table Expressions) support (WITH clause)
  - [x] `CTE` struct for defining CTEs
  - [x] `With{T}` query node
  - [x] `cte(name, query)` helper with optional column aliases
  - [x] `with(ctes, main_query)` helper (single and multiple CTEs)
  - [x] SQL compilation for CTEs
  - [x] End-to-end execution tests
  - [x] Nested CTE references support

### Advanced Features ✅
- [x] Window functions (OVER clause) - **Phase 8.5** (79 tests)
- [x] Set Operations (UNION / INTERSECT / EXCEPT) - **Phase 8.6** (102 tests)
- [x] UPSERT (ON CONFLICT) support - **Phase 8.7** (86 tests)

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

### Advanced Features ✅
- [x] CTE (WITH clause) compilation
- [x] UPSERT (ON CONFLICT) compilation - **Phase 8.7**
- [x] Window functions compilation - **Phase 8.5**
- [x] Set operations compilation - **Phase 8.6**

### DDL Support ✅ **Phase 10**
- [x] DDL compilation (CREATE TABLE, ALTER TABLE, DROP TABLE, CREATE/DROP INDEX)

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
- [x] RETURNING clause support (fetch results from DML)

### Future Enhancements ⏳
- [ ] Batch INSERT operations
- [ ] Streaming results (large datasets)
- [ ] Result pagination

---

## Phase 7: Transactions ✅ COMPLETED

### Transaction Interface ✅
- [x] Define `TransactionHandle` abstract type
- [x] `transaction(f, conn)` → commit on success, rollback on error
- [x] Transaction handles compatible with query execution
- [x] Nested transaction support using savepoints

### SQLite Transactions ✅
- [x] Implement SQLite transaction support
- [x] BEGIN TRANSACTION
- [x] COMMIT
- [x] ROLLBACK
- [x] Savepoint support (SAVEPOINT/RELEASE/ROLLBACK TO)

### Tests ✅
- [x] Create `test/core/transaction_test.jl`
- [x] Test successful commit
- [x] Test rollback on exception
- [x] Test query execution within transaction (fetch_all, fetch_one, execute_dml)
- [x] Test nested transactions (savepoints)
- [x] Test transaction isolation
- [x] Test error handling

**Total Transaction Tests:** 26 passing ✅

### Future Enhancements ⏳
- [ ] Isolation level control
- [ ] Read-only transactions
- [ ] Deferred/immediate transactions (SQLite)

---

## Phase 8: Migration Runner ✅ COMPLETED

### Migration Infrastructure ✅
- [x] Define migration file format (raw SQL with UP/DOWN sections)
- [x] `schema_migrations` table schema
- [x] `create_migrations_table(db)`
- [x] `discover_migrations(migrations_dir)` → sorted list
- [x] `apply_migration(db, migration)`
- [x] Track applied migrations with SHA256 checksums

### Migration API ✅
- [x] `apply_migrations(db, migrations_dir)`
- [x] `generate_migration(dir, name)` → create new migration file
- [x] `migration_status(db, migrations_dir)` → pending vs applied
- [x] `validate_migration_checksums(db, migrations_dir)` → detect modifications
- [x] Idempotent migration application

### Tests ✅
- [x] Create `test/core/migrations_test.jl`
- [x] Test initial schema creation
- [x] Test incremental migrations
- [x] Test idempotency (re-running same migrations)
- [x] Test migration ordering
- [x] Test tracking in `schema_migrations`
- [x] Test checksum validation
- [x] Test transaction-wrapped execution

**Total Migration Tests:** 79 passing ✅

### Future Enhancements ⏳
- [ ] Migration rollback (DOWN section execution)
- [ ] Migration diffing
- [ ] DDL-based migrations (not just raw SQL)
- [ ] Online migrations

**Note:** DOWN section format is supported, but automatic rollback execution is not yet implemented.

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

### Query Features
- [x] Subqueries as expressions ✅
- [x] CTEs (WITH clause) ✅
- [x] Window functions ✅ **Phase 8.5** (79 tests)
- [x] UNION / INTERSECT / EXCEPT ✅ **Phase 8.6** (102 tests)
- [x] UPSERT (ON CONFLICT) ✅ **Phase 8.7** (86 tests)
- [ ] Recursive CTEs ⏳

### DDL Support ✅ **Phase 10** (227 tests)
- [x] CREATE TABLE
- [x] ALTER TABLE
- [x] DROP TABLE
- [x] CREATE INDEX / DROP INDEX
- [x] DDL compilation via Dialect
- [x] Column constraints (PRIMARY KEY, NOT NULL, UNIQUE, DEFAULT, CHECK, FOREIGN KEY)
- [x] Table constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK)
- [x] Portable column type system

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

## Phase 10: DDL Support ✅ COMPLETED

### DDL AST ✅
- [x] Define DDL abstract type hierarchy
- [x] Implement `CreateTable` struct
- [x] Implement `AlterTable` struct
- [x] Implement `DropTable` struct
- [x] Implement `CreateIndex` struct
- [x] Implement `DropIndex` struct
- [x] Implement column constraint types
- [x] Implement table constraint types
- [x] Portable column type system

### Pipeline API ✅
- [x] `create_table(table; options...)` → CreateTable
- [x] `add_column(table, name, type; constraints...)` with currying
- [x] `add_primary_key(columns)` with currying
- [x] `add_foreign_key(columns, ref_table, ref_columns)` with currying
- [x] `add_unique(columns)` with currying
- [x] `add_check(condition)` with currying
- [x] `alter_table(table)` → AlterTable
- [x] `add_alter_column`, `drop_alter_column`, `rename_alter_column` with currying
- [x] `drop_table(table; options...)` → DropTable
- [x] `create_index(name, table, columns; options...)` → CreateIndex
- [x] `drop_index(name; options...)` → DropIndex

### SQLite DDL Compilation ✅
- [x] Compile `CreateTable` to SQL
- [x] Compile `AlterTable` to SQL (limited support)
- [x] Compile `DropTable` to SQL
- [x] Compile `CreateIndex` to SQL
- [x] Compile `DropIndex` to SQL
- [x] Map portable column types to SQLite types
- [x] Compile column constraints
- [x] Compile table constraints

### Tests ✅
- [x] Create `test/core/ddl_test.jl` (156 tests)
- [x] Test all DDL statement construction
- [x] Test pipeline API and currying
- [x] Test column and table constraints
- [x] Test immutability
- [x] Add DDL tests to `test/dialects/sqlite_test.jl` (71 tests)
- [x] Test DDL compilation to SQL
- [x] Test type mapping
- [x] Test complex schema examples

**Total DDL Tests:** 227 passing ✅

---

## Current Status Summary

**Completed Phases:** 9/11
**Total Tasks Completed:** ~400/420+
**Current Phase:** Phase 11 (PostgreSQL Dialect) ⏳

**Next Immediate Tasks:**
1. Begin Phase 11: PostgreSQL Dialect
2. Implement PostgreSQLDialect (SQL generation)
3. Implement PostgreSQLDriver (connection and execution)
4. Implement PostgreSQL-specific codecs (UUID, JSONB, Arrays)
5. Write compatibility tests

**Blockers:** None

**Notes:**
- Phase 1 (Expression AST) completed successfully with **268 tests passing** ✅
  - All major SQL expression types implemented (CAST, Subquery, CASE)
  - Placeholder API (`p_`) fully functional
  - Pattern matching (LIKE/ILIKE), BETWEEN, IN operators
- Phase 2 (Query AST) completed successfully with **232 tests passing** ✅
  - Full DML support (INSERT, UPDATE, DELETE)
  - CTE (Common Table Expressions) support
  - RETURNING clause support
  - Curried pipeline API for natural SQL composition
- Phase 3 (Dialect Abstraction) completed successfully with **331 tests passing** ✅
  - Complete SQLite dialect implementation
  - All expression types compile correctly to SQL
  - DML, CTE, and DDL compilation
- Phase 4 (Driver Abstraction) completed successfully with **41 tests passing** ✅
- Phase 5 (CodecRegistry) completed successfully with **115 tests passing** ✅
- Phase 6 (End-to-End Integration) completed successfully with **95 integration tests passing** ✅
- Phase 7 (Transactions) completed successfully with **26 tests passing** ✅
  - Transaction API with automatic commit/rollback
  - Savepoint support for nested transactions
- Phase 8 (Migrations) completed successfully with **79 tests passing** ✅
  - Migration discovery and application
  - SHA256 checksum validation
  - Transaction-wrapped execution
- **Phase 8.5** (Window Functions) completed with **79 tests passing** ✅
  - Window function AST (WindowFrame, Over, WindowFunc)
  - Ranking functions (row_number, rank, dense_rank, ntile)
  - Value functions (lag, lead, first_value, last_value, nth_value)
  - Aggregate window functions (sum, avg, min, max, count)
  - Frame specification (ROWS/RANGE/GROUPS BETWEEN)
- **Phase 8.6** (Set Operations) completed with **102 tests passing** ✅
  - Set operation AST (SetUnion, SetIntersect, SetExcept)
  - UNION / UNION ALL support
  - INTERSECT support
  - EXCEPT support
  - Pipeline API with currying
- **Phase 8.7** (UPSERT) completed with **86 tests passing** ✅
  - OnConflict AST type
  - ON CONFLICT DO NOTHING support
  - ON CONFLICT DO UPDATE support
  - Conflict target column specification
  - WHERE clause for conditional updates
  - Pipeline API with currying
- **Phase 10** (DDL Support) completed with **227 tests passing** ✅
  - DDL AST (CreateTable, AlterTable, DropTable, CreateIndex, DropIndex)
  - Column and table constraints
  - Portable column type system
  - Full SQLite DDL compilation
  - Pipeline API with currying
- **Total: 1610 tests passing** ✅
- Full query execution pipeline operational
- Type-safe parameter binding working
- DML operations (INSERT/UPDATE/DELETE) with RETURNING support
- Transaction and migration support fully implemented
- Observability API (sql, explain) implemented
- Advanced SQL features (Window Functions, Set Operations, UPSERT, DDL) implemented
- Ready to proceed with Phase 11 (PostgreSQL Dialect)
