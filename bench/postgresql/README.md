# PostgreSQL Benchmarks

This directory contains benchmarks for SQLSketch.jl with PostgreSQL.

## Prerequisites

### 1. Install PostgreSQL

**Option A: Docker Compose (Recommended for Testing)**

Use the provided docker-compose configuration in `test/integration/`:

```bash
# Start PostgreSQL container
cd test/integration
docker compose up -d postgres

# Check container status
docker ps | grep postgres

# Stop container when done
docker compose down
```

This uses:
- Port: 5433 (to avoid conflicts with local PostgreSQL on 5432)
- Database: sqlsketch_test
- User: test_user
- Password: test_password

Set environment variable for benchmarks:

```bash
export SQLSKETCH_PG_CONN="host=localhost port=5433 dbname=sqlsketch_test user=test_user password=test_password"
```

**Option B: Docker Manual**

```bash
# Start PostgreSQL container
docker run --name sqlsketch-pg \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=sqlsketch_bench \
  -p 5432:5432 \
  -d postgres:15

# Stop container when done
docker stop sqlsketch-pg

# Remove container
docker rm sqlsketch-pg
```

**Option C: Local Installation**

Install PostgreSQL 12+ and create a database:

```sql
CREATE DATABASE sqlsketch_bench;
```

### 2. Configure Connection

**⚠️ Security Note:** Default credentials are for local development/testing only.

Set environment variable to customize:

```bash
# For docker-compose setup (test/integration)
export SQLSKETCH_PG_CONN="host=localhost port=5433 dbname=sqlsketch_test user=test_user password=test_password"

# For manual docker or local PostgreSQL
export SQLSKETCH_PG_CONN="host=localhost port=5432 dbname=sqlsketch_bench user=postgres password=postgres"
```

**Default connection string** (if `SQLSKETCH_PG_CONN` not set):
```
host=localhost port=5432 dbname=sqlsketch_bench user=postgres password=postgres
```

This default is safe because:
- ✅ Localhost only (no external access)
- ✅ Test database only (`sqlsketch_bench` or `sqlsketch_test`)
- ✅ No production data
- ✅ Easily customizable via environment variable

**Never commit production credentials to git.**

## Benchmarks

### 1. Basic Performance (`basic.jl`)

Measures query construction, SQL compilation, and execution performance.

```bash
julia --project=. bench/postgresql/basic.jl
```

**Measures:**
- Query AST construction speed
- SQL compilation speed
- Query execution speed (SELECT queries)
- PostgreSQL-specific queries (JSONB, Arrays)

### 2. Type-Specific Performance (`types.jl`)

Tests PostgreSQL-specific types: UUID, JSONB, Arrays, BOOLEAN, TIMESTAMP.

```bash
julia --project=. bench/postgresql/types.jl
```

**Measures:**
- UUID primary key performance
- Native BOOLEAN vs SQLite INTEGER
- TIMESTAMP precision
- JSONB query performance (if supported)
- TEXT[] array performance (if supported)

### 3. SQLite vs PostgreSQL Comparison (`comparison.jl`)

Compares identical queries on both databases.

```bash
SQLSKETCH_PG_CONN="host=localhost port=5433 dbname=sqlsketch_test user=test_user password=test_password" \
  julia --project=. bench/postgresql/comparison.jl
```

**Measures:**
- Relative performance (which is faster?)
- Allocation differences
- Network overhead vs in-memory (SQLite)

### 4. Connection Pooling (`connection_pooling.jl`)

Tests connection pool performance vs direct connections.

```bash
SQLSKETCH_PG_CONN="host=localhost port=5433 dbname=sqlsketch_test user=test_user password=test_password" \
  julia --project=. bench/postgresql/connection_pooling.jl
```

**Measures:**
- Connection overhead (new connection vs pooled)
- Query execution time with/without pooling
- Memory and allocation savings
- Short query performance (connection overhead dominant)

**Expected Results:**
- 10-15x speedup for pooled connections
- 90%+ connection overhead reduction
- 99%+ memory reduction

### 5. Full Optimization Stack (`full_optimization_benchmark.jl`)

Tests combined effect of all optimizations (DecodePlan + Prepared Statement Caching).

```bash
SQLSKETCH_PG_CONN="host=localhost port=5433 dbname=sqlsketch_test user=test_user password=test_password" \
  julia --project=. bench/postgresql/full_optimization_benchmark.jl
```

