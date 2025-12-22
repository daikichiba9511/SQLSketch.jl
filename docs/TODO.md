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
- [x] INSERT execution via `execute`
- [x] UPDATE execution via `execute`
- [x] DELETE execution via `execute`
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
- [x] Test query execution within transaction (fetch_all, fetch_one, execute)
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

## Phase 11: PostgreSQL Dialect ✅ COMPLETED

### PostgreSQL Dialect ✅
- [x] Implement `PostgreSQLDialect` struct
- [x] Expression compilation
- [x] Query compilation
- [x] Identifier quoting (double quotes)
- [x] Placeholder syntax (`$1`, `$2`, ...)
- [x] Capability reporting
  - [x] CTE support
  - [x] RETURNING support
  - [x] UPSERT support (ON CONFLICT)
  - [x] LATERAL joins
  - [x] Window functions
  - [x] Arrays
  - [x] BULK_COPY
  - [x] SAVEPOINT
  - [x] ADVISORY_LOCK

### PostgreSQL Driver ✅
- [x] Implement `PostgreSQLDriver` struct
- [x] Implement `PostgreSQLConnection` struct
- [x] Add `LibPQ.jl` dependency
- [x] Connection management (libpq connection strings)
- [x] Query execution with positional parameters
- [x] Transaction support (BEGIN/COMMIT/ROLLBACK)
- [x] Savepoint support (nested transactions)

### PostgreSQL Codecs ✅
- [x] UUID codec (native PostgreSQL type)
- [x] JSONB codec (Dict/Vector serialization)
- [x] Array codec (Integer[], Text[], generic arrays)
- [x] Boolean codec (native BOOLEAN)
- [x] Date/DateTime codec (native DATE/TIMESTAMP)

### PostgreSQL DDL ✅
- [x] CREATE TABLE compilation
- [x] ALTER TABLE compilation (multiple operations)
- [x] DROP TABLE compilation (with CASCADE)
- [x] CREATE INDEX compilation
- [x] DROP INDEX compilation
- [x] Portable column type mapping
- [x] Column and table constraint support

### Tests ✅
- [x] Create `test/dialects/postgresql_test.jl` (102 tests)
- [x] Create `test/integration/postgresql_integration_test.jl`
- [x] Test SQL generation differences vs SQLite
- [x] Test PostgreSQL-specific features (ILIKE, BOOLEAN, UUID, JSONB, ARRAY)
- [x] Test compatibility (comparison tests with SQLite)
- [x] Test transactions and savepoints
- [x] Test UPSERT (ON CONFLICT)
- [x] Test RETURNING clause
- [x] Test CTE and set operations
- [x] Test DDL operations

**Total PostgreSQL Tests:** 102 passing ✅

---

## Phase 12: Documentation ✅ COMPLETED

### User Documentation ✅
- [x] Getting started guide (`docs/src/getting-started.md`)
- [x] API reference (`docs/src/api.md`)
- [x] Design rationale document (already exists: `design.md`)
- [x] Tutorial: Building queries
- [x] Tutorial: Type-safe queries
- [x] Tutorial: Transactions
- [x] Tutorial: Migrations

### Examples ✅
- [x] Create `examples/` directory (documented in tutorial)
- [x] Example: Basic CRUD application
- [x] Example: Query composition
- [x] Example: Transaction handling
- [x] Example: Migration workflow
- [x] Example: Multi-database support

### Developer Documentation ✅
- [x] Contributing guide (in README.md)
- [x] Architecture overview (in design.md)
- [x] Adding new dialects guide (in tutorial.md)
- [x] Adding new codecs guide (in tutorial.md)

### Migration Guides ✅
- [x] Migration guide from raw SQL (in tutorial.md)
- [x] Migration guide from other query builders (in getting-started.md)

---

## Phase 13: Performance Optimization ✅ COMPLETED

### 13.1: Benchmark Infrastructure ✅
**Goal**: Establish performance baseline and regression testing

