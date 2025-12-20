# Getting Started with SQLSketch.jl

**⚠️ Note: This is a toy project for learning purposes, not intended for production use.**

SQLSketch.jl is a type-safe, composable SQL query builder for Julia. It provides a fluent API for constructing SQL queries that are checked at compile time while remaining transparent and inspectable.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/daikichiba9511/SQLSketch.jl")
```

## Database Setup

### PostgreSQL (Primary Target)

SQLSketch is designed with PostgreSQL as the primary target database. PostgreSQL offers rich native types (UUID, JSONB, ARRAY, TIMESTAMP WITH TIME ZONE) and advanced SQL features.

**Install PostgreSQL driver:**

```julia
Pkg.add("LibPQ")
```

**Connect to PostgreSQL:**

```julia
using SQLSketch
using SQLSketch.Drivers: PostgreSQLDriver

# Create driver with connection string
driver = PostgreSQLDriver("host=localhost dbname=mydb user=myuser password=mypass")

# Or use environment variables
driver = PostgreSQLDriver(ENV["DATABASE_URL"])
```

### SQLite (Development/Testing)

SQLite is supported for fast local development and testing, but applications should target PostgreSQL for production.

**Install SQLite driver:**

```julia
Pkg.add("SQLite")
```

**Connect to SQLite:**

```julia
using SQLSketch
using SQLSketch.Drivers: SQLiteDriver

# In-memory database
driver = SQLiteDriver(":memory:")

# Or file-based
driver = SQLiteDriver("dev.db")
```

## Your First Query

### Basic SELECT

```julia
using SQLSketch

