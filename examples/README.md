# SQLSketch.jl Examples

This directory contains example scripts demonstrating various features of SQLSketch.jl.

## Running Examples

```bash
# From the repository root
julia --project=. examples/<example_file>.jl
```

## Available Examples

### 1. Basic Queries (`basic_queries.jl`)

Demonstrates fundamental query operations:
- Simple WHERE and ORDER BY clauses
- JOIN queries
- INSERT with parameters
- Transactions
- UPDATE and DELETE operations

**Usage:**
```bash
julia --project=. examples/basic_queries.jl
```

### 2. JOIN Operations (`join_examples.jl`)

Comprehensive examples of all JOIN types:
- INNER JOIN - only matching rows
- LEFT JOIN - all left rows, matching right (with NULLs)
- RIGHT JOIN - all right rows, matching left (SQLite limitation workaround)
- FULL JOIN - all rows from both tables
- Multiple JOINs - chaining multiple join operations
- Self-joins - joining a table to itself
- JOIN with filtering - combining WHERE clauses

**Usage:**
```bash
julia --project=. examples/join_examples.jl
```

### 3. Window Functions (`window_functions.jl`)

Shows how to use SQL window functions:
- ROW_NUMBER, RANK, DENSE_RANK
- LAG and LEAD for sequential comparisons
- Running totals with SUM
- Moving averages with AVG
- NTILE for percentiles
- FIRST_VALUE and LAST_VALUE

**Usage:**
```bash
julia --project=. examples/window_functions.jl
```

### 4. Database Migrations (`migrations_example.jl`)

Demonstrates the migration system:
- Generating migration files
- Applying migrations
- Checking migration status
- SHA256 checksum validation
- Idempotency

**Usage:**
```bash
julia --project=. examples/migrations_example.jl
```

### 5. PostgreSQL Features (`postgresql_example.jl`)

PostgreSQL-specific functionality:
- UUID primary keys
- JSONB for structured data
- ARRAY types
- TIMESTAMP WITH TIME ZONE
- RETURNING clause
- Savepoints (nested transactions)

**Prerequisites:**
- PostgreSQL server running
- Database `sqlsketch_test` created

**Setup:**
```bash
# Create test database
psql -c 'CREATE DATABASE sqlsketch_test;'

# Set environment variables (optional)
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=sqlsketch_test
export PGUSER=postgres
export PGPASSWORD=your_password
```

**Usage:**
```bash
julia --project=. examples/postgresql_example.jl
```

### 6. Manual Integration Test (`manual_integration_test.jl`)

Low-level integration test showing the complete flow:
- Database setup
- Query AST construction
- SQL compilation
- Driver execution
- Result decoding with CodecRegistry

This example is useful for understanding how the layers work together.

**Usage:**
```bash
julia --project=. examples/manual_integration_test.jl
```

### 7. Create Test Database (`create_test_db.jl`)

Creates a persistent SQLite database for manual inspection:
- Creates `examples/test.db`
- Populates with sample users and posts
- Demonstrates foreign keys

**Usage:**
```bash
julia --project=. examples/create_test_db.jl

# Then inspect with sqlite3
sqlite3 examples/test.db
```

## Quick Start

```bash
# Run basic queries example
julia --project=. examples/basic_queries.jl

# Run JOIN examples
julia --project=. examples/join_examples.jl

# Run window functions example
julia --project=. examples/window_functions.jl

# Run migrations example
julia --project=. examples/migrations_example.jl

# Create persistent database and inspect
julia --project=. examples/create_test_db.jl
sqlite3 examples/test.db
```

## Example Output

Each example produces formatted output showing:
- Generated SQL
- Query results
- Step-by-step execution

## Common Patterns

All examples follow these patterns:

```julia
using SQLSketch          # Core query building functions
using SQLSketch.Drivers  # Database drivers

# Connect to database
driver = SQLiteDriver()  # or PostgreSQLDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()  # or PostgreSQLDialect()
registry = CodecRegistry()

# Build query
q = from(:users) |>
    where(col(:users, :age) > literal(18)) |>
    select(NamedTuple, col(:users, :id), col(:users, :name))

# Execute query
results = fetch_all(db, dialect, registry, q)

# Cleanup
close(db)
```

## Database Schema

The `create_test_db.jl` example creates these tables:

### users table
```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    age INTEGER,
    is_active INTEGER DEFAULT 1,
    created_at TEXT NOT NULL
);
```

### posts table
```sql
CREATE TABLE posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    content TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

## Contributing Examples

When adding new examples:
1. Use the standard import pattern: `using SQLSketch` and `using SQLSketch.Drivers`
2. Include a docstring explaining the example
3. Add clear section headers with `println`
4. Show both the SQL and results
5. Clean up resources with `close(db)`
6. Update this README

## See Also

- [Getting Started Guide](../docs/src/getting-started.md)
- [Tutorial](../docs/src/tutorial.md)
- [API Reference](../docs/src/api.md)

## Notes

- Database files (`*.db`) are excluded from git via `.gitignore`
- `test.db` must be recreated after cloning the repository
- Most examples use SQLite for simplicity and portability
- PostgreSQL example requires a running PostgreSQL server
