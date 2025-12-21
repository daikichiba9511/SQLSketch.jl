# Changelog

All notable changes to SQLSketch.jl will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-12-21

### Added

**Database Support:**
- SQLite support (in-memory and file-based)
- PostgreSQL support with LibPQ.jl
- MySQL/MariaDB support

**Core Features:**
- Expression AST for type-safe SQL expression building
- Query AST with pipeline API (`from |> where |> select`)
- DDL support (CREATE TABLE, ALTER TABLE, DROP TABLE, CREATE/DROP INDEX)
- Transaction management with savepoints
- Migration runner with checksum validation
- Window functions (OVER, PARTITION BY, ORDER BY, frame specs)
- Set operations (UNION, INTERSECT, EXCEPT)
- UPSERT (ON CONFLICT DO NOTHING/UPDATE)
- CTE (Common Table Expressions)
- DML with RETURNING clause support

**Performance Optimizations:**
- Query Plan Cache: **4.85-6.95x** speedup for repeated compilations
- Prepared Statement Cache: 10-20% speedup for repeated queries
- Connection Pooling: 4-5x speedup for concurrent workloads
- Batch INSERT operations:
  - PostgreSQL COPY: up to 2016x speedup
  - Multi-row INSERT: up to 299x speedup

**Performance Tooling:**
- `@timed_query` macro for query profiling
- `analyze_query()` for EXPLAIN plan analysis
- Index usage detection
- Full table scan warnings
- Performance best practices guide

**Metadata API:**
- `list_tables()` - List all tables in database
- `describe_table()` - Get table schema information
- `list_schemas()` - List database schemas (PostgreSQL)

**Documentation:**
- Complete API reference
- Comprehensive tutorial
- Performance optimization guide
- Getting started guide
- Benchmark results

### Performance

**Verified Benchmarks:**
- Query Plan Cache: 4.85x - 6.95x speedup (verified)
- Connection Pooling: 4-5x speedup (concurrent workloads)
- Batch INSERT (PostgreSQL COPY): 4x - 2016x speedup
- Batch INSERT (Multi-row): 1.35x - 299x speedup
- Prepared Statement Cache: 10-20% speedup

### Testing

- **2215 passing tests** across all features
- Unit tests for all core components
- Integration tests for SQLite and PostgreSQL
- Compatibility tests for MySQL
- Benchmark validation tests

### Technical Details

**Implemented Phases:**
- Phase 1: Expression AST (268 tests)
- Phase 2: Query AST (232 tests)
- Phase 3: Dialect Abstraction (356 tests - SQLite)
- Phase 4: Driver Abstraction (41 tests)
- Phase 5: CodecRegistry (115 tests)
- Phase 6: End-to-End Integration (95 tests)
- Phase 7: Transaction Management (26 tests)
- Phase 8: Migration Runner (79 tests)
- Phase 8.5: Window Functions (79 tests)
- Phase 8.6: Set Operations (102 tests)
- Phase 8.7: UPSERT (86 tests)
- Phase 10: DDL Support (241 tests)
- Phase 11: PostgreSQL Dialect (155 tests + integration)
- Phase 12: Documentation (complete)
- Phase 13: Performance Optimization
  - 13.1: Benchmark Infrastructure ✅
  - 13.2: Prepared Statement Caching ✅
  - 13.3: Connection Pooling (43 tests)
  - 13.4: Batch Operations (15 tests)
  - 13.5: Query Plan Cache (46 tests)
  - 13.6: Performance Tooling (43 tests)

**MySQL Support:**
- MySQL Dialect (161 tests)
- MySQL Driver with connection pooling
- MySQL Codecs (Date, DateTime, UUID, JSON, Boolean)
- MySQL batch operations with LOAD DATA LOCAL INFILE

### Known Limitations

- Streaming results for large datasets: not yet implemented (future)
- Recursive CTEs: not yet implemented (future)
- Easy Layer (Repository pattern, CRUD helpers): planned for future releases

### Breaking Changes

None (initial release)

---

## [0.3.0] - TBD

### Changed - BREAKING

**API Naming Changes to Avoid Base Module Conflicts**

To prevent naming conflicts with Julia's `Base` module and improve API clarity, the following functions have been renamed:

#### Join Operations
- `join(table, on; kind=:inner)` → `inner_join(table, on)`
- `join(table, on; kind=:left)` → `left_join(table, on)`
- `join(table, on; kind=:right)` → `right_join(table, on)`
- `join(table, on; kind=:full)` → `full_join(table, on)`
- `innerjoin` → `inner_join` (snake_case for consistency)
- `leftjoin` → `left_join`
- `rightjoin` → `right_join`
- `fulljoin` → `full_join`

#### INSERT Operations
- `values(...)` → `insert_values(...)`

#### UPDATE Operations
- `set(...)` → `set_values(...)`

#### Set Operations
- `union(q1, q2; all=true)` → `union_all(q1, q2)`
- `union(q1, q2; all=false)` or `union(q1, q2)` → `union_distinct(q1, q2)`
- `intersect(q1, q2)` → `intersect_query(q1, q2)`
- `except(q1, q2)` → `except_query(q1, q2)`

### Migration Guide

**Before (v0.2.x):**
```julia
q = from(:users) |>
    join(:orders, col(:users, :id) == col(:orders, :user_id); kind=:left) |>
    where(col(:users, :active) == true) |>
    select(NamedTuple, col(:users, :name))

insert_q = insert_into(:users, [:name, :email]) |>
           values([[literal("Alice"), literal("alice@example.com")]])

update_q = update(:users) |>
           set(:active => literal(false)) |>
           where(col(:users, :id) == param(Int, :id))

union_q = q1 |> union(q2; all=true)
```

**After (v0.3.0):**
```julia
q = from(:users) |>
    left_join(:orders, col(:users, :id) == col(:orders, :user_id)) |>
    where(col(:users, :active) == true) |>
    select(NamedTuple, col(:users, :name))

insert_q = insert_into(:users, [:name, :email]) |>
           insert_values([[literal("Alice"), literal("alice@example.com")]])

update_q = update(:users) |>
           set_values(:active => literal(false)) |>
           where(col(:users, :id) == param(Int, :id))

union_q = q1 |> union_all(q2)
```

### Rationale

These changes eliminate conflicts with Julia's `Base` module functions (`Base.join`, `Base.values`, `Base.union`, `Base.intersect`) and adopt consistent snake_case naming across the entire API per the project's coding conventions.

---

## [Unreleased]

### Planned Features

- Streaming results API for memory-efficient large dataset processing
- Recursive CTEs (WITH RECURSIVE)
- Easy Layer: Repository pattern, CRUD helpers, Active Record-style API
- MariaDB-specific optimizations
- Additional database backends (DuckDB, etc.)

---

[0.3.0]: https://github.com/daikichiba9511/SQLSketch.jl/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/daikichiba9511/SQLSketch.jl/releases/tag/v0.2.0