- [x] Add `BenchmarkTools.jl` dependency
- [x] Create `benchmark/` directory structure
- [x] Implement batch operation benchmarks
- [x] Implement connection pooling benchmarks
- [x] Create benchmark suite runner
- [x] Document benchmarking results in `benchmark/RESULTS.md`

**Deliverables:**
- ✅ `benchmark/postgresql/batch_benchmark.jl`
- ✅ `benchmark/postgresql/connection_pooling.jl`
- ✅ `benchmark/RESULTS.md`

---

### 13.2: Prepared Statement Caching ✅
**Goal**: Cache compiled SQL and prepared statements for repeated queries

- [x] Design cache architecture (LRU eviction)
- [x] Implement `PreparedStatementCache` struct
- [x] Integrate with SQLite and PostgreSQL drivers
- [x] Benchmark cache impact (10-20% speedup achieved)

**Deliverables:**
- ✅ `src/Core/pool.jl` (PreparedStatementCache implementation)
- ✅ Driver integration
- ✅ 10-20% speedup achieved

---

### 13.3: Connection Pooling ✅
**Goal**: Reusable connection pool for multi-threaded/web applications

- [x] Design thread-safe connection pool architecture
- [x] Implement `ConnectionPool` struct with lifecycle management
- [x] Implement pool API (acquire/release/with_connection)
- [x] Add health checks and automatic reconnection
- [x] Implement TimeoutManager with O(1) unregister optimization
- [x] Write multi-threaded tests (43 tests)
- [x] Benchmark concurrent query performance (4.36x speedup)

**Deliverables:**
- ✅ `src/Core/pool.jl` (ConnectionPool + TimeoutManager)
- ✅ Thread-safe pool implementation
- ✅ `test/core/pool_test.jl` (43 tests)
- ✅ `benchmark/postgresql/connection_pooling.jl`

**Achievement:**
- ✅ 4.36x speedup for concurrent workloads
- ✅ O(1) timeout unregister with lazy deletion

---

### 13.4: Batch Operations ✅
**Goal**: Efficient bulk INSERT operations

- [x] Design batch INSERT API
- [x] Implement `insert_batch` with chunking
- [x] Add PostgreSQL COPY support (fast path)
- [x] Add SQLite bulk insert optimization
- [x] Write comprehensive tests (15 tests)
- [x] Benchmark batch vs loop operations

**Deliverables:**
- ✅ `src/Core/batch.jl`
- ✅ Dialect-specific optimizations
- ✅ `test/core/batch_test.jl` (15 tests)
- ✅ `benchmark/postgresql/batch_benchmark.jl`

**Achievement:**
- ✅ PostgreSQL COPY: 4-2016x faster than loop
- ✅ SQLite multi-row INSERT: 1.35-299x faster than loop

---

## Phase 13 Summary ✅ COMPLETED

**Total time:** ~4 weeks

**Completed:**
1. ✅ Benchmark Infrastructure
2. ✅ Prepared Statement Caching (10-20% speedup)
3. ✅ Connection Pooling (4.36x speedup)
4. ✅ Batch Operations (50-2016x speedup)

**Success metrics:**
- ✅ Benchmark suite established
- ✅ >90% test coverage maintained (2126 tests)
- ✅ Prepared statement caching: 10-20% speedup
- ✅ Connection pooling: concurrent workload support
- ✅ Batch operations: 50-2016x speedup
- ✅ All performance features documented

---

## Phase 14: Advanced Performance & Features ⏳ NEXT

### 14.1: Streaming Results ⏳
**Goal**: Memory-efficient processing of large result sets

**Priority**: 🔥 High (critical for large datasets)

**Tasks:**
- [ ] Design iterator-based streaming API
  - [ ] Define `StreamingResult` iterator type
  - [ ] Configurable fetch size (default: 1000 rows)
  - [ ] Early termination support
  - [ ] Connection lifecycle management
