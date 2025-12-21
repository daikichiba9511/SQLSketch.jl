# API Reference

## Query Building

### Starting Queries

```@docs
from
```

### Filtering and Conditions

```@docs
where
having
```

### Selecting Columns

```@docs
select
distinct
```

### Ordering and Limiting

```@docs
order_by
limit
offset
```

### Grouping

```@docs
group_by
```

## DML Operations

### INSERT

```@docs
insert_into
```

### Batch INSERT

For efficient insertion of large datasets, use `insert_batch`:

```@docs
insert_batch
```

**Performance:**
- **SQLite:** 1.35x - 299x faster than loop INSERT
- **PostgreSQL:** 4x - 2016x faster (uses COPY FROM STDIN)

**Example:**

```julia
# Prepare data
users = [
    (id=1, email="alice@example.com", active=true),
    (id=2, email="bob@example.com", active=true),
    # ... thousands more
]

# Batch insert (automatically optimized)
result = insert_batch(conn, dialect, registry, :users,
                      [:id, :email, :active], users)
println("Inserted $(result.rowcount) rows")
```

See `benchmark/RESULTS.md` in the repository for detailed performance analysis.

### UPDATE

```@docs
update
```

### DELETE

```@docs
delete_from
```

### RETURNING

```@docs
returning
```

## DDL Operations

### Table Operations

```@docs
create_table
alter_table
drop_table
add_column
```

### Index Operations

```@docs
create_index
drop_index
```

## Expressions

### Column References

```@docs
col
```

### Literals and Parameters

```@docs
literal
param
p_
```

### Comparisons

Binary operators are overloaded for `SQLExpr`:
- `==`, `!=` - Equality/inequality
- `<`, `<=`, `>`, `>=` - Comparison
- `+`, `-`, `*`, `/` - Arithmetic
- `&` (and), `|` (or) - Logical operators

### Type Conversion

```@docs
cast
```

### Subqueries

```@docs
subquery
```

## Query Execution

SQLSketch separates **data retrieval** from **side-effecting operations**.

**Key distinction:**
- Use **`fetch_*`** when you want to **retrieve data** (SELECT, INSERT/UPDATE/DELETE with RETURNING)
- Use **`execute`** when you want to **produce side effects** without retrieving data (INSERT, UPDATE, DELETE, CREATE TABLE, etc.)

**Quick reference:**

| Function | Returns | Use Case | Performance |
|----------|---------|----------|-------------|
| `fetch_all(conn, query)` | `Vector{T}` | Get all rows (row-based) | Fast (40-155% overhead vs raw) |
| `fetch_all_columnar(conn, query)` | `NamedTuple of Vectors` | Get all rows (columnar) | **Fastest (4-12% overhead vs raw)** |
| `fetch_all_columnar(conn, query, ColumnarType)` | `ColumnarType` | Get all rows (type-safe columnar) | **Fastest + type-safe** |
| `fetch_one(conn, query)` | `T` | Get exactly one row (error if 0 or >1) | - |
| `fetch_maybe(conn, query)` | `Union{T, Nothing}` | Get optional row | - |
| `execute(conn, query)` | `Int64` | Perform side effects (returns affected row count) | - |