# Build a query
q = from(:users) |>
    where(col(:users, :active) == literal(true)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

# Inspect generated SQL
println(sql(q, PostgreSQLDialect()))
# SELECT "users"."id", "users"."email" FROM "users" WHERE "users"."active" = $1

# Execute query
results = fetch_all(driver, q)
# Vector{NamedTuple{(:id, :email), Tuple{Int64, String}}}

for row in results
    println("$(row.id): $(row.email)")
end
```

### Type-Safe Structs

Map query results directly to structs:

```julia
struct User
    id::Int64
    email::String
    created_at::DateTime
end

q = from(:users) |>
    select(User,
           col(:users, :id),
           col(:users, :email),
           col(:users, :created_at))

users = fetch_all(driver, q)
# Vector{User}
```

### Parameterized Queries

Use placeholders for safe parameter binding:

```julia
# Define parameter
user_id = p_(:user_id, Int64)

q = from(:users) |>
    where(col(:users, :id) == user_id) |>
    select(User, col(:users, :id), col(:users, :email), col(:users, :created_at))

# Execute with parameter values
user = fetch_one(driver, q, user_id => 42)
# User(42, "user@example.com", DateTime(...))
```

## Core Concepts

### Query Building Styles

SQLSketch provides flexible query building. Here are three approaches:

#### 1. Pipeline Style (Recommended)

The pipeline style uses `|>` to chain operations, mirroring SQL's logical evaluation order:

```julia
q = from(:users) |>
    where(col(:users, :active) == literal(true)) |>
    order_by(col(:users, :created_at); desc=true) |>
    limit(10) |>
    select(User, col(:users, :id), col(:users, :email))
```

**Advantages:**
- Reads naturally from top to bottom (FROM → WHERE → ORDER BY → LIMIT → SELECT)
- Matches SQL's logical evaluation order
- Easy to add/remove operations
- Most readable for complex queries

#### 2. Nested Style

Functions can be nested, but this reads inside-out:

```julia
q = select(
    limit(
        order_by(
            where(
                from(:users),
                col(:users, :active) == literal(true)
            ),
            col(:users, :created_at); desc=true
        ),
        10
    ),
    User,
    col(:users, :id),
    col(:users, :email)
)
```

**Drawbacks:**
- Reads from innermost to outermost (reverse order)
- Hard to scan visually
- Difficult to modify

#### 3. Step-by-Step Style

Queries can be built incrementally by assigning intermediate results:

```julia
q1 = from(:users)
q2 = where(q1, col(:users, :active) == literal(true))
q3 = order_by(q2, col(:users, :created_at); desc=true)
q4 = limit(q3, 10)
q5 = select(q4, User, col(:users, :id), col(:users, :email))
```

**Use cases:**
- Conditional query building
- Debugging intermediate steps
- When clarity is more important than conciseness

**All three styles generate identical SQL:**

```sql
SELECT "users"."id", "users"."email"
FROM "users"
WHERE "users"."active" = $1
ORDER BY "users"."created_at" DESC
LIMIT $2
```

**Recommendation:** Use the pipeline style for most cases. Use step-by-step when you need conditional logic or debugging.

### Shape-Preserving vs Shape-Changing

- **Shape-Preserving**: Operations that don't change the output type
  - `from`, `where`, `join`, `order_by`, `limit`, `offset`, `distinct`, `group_by`, `having`

- **Shape-Changing**: Only `select` changes the output type
  - Must specify output type: `select(NamedTuple, ...)` or `select(User, ...)`

### SQL Transparency

All queries are inspectable before execution:

```julia
q = from(:users) |> where(col(:users, :active) == literal(true))

# View generated SQL
println(sql(q, PostgreSQLDialect()))

# Get SQL with parameter positions
compiled = compile(PostgreSQLDialect(), q)
println(compiled.sql)
println(compiled.param_order)

# View EXPLAIN plan
println(explain(q, PostgreSQLDialect()))
```

## Common Patterns

### Joins

```julia
q = from(:users) |>
    join(:posts, col(:posts, :user_id) == col(:users, :id); kind=:left) |>
    select(NamedTuple,
           col(:users, :email),
           col(:posts, :title))
```

### Ordering and Limiting

```julia
q = from(:users) |>
    order_by(col(:users, :created_at); desc=true) |>
    limit(10)
```

### Aggregation

```julia
q = from(:orders) |>
    group_by(col(:orders, :user_id)) |>
    select(NamedTuple,
           col(:orders, :user_id),
           count_star())
```

### Subqueries

```julia
subq = from(:orders) |>
       select(NamedTuple, col(:orders, :user_id))

q = from(:users) |>
    where(col(:users, :id) |> in_(subquery(subq)))
```

## DML Operations

### INSERT

```julia
q = insert_into(:users, [:email, :active]) |>
    values([literal("new@example.com"), literal(true)])

execute_dml(driver, q)
```

### UPDATE

```julia
q = update(:users) |>
    set_(:email, literal("updated@example.com")) |>
    where(col(:users, :id) == literal(1))

execute_dml(driver, q)
```

### DELETE

```julia
q = delete_from(:users) |>
    where(col(:users, :active) == literal(false))

execute_dml(driver, q)
```

### RETURNING (PostgreSQL)

```julia
q = insert_into(:users, [:email, :active]) |>
    values([literal("new@example.com"), literal(true)]) |>
    returning(col(:users, :id))

new_id = fetch_one(driver, q)
```

## Transactions

```julia
result = transaction(driver) do tx
    # Multiple operations in transaction
    execute_dml(tx, insert_query)
    execute_dml(tx, update_query)

    # Fetch within transaction
    user = fetch_one(tx, select_query)

    # Return value from transaction
    user.id
end

# Automatically commits on success, rolls back on error
```

### Savepoints (Nested Transactions)

```julia
transaction(driver) do tx
    execute_dml(tx, query1)

    savepoint(tx, :sp1) do sp
        execute_dml(sp, query2)
        # Rolls back to sp1 on error
    end

    execute_dml(tx, query3)
end
```

## PostgreSQL-Specific Features

### UUID

```julia
using UUIDs

struct User
    id::UUID
    email::String
end

q = from(:users) |>
    where(col(:users, :id) == literal(uuid4())) |>
    select(User, col(:users, :id), col(:users, :email))
```

### JSONB

```julia
# Store JSON data
metadata = Dict("tags" => ["admin", "verified"], "score" => 100)

q = insert_into(:users, [:email, :metadata]) |>
    values([literal("user@example.com"), literal(metadata)])

execute_dml(driver, q)
```

### Arrays

```julia
# Query with array literal
tags = ["julia", "database"]

q = from(:posts) |>
    where(col(:posts, :tags) == literal(tags))
```

## Next Steps

- **[API Reference](api.md)** - Complete API documentation
- **[Tutorial](tutorial.md)** - Step-by-step learning path
- **[Design Philosophy](design.md)** - Understanding SQLSketch's architecture

## Getting Help

- Check the [API Reference](api.md) for function documentation
- Report issues at [GitHub Issues](https://github.com/daikichiba9511/SQLSketch.jl/issues)
