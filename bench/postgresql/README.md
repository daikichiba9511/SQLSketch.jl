# PostgreSQL Benchmarks

This directory contains benchmarks for SQLSketch.jl with PostgreSQL.

## Prerequisites

### 1. Install PostgreSQL

**Option A: Docker (Recommended)**

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

**Option B: Local Installation**

Install PostgreSQL 12+ and create a database:

```sql
CREATE DATABASE sqlsketch_bench;
```

### 2. Configure Connection

**⚠️ Security Note:** Default credentials are for local development/testing only.

Set environment variable to customize (optional):

```bash
export SQLSKETCH_PG_CONN="host=localhost port=5432 dbname=sqlsketch_bench user=postgres password=postgres"
```

**Default connection string** (if `SQLSKETCH_PG_CONN` not set):
```
host=localhost port=5432 dbname=sqlsketch_bench user=postgres password=postgres
```

This default is safe because:
- ✅ Localhost only (no external access)
- ✅ Test database only (`sqlsketch_bench`)
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
julia --project=. bench/postgresql/comparison.jl
```

**Measures:**
- Relative performance (which is faster?)
- Allocation differences
- Network overhead vs in-memory (SQLite)

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

## Future Benchmarks

Planned additions:

- **Prepared statement caching** - Compare with/without caching
- **Connection pooling** - Multi-connection overhead
- **Batch operations** - COPY vs INSERT performance
- **Transaction overhead** - BEGIN/COMMIT costs
- **Concurrent queries** - Multi-client performance
