# Integration Tests

This directory contains integration tests that verify end-to-end functionality of SQLSketch.jl components.

## Test Files

### `compare_queries_test.jl`

Compares SQLSketch.jl generated SQL with reference SQL to ensure correctness.

**What it tests:**
- Query AST → SQL compilation
- SQL execution via Driver
- Result decoding via CodecRegistry
- 7 different query patterns:
  - Simple SELECT
  - WHERE clause
  - LIMIT
  - OFFSET
  - ORDER BY DESC
  - DISTINCT
  - Multiple WHERE conditions

**Prerequisites:**
```bash
# Create test database first
julia --project=. examples/create_test_db.jl
```

**Run:**
```bash
julia --project=. test/integration/compare_queries_test.jl
```

**Expected output:**
```
Total tests:  7
Passed:       7 ✅
Failed:       0
```

## Notes

- Integration tests require `examples/test.db` to exist
- These tests verify that SQLSketch.jl produces identical results to native SQLite
- Tests use the full stack: Query AST → Dialect → Driver → CodecRegistry