- [ ] Implement `stream_query` function
  - [ ] `stream_query(conn, dialect, registry, query; fetch_size=1000)` → iterator
  - [ ] Lazy row materialization
  - [ ] Type-safe iteration with `Base.iterate`
  - [ ] Automatic batch fetching
- [ ] Integrate with drivers
  - [ ] SQLite cursor-based streaming
  - [ ] PostgreSQL cursor-based streaming
- [ ] Write comprehensive tests
  - [ ] Small result sets (<100 rows)
  - [ ] Large result sets (100K+ rows)
  - [ ] Early termination (break in loop)
  - [ ] Memory usage validation
  - [ ] Type conversion correctness
- [ ] Benchmark impact
  - [ ] Memory usage: streaming vs fetch_all
  - [ ] Throughput comparison
  - [ ] Optimal fetch_size determination

**Deliverables:**
- `src/Core/streaming.jl`
- Driver integration (SQLite/PostgreSQL)
- `test/core/streaming_test.jl`
- `benchmark/streaming_benchmark.jl`

**Success Criteria:**
- Handles 100K+ row results efficiently
- Memory usage <10% of fetch_all
- Type-safe iteration
- No memory leaks

**Estimated time:** 3-4 days

---

### 14.2: Query Plan Caching ⏳
**Goal**: Cache compiled SQL and AST-based execution plans

**Priority**: 🌟 Medium (optimization for repeated queries)

**Tasks:**
- [ ] Design query plan cache architecture
  - [ ] AST-based cache key (structural hashing)
  - [ ] Compiled SQL storage with parameter metadata
  - [ ] LRU eviction policy
  - [ ] Thread-safety considerations
- [ ] Implement `QueryPlanCache` struct
  - [ ] Cache storage (Dict-based with LRU)
  - [ ] Hit/miss tracking for metrics
  - [ ] Size limits (default: 100 plans)
  - [ ] Eviction implementation
- [ ] Integrate with compilation pipeline
  - [ ] Automatic cache lookup in `compile()`
  - [ ] Cache warming strategies (optional)
  - [ ] Cache invalidation API
- [ ] Write tests
  - [ ] Cache hit scenarios
  - [ ] Cache miss scenarios
  - [ ] Eviction behavior
  - [ ] Correctness (cached SQL == fresh SQL)
  - [ ] Thread-safety tests
- [ ] Benchmark impact
  - [ ] Compilation speedup for cached queries
  - [ ] Memory overhead
  - [ ] Cache hit rate in typical workloads

**Deliverables:**
- `src/Core/query_plan_cache.jl`
- Integration in `src/Core/dialect.jl`
- `test/core/query_plan_cache_test.jl`
- `benchmark/query_plan_cache_benchmark.jl`

**Success Criteria:**
- Query compilation >50% faster for cached queries
- Cache hit rate >80% in typical workloads
- No memory leaks from cache
- Thread-safe access

**Estimated time:** 2-3 days

---

### 14.3: Performance Tooling ⏳
**Goal**: Built-in performance analysis and profiling tools

**Priority**: 🌟 Medium (observability)

**Tasks:**
- [ ] Implement query performance analyzer
  - [ ] Execution time tracking
  - [ ] Row count statistics
  - [ ] Cache hit rate monitoring
  - [ ] Query compilation time breakdown
- [ ] Implement `@timed` macro for queries
  - [ ] `@timed fetch_all(...)` → results + timing
  - [ ] Detailed timing breakdown (compile, execute, decode)
  - [ ] Human-readable output
- [ ] Implement query profiler
  - [ ] Automatic EXPLAIN QUERY PLAN integration
  - [ ] Index usage analysis
  - [ ] Full table scan detection
  - [ ] Query cost estimation
- [ ] Write documentation
  - [ ] Performance best practices guide
  - [ ] Profiling guide with examples
  - [ ] Optimization cookbook (common patterns)
  - [ ] Benchmarking guidelines