**Measures:**
- Cache miss vs cache hit performance
- Prepared statement cache efficiency
- Overall overhead vs raw LibPQ
- Cache warmup behavior

**Expected Results:**
- 10-15% speedup with prepared statement cache (cache hit)
- 50%+ speedup after cache warmup
- <50% overhead vs raw LibPQ (target achieved: ~25%)

## Expected Results

### Performance Characteristics

**SQLite advantages:**
- In-memory database (no network latency)
- Simpler architecture
- Faster for small datasets (<1000 rows)
- Good for development/testing

**PostgreSQL advantages:**
- Production-ready (ACID, durability)
- Rich type system (UUID, JSONB, Arrays)
- Better concurrency
- Advanced SQL features

### Typical Speedup

For SQLSketch overhead comparison:

| Query Type | SQLite overhead | PostgreSQL overhead |
|------------|-----------------|---------------------|
| Simple SELECT | 15-20x | 5-10x |
| JOIN | 8-10x | 3-5x |
| ORDER + LIMIT | 1.05x | 1.02x |

PostgreSQL prepared statements typically provide better caching benefits (10-20% speedup vs SQLite's 3-11%).

## Troubleshooting

### "Failed to connect to PostgreSQL"

1. Check if PostgreSQL is running:
   ```bash
   docker ps | grep sqlsketch-pg
   ```

2. Check connection string:
   ```bash
   echo $SQLSKETCH_PG_CONN
   ```

3. Test connection manually:
   ```bash
   psql -h localhost -U postgres -d sqlsketch_bench
   ```

### "JSONB/Array queries failed"

This is expected if JSONB/Array codecs are not fully implemented. These features use `raw_expr()` as a workaround.

Future improvement: First-class JSONB and Array expression support.

## Notes

- All benchmarks automatically set up and tear down test data
- PostgreSQL container can be reused across benchmark runs
- Results are affected by PostgreSQL server configuration
- For accurate comparison, use PostgreSQL on localhost (not remote server)

## Quick Start: Run All Benchmarks

To run all PostgreSQL benchmarks at once:

```bash
# 1. Start PostgreSQL with docker-compose
cd test/integration
docker compose up -d postgres

# Wait for PostgreSQL to be ready
sleep 5

# 2. Set connection string
export SQLSKETCH_PG_CONN="host=localhost port=5433 dbname=sqlsketch_test user=test_user password=test_password"

# 3. Run benchmarks
cd ../..
julia --project=. bench/postgresql/basic.jl
julia --project=. bench/postgresql/comparison.jl
julia --project=. bench/postgresql/connection_pooling.jl
julia --project=. bench/postgresql/full_optimization_benchmark.jl

# 4. Cleanup
cd test/integration
docker compose down
```

## Benchmark Results Summary

Based on recent benchmark runs:

### Batch Operations (10,000 rows)
- **PostgreSQL COPY**: 2944x faster than loop INSERT
- **SQLite Batch**: 279x faster than loop INSERT

### Connection Pooling
- **Speedup**: 12.57x (92.04% reduction)
- **Memory**: 99.55% reduction
- **Short queries**: 9.66x faster

### Full Optimization Stack
- **Prepared statement cache**: 12% speedup (cache hit)
- **Cache warmup**: 53% speedup (first vs subsequent)
- **Overhead vs raw LibPQ**: 25.38% (target: <50%)

### SQLite vs PostgreSQL
- **PostgreSQL wins**: 88.81% faster on average
- **Best PostgreSQL win**: 181% faster (filter_and_project)
- **SQLite wins**: 28% faster (small ORDER BY + LIMIT)

## Implemented Benchmarks

✅ **Basic Performance** - Query construction, compilation, execution
✅ **Connection Pooling** - Multi-connection overhead
✅ **Full Optimization Stack** - Prepared statement caching + DecodePlan
✅ **SQLite Comparison** - Side-by-side performance
✅ **Batch Operations** - COPY vs INSERT (see `benchmark/batch_benchmark.jl`)

## Future Benchmarks

Planned additions:

- **Transaction overhead** - BEGIN/COMMIT costs
- **Concurrent queries** - Multi-client performance
- **Streaming results** - Iterator-based row fetching
- **Query plan caching** - AST-based cache
