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

### Fetching Results

```@docs
fetch_all
fetch_one
fetch_maybe
```

### Executing DML

```@docs
execute_dml
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
SQLSketch.Core.apply_migrations
SQLSketch.Core.migration_status
```