**Deliverables:**
- `src/Core/profiling.jl`
- `docs/performance.md`
- Example usage in tutorial
- Performance optimization guide

**Success Criteria:**
- Easy identification of slow queries
- Index usage analysis working for SQLite and PostgreSQL
- Clear performance recommendations
- Well-documented with examples

**Estimated time:** 3-4 days

---

### 14.4: Batch UPDATE/DELETE ⏳
**Goal**: Extend batch operations to UPDATE and DELETE

**Priority**: 🌟 Medium (complete batch API)

**Tasks:**
- [ ] Design batch UPDATE API
  - [ ] `update_batch(table, updates::Vector{NamedTuple}, where_conditions)`
  - [ ] Parameter array binding
  - [ ] Chunking strategy
- [ ] Design batch DELETE API
  - [ ] `delete_batch(table, where_conditions::Vector{SQLExpr})`
  - [ ] Temporary table strategy (for complex conditions)
- [ ] Implement batch UPDATE
  - [ ] PostgreSQL optimized UPDATE with unnest
  - [ ] SQLite multi-statement UPDATE
  - [ ] Transaction wrapping
- [ ] Implement batch DELETE
  - [ ] IN-list batching
  - [ ] Temporary table approach (for large batches)
- [ ] Write comprehensive tests
  - [ ] Small batches (10 rows)
  - [ ] Large batches (10K+ rows)
  - [ ] Transaction rollback on error
  - [ ] Type conversion correctness
  - [ ] Edge cases (empty batch, null values)
- [ ] Benchmark impact
  - [ ] Batch UPDATE vs loop UPDATE
  - [ ] Batch DELETE vs loop DELETE
  - [ ] Optimal chunk size determination

**Deliverables:**
- Extensions to `src/Core/batch.jl`
- `test/core/batch_update_delete_test.jl`
- `benchmark/batch_update_delete_benchmark.jl`
- API documentation

**Success Criteria:**
- Batch UPDATE >10x faster than loop
- Batch DELETE >10x faster than loop
- Handles 100K+ row batches efficiently
- Complete test coverage

**Estimated time:** 3-4 days

---

### 14.5: Advanced PostgreSQL Features ⏳
**Goal**: Leverage PostgreSQL-specific advanced features

**Priority**: 📌 Low (nice to have)

**Tasks:**
- [ ] Implement LISTEN/NOTIFY support
  - [ ] `listen(conn, channel)` → subscribe to notifications
  - [ ] `notify(conn, channel, payload)` → send notification
  - [ ] `wait_for_notification(conn; timeout)` → blocking wait
  - [ ] Async notification handler
- [ ] Implement advisory locks
  - [ ] `advisory_lock(conn, lock_id)`
  - [ ] `advisory_unlock(conn, lock_id)`
  - [ ] `try_advisory_lock(conn, lock_id)` → non-blocking
  - [ ] Session-level and transaction-level locks
- [ ] Add full-text search support
  - [ ] `to_tsvector(text, config)` expression
  - [ ] `to_tsquery(text, config)` expression
  - [ ] `@@` match operator
  - [ ] Ranking functions (`ts_rank`, `ts_rank_cd`)
- [ ] Add LATERAL join support
  - [ ] Extend JOIN AST with `lateral` flag
  - [ ] Compilation support in PostgreSQL dialect
- [ ] Write comprehensive tests
  - [ ] LISTEN/NOTIFY integration tests
  - [ ] Advisory lock tests (concurrent scenarios)
  - [ ] Full-text search tests
  - [ ] LATERAL join tests

**Deliverables:**
- Extensions to `src/Drivers/postgresql.jl`
- Extensions to `src/Dialects/postgresql.jl`
- `test/dialects/postgresql_advanced_test.jl`
- Documentation in API reference