See [Design - Query Execution Model](design.md#13-query-execution-model) for detailed rationale.

### Fetching Results

#### Row-Based API

```@docs
fetch_all
fetch_one
fetch_maybe
```

**Performance characteristics (PostgreSQL):**

| Result Size | Time | Overhead vs Raw LibPQ |
|-------------|------|----------------------|
| 500 rows | ~327 μs | 40% |
| 1667 rows | ~2.5 ms | 155% |

**When to use:**
- ✅ CRUD operations (iterate over individual records)
- ✅ Small to medium result sets (<10,000 rows)
- ✅ Row-by-row processing is natural

#### Columnar API (PostgreSQL Only)

**Note:** `fetch_all_columnar` is a PostgreSQL-specific optimization. See PostgreSQL driver documentation for details.

**Performance characteristics (PostgreSQL):**

| Result Size | Time | Overhead vs Raw LibPQ |
|-------------|------|----------------------|
| 500 rows | ~252 μs | 12% |
| 1667 rows | ~1.1 ms | 6% |

**Speedup vs row-based:** 8-10x faster

**When to use:**
- ✅ Analytics queries (aggregations, statistics)
- ✅ Large result sets (>1,000 rows)
- ✅ Column-wise operations (sum, mean, filter)
- ✅ DataFrame/CSV export
- ✅ Data science workflows

**Usage:**

```julia
# Option 1: NamedTuple of Vectors (flexible)
result = fetch_all_columnar(conn, dialect, registry, query)
# → (id = [1, 2, 3, ...], amount = [100.0, 200.0, ...])
total = sum(result.amount)

# Option 2: Type-safe columnar struct (recommended for production)
struct SalesColumnar
    id::Vector{Int}
    amount::Vector{Float64}
end

result = fetch_all_columnar(conn, dialect, registry, query, SalesColumnar)
# → SalesColumnar([1, 2, 3, ...], [100.0, 200.0, ...])
total = sum(result.amount)  # Type-safe!
```

### Executing Statements

```@docs
execute
ExecResult
```

### Transactions

```@docs
transaction
savepoint
```

## SQL Generation

```@docs
sql
compile
explain
```

## Metadata API

SQLSketch provides introspection APIs to query database schema metadata:

### Database Schema Inspection

```@docs
list_tables
list_schemas
describe_table
```

**Example:**

```julia
# List all tables in current database
tables = list_tables(conn)
# → ["orders", "products", "users"]

# Get table structure
columns = describe_table(conn, :users)
for col in columns
    println("$(col.name): $(col.type) $(col.nullable ? "NULL" : "NOT NULL")")
end
# → id: INT NOT NULL [PK]
# → email: VARCHAR(255) NOT NULL
# → name: VARCHAR(255) NOT NULL
# → age: INT NULL
# → created_at: DATETIME NULL

# List all schemas/databases
schemas = list_schemas(conn)
# → ["myapp_dev", "myapp_test", "myapp_prod"]
```

**MySQL-specific notes:**
- `list_tables()` excludes system tables automatically
- `list_schemas()` excludes `information_schema`, `mysql`, `performance_schema`, `sys`
- `describe_table()` returns MySQL-specific type names (e.g., `TINYINT(1)`, `VARCHAR(255)`)

## Dialects

SQLSketch provides dialect abstraction for different SQL databases:

- **SQLiteDialect** - SQLite SQL generation
- **PostgreSQLDialect** - PostgreSQL SQL generation
- **MySQLDialect** - MySQL SQL generation

Each dialect handles:
- Identifier quoting (`"identifier"` for PostgreSQL, `` `identifier` `` for MySQL/SQLite)
- Placeholder syntax (`$1, $2, ...` for PostgreSQL, `?` for MySQL/SQLite)
- Type mapping and casting
- SQL feature capabilities (RETURNING, ON CONFLICT, etc.)

**Note:** MariaDB may work with MySQLDialect via protocol compatibility but is not explicitly tested.

## Drivers

SQLSketch provides driver abstraction for database connections:

- **SQLiteDriver** - SQLite database driver (in-memory or file-based)
- **PostgreSQLDriver** - PostgreSQL database driver (via LibPQ.jl)
- **MySQLDriver** - MySQL database driver (via MySQL.jl, tested with MySQL 8.0+)

Each driver handles:
- Connection management
- Query execution
- Transaction support
- Parameter binding
- Result mapping
- Prepared statement caching (MySQL, PostgreSQL)

### MySQL Driver Features

**JSON Support:**

MySQL 5.7+ provides native JSON type support via the `JSONCodec`:

```julia
using SQLSketch.Codecs.MySQL

# Register MySQL codecs (includes JSON support)
registry = CodecRegistry()
MySQL.register_mysql_codecs!(registry)

# JSON data is automatically encoded/decoded
metadata = Dict("role" => "admin", "permissions" => ["read", "write"])
execute_sql(conn, "INSERT INTO users (email, metadata) VALUES (?, ?)",
           ["user@example.com", JSON3.write(metadata)])

# Retrieve JSON
rows = fetch_all(conn, dialect, registry, query)
json_data = JSON3.read(rows[1].metadata, Dict{String, Any})
```

**Prepared Statement Caching:**

MySQL driver includes LRU-based prepared statement caching for improved performance:

```julia
# Prepared statements are automatically cached
q = from(:users) |>
    where(col(:users, :id) == param(Int, :id)) |>
    select(NamedTuple, col(:users, :email))

# First execution - cache miss, statement prepared
result1 = fetch_all(conn, dialect, registry, q, (id=1,); use_prepared=true)

# Second execution - cache hit, reuses prepared statement
result2 = fetch_all(conn, dialect, registry, q, (id=2,); use_prepared=true)
```

**Performance benefits:**
- 10-20% faster for repeated queries
- Reduced MySQL server load (no re-parsing)
- LRU eviction prevents memory bloat
- Thread-safe for single-connection use

**Configuration:**

```julia
# Custom cache size
raw_conn = DBInterface.connect(MySQL.Connection, host, user, password; db=db)
conn = MySQLConnection(raw_conn; cache_size=200, enable_cache=true)

# Disable caching
conn = MySQLConnection(raw_conn; enable_cache=false)
```

## Migration System

```@docs
SQLSketch.Extras.apply_migrations
SQLSketch.Extras.migration_status
```

## Connection Pooling

SQLSketch provides thread-safe connection pooling for high-concurrency applications.

### Basic Usage

```julia
# Create connection pool
pool = ConnectionPool(PostgreSQLDriver(),
                      "postgresql://localhost/mydb";
                      min_size=2,    # Minimum connections
                      max_size=10)   # Maximum connections

# Resource-safe pattern (recommended)
with_connection(pool) do conn
    result = fetch_all(conn, dialect, registry, query)
end

# Manual acquire/release pattern
conn = acquire(pool)
try
    result = fetch_all(conn, dialect, registry, query)
finally
    release(pool, conn)
end

# Cleanup
close(pool)
```

### API Reference

```@docs
ConnectionPool
acquire
release
with_connection
```

### Configuration

```julia
pool = ConnectionPool(driver, config;
                      min_size = 1,              # Minimum pool size
                      max_size = 10,             # Maximum pool size
                      health_check_interval = 60.0)  # Health check interval (seconds)
```

**Parameters:**

- `driver`: Database driver instance
- `config`: Driver-specific connection configuration (e.g., connection string for PostgreSQL)
- `min_size`: Minimum number of connections to maintain (default: 1)
- `max_size`: Maximum number of connections allowed (default: 10)
- `health_check_interval`: Seconds between health checks (default: 60.0, set to 0.0 to disable)

### Performance

Connection pooling provides:

- **>80% reduction** in connection overhead
- **5-10x faster** for short queries (connection time dominates)
- **Near-zero overhead** for long queries
- **Better resource utilization** under high concurrency

### Examples

**PostgreSQL Connection Pool:**

```julia
pool = ConnectionPool(PostgreSQLDriver(),
                      "postgresql://user:pass@localhost/mydb";
                      min_size=5, max_size=20)

# Use in multi-threaded application
Threads.@threads for i in 1:100
    with_connection(pool) do conn
        result = fetch_all(conn, dialect, registry, query)
        # Process result...
    end
end

close(pool)
```

**MySQL Connection Pool:**

```julia
pool = ConnectionPool(MySQLDriver(),
                      ("localhost", "mydb", "user", "password");
                      min_size=2, max_size=10)

with_connection(pool) do conn
    result = fetch_all(conn, dialect, registry, query)
end

close(pool)
```

**SQLite Connection Pool:**

```julia
# SQLite supports connection pooling for read-heavy workloads
pool = ConnectionPool(SQLiteDriver(), ":memory:";
                      min_size=1, max_size=5)

with_connection(pool) do conn
    result = fetch_all(conn, dialect, registry, query)
end

close(pool)
```

### Thread Safety

All pool operations (acquire, release, close) are thread-safe and protected by a `ReentrantLock`. The pool can be safely shared across multiple threads.

### Health Checking

The pool validates connections before reuse:

- Connections idle longer than `health_check_interval` are health-checked
- Broken connections are automatically replaced
- Health checks use lightweight ping queries

### Best Practices

1. **Use `with_connection` pattern**: Ensures connections are always released
2. **Set appropriate pool size**: Too small = contention, too large = wasted resources
3. **Monitor pool utilization**: Check `in_use` vs `available` connections
4. **Close pool on shutdown**: Use `close(pool)` to clean up resources

See `examples/connection_pool_example.jl` for a complete example.
