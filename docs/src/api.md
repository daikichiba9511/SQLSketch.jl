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

#### Columnar API

```@docs
fetch_all_columnar
```

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

## Dialects

SQLSketch provides dialect abstraction for different SQL databases:

- **SQLiteDialect** - SQLite SQL generation
- **PostgreSQLDialect** - PostgreSQL SQL generation

Each dialect handles:
- Identifier quoting (`"identifier"` for PostgreSQL, `` `identifier` `` for SQLite)
- Placeholder syntax (`$1, $2, ...` for PostgreSQL, `?, ?, ...` for SQLite)
- Type mapping and casting
- SQL feature capabilities (RETURNING, ON CONFLICT, etc.)

## Drivers

SQLSketch provides driver abstraction for database connections:

- **SQLiteDriver** - SQLite database driver (in-memory or file-based)
- **PostgreSQLDriver** - PostgreSQL database driver (via LibPQ.jl)

Each driver handles:
- Connection management
- Query execution
- Transaction support
- Parameter binding
- Result mapping

## Migration System

```@docs
SQLSketch.Extras.apply_migrations
SQLSketch.Extras.migration_status
```