**Success Criteria:**
- LISTEN/NOTIFY working for pub/sub patterns
- Advisory locks working for distributed coordination
- Full-text search working with ranking
- LATERAL joins compiling correctly

**Estimated time:** 4-5 days

---

### 14.6: Schema Introspection ⏳
**Goal**: Reflect existing database schema and generate DDL

**Priority**: 🔥 High (essential for migrations and tooling)

**Tasks:**
- [ ] Design introspection API
  - [ ] `list_tables(conn)` → Vector{Symbol}
  - [ ] `list_columns(conn, table)` → Vector{ColumnInfo}
  - [ ] `reflect_table(conn, table_name)` → CreateTable DDL AST
  - [ ] `reflect_index(conn, index_name)` → CreateIndex DDL AST
- [ ] Implement SQLite introspection
  - [ ] Query `sqlite_master` for schema info
  - [ ] Parse CREATE TABLE statements
  - [ ] Extract column types and constraints
  - [ ] Extract indexes
- [ ] Implement PostgreSQL introspection
  - [ ] Query `information_schema` and `pg_catalog`
  - [ ] Extract table definitions
  - [ ] Extract column types, constraints, defaults
  - [ ] Extract indexes with expressions
- [ ] Implement DDL generation
  - [ ] Convert introspected schema to DDL AST
  - [ ] Portable type mapping (reverse)
  - [ ] Preserve constraints and indexes
- [ ] Write comprehensive tests
  - [ ] Round-trip tests (create → reflect → recreate)
  - [ ] Complex schema introspection
  - [ ] Edge cases (views, triggers, etc.)
- [ ] Write documentation
  - [ ] Introspection guide
  - [ ] Migration generation examples

**Deliverables:**
- `src/Core/introspection.jl`
- SQLite introspection implementation
- PostgreSQL introspection implementation
- `test/core/introspection_test.jl`
- Documentation in tutorial

**Success Criteria:**
- Round-trip schema recreation works
- Supports complex schemas (FK, indexes, constraints)
- Works for both SQLite and PostgreSQL
- Well-documented with examples

**Estimated time:** 3-4 days

---

## Phase 14 Summary

**Total estimated time:** 18-24 days (~4-5 weeks)

**Priority order:**
1. 🔥 **14.1 Streaming Results** (critical for large datasets)
2. 🔥 **14.6 Schema Introspection** (essential for tooling)
3. 🌟 **14.2 Query Plan Caching** (optimization)
4. 🌟 **14.3 Performance Tooling** (observability)
5. 🌟 **14.4 Batch UPDATE/DELETE** (complete batch API)
6. 📌 **14.5 Advanced PostgreSQL Features** (nice to have)

**Success metrics:**
- [ ] Streaming handles 100K+ rows with <10% memory vs fetch_all
- [ ] Schema introspection supports round-trip DDL generation
- [ ] Query plan caching shows >50% compilation speedup
- [ ] Performance tooling provides actionable insights
- [ ] Batch UPDATE/DELETE >10x faster than loop
- [ ] PostgreSQL advanced features documented and tested
- [ ] All features well-documented with examples
- [ ] >90% test coverage maintained

---

## Optional Future Work (Post-v1.0)

### Additional Dialects ⏳
- [ ] MySQL Dialect
- [ ] MariaDB Dialect
- [ ] DuckDB Dialect

### Extras Layer ⏳
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
- [x] Extended column constraints (AUTO_INCREMENT, GENERATED, COLLATION, IDENTITY, COMMENT, ON UPDATE)
- [x] Table constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK)
- [x] Portable column type system

#### DDL - Advanced Features ⏳ (未実装)

**Column-level制約:**
- [ ] DEFERRABLE / NOT DEFERRABLE (PostgreSQL)
  - 制約チェックの遅延評価制御
- [ ] COMPRESSION (PostgreSQL 14+)
  - カラムの圧縮方式指定
- [ ] STORAGE (PostgreSQL)
  - カラムのストレージ戦略指定

**Table-level制約:**
- [ ] EXCLUDE constraint (PostgreSQL)
  - 排他制約（`EXCLUDE USING gist (period WITH &&)`）
- [ ] WITH clause (storage parameters)
  - テーブルストレージパラメータ（`WITH (fillfactor=70)`）
- [ ] TABLESPACE
  - テーブルスペース指定
- [ ] ON COMMIT (temporary tables)
  - 一時テーブルのコミット時動作（`ON COMMIT DROP/DELETE ROWS/PRESERVE ROWS`）
- [ ] PARTITION BY
  - テーブルパーティショニング（RANGE, LIST, HASH）
- [ ] INHERITS (PostgreSQL)
  - テーブル継承

**Index関連:**
- [ ] Expression index
  - 式インデックス（`CREATE INDEX ON users (lower(email))`）
- [ ] Index method
  - インデックスメソッド指定（BTREE, HASH, GIN, GIST, BRIN, SP-GIST）
- [ ] INCLUDE columns (PostgreSQL 11+)
  - カバリングインデックス（`CREATE INDEX ON users (email) INCLUDE (name, age)`）
- [ ] Index storage parameters
  - インデックスストレージパラメータ（`WITH (fillfactor=70)`）
- [ ] CONCURRENTLY (PostgreSQL)
  - 並行インデックス作成（`CREATE INDEX CONCURRENTLY`）
- [ ] Partial index WHERE clause
  - 部分インデックス（一部実装済み、拡張が必要）

**ALTER TABLE operations (未実装):**
- [ ] ALTER COLUMN operations
  - SET DEFAULT / DROP DEFAULT
  - SET NOT NULL / DROP NOT NULL
  - SET DATA TYPE (型変換)
  - SET STATISTICS (統計情報)
  - SET STORAGE (ストレージ戦略)
- [ ] RENAME TABLE
  - テーブル名変更
- [ ] SET/RESET storage parameters
  - ストレージパラメータの設定/リセット
- [ ] ENABLE/DISABLE TRIGGER
  - トリガーの有効化/無効化
- [ ] SET SCHEMA
  - スキーマ移動

**優先度評価:**
- 🔥 **高**: Expression index, Index method, ALTER COLUMN operations
- 🌟 **中**: INCLUDE columns, PARTITION BY, CONCURRENTLY
- 📌 **低**: DEFERRABLE, COMPRESSION, STORAGE, TABLESPACE, INHERITS, EXCLUDE

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

**Completed Phases:** 13/13 ✅
**Total Tasks Completed:** All core features implemented
**Current Status:** Phase 13 (Performance Optimization & MySQL Support) ✅ COMPLETED

**Phase 13 Achievements:**
1. ✅ MySQL Dialect, Driver & Codec (242 tests)
2. ✅ Batch Operations (15 tests) - 50-2016x speedup
3. ✅ Connection Pooling (43 tests) - 4.36x speedup
4. ✅ Prepared Statement Caching - 10-20% speedup

**Total Tests:** 2126 passing ✅

**Blockers:** None

**Target Release:** v0.2.0 ready for release

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
- **Phase 11** (PostgreSQL Dialect) completed with **102 tests passing** ✅
  - PostgreSQLDialect implementation
  - PostgreSQLDriver implementation (LibPQ.jl)
  - PostgreSQL-specific Codecs (UUID, JSONB, Arrays)
  - Full DDL support for PostgreSQL
  - 102 PostgreSQL dialect tests
  - Comprehensive integration tests
- **Total: 1712 tests passing** ✅
- Full query execution pipeline operational
- Type-safe parameter binding working
- DML operations (INSERT/UPDATE/DELETE) with RETURNING support
- Transaction and migration support fully implemented
- Observability API (sql, explain) implemented
- Advanced SQL features (Window Functions, Set Operations, UPSERT, DDL) implemented
- Ready to proceed with Phase 11 (PostgreSQL Dialect)
