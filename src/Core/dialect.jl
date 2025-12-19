"""
# Dialect Abstraction

This module defines the Dialect abstraction for SQLSketch.

A Dialect represents a database's SQL syntax and semantic differences.
Dialects are responsible for compiling Query ASTs and Expression ASTs
into database-specific SQL strings.

## Design Principles

- Dialects are **pure** – they do not manage connections or execute SQL
- Dialects handle SQL generation, identifier quoting, and placeholder syntax
- Dialects report supported features via a capability system
- Dialect implementations are independent of driver/client libraries

## Responsibilities

- Generate SQL strings from query ASTs
- Quote identifiers (tables, columns, aliases)
- Define placeholder syntax (`?`, `\$1`, etc.)
- Compile DDL statements
- Report supported features via capabilities

## Usage

```julia
dialect = SQLiteDialect()
sql, params = compile(dialect, query)
# sql    → "SELECT id, email FROM users WHERE active = ?"
# params → [:active]
```

See `docs/design.md` Section 10 for detailed design rationale.
"""

# TODO: Implement Dialect abstraction
# This is Phase 3 of the roadmap

"""
Abstract base type for all SQL dialects.

Dialect implementations must define:
- `compile(dialect, query)` → (sql::String, params::Vector{Symbol})
- `compile_expr(dialect, expr)` → sql_fragment::String
- `quote_identifier(dialect, name)` → quoted::String
- `placeholder(dialect, idx)` → placeholder::String
- `supports(dialect, capability)` → Bool
"""
abstract type Dialect end

# Capability enum
"""
Database capabilities that may or may not be supported by a given dialect.

# Capabilities
- `CAP_CTE` – Common Table Expressions (WITH clause)
- `CAP_RETURNING` – RETURNING clause in INSERT/UPDATE/DELETE
- `CAP_UPSERT` – ON CONFLICT / ON DUPLICATE KEY UPDATE
- `CAP_WINDOW` – Window functions
- `CAP_LATERAL` – LATERAL joins
- `CAP_BULK_COPY` – COPY FROM / LOAD DATA operations
- `CAP_SAVEPOINT` – Transaction savepoints
- `CAP_ADVISORY_LOCK` – Advisory locks
"""
@enum Capability begin
    CAP_CTE
    CAP_RETURNING
    CAP_UPSERT
    CAP_WINDOW
    CAP_LATERAL
    CAP_BULK_COPY
    CAP_SAVEPOINT
    CAP_ADVISORY_LOCK
end

#
# Dialect Interface Functions
#
# These functions must be implemented by all Dialect subtypes.
#

"""
    compile(dialect::Dialect, query::Query) -> (sql::String, params::Vector{Symbol})

Compile a Query AST into a SQL string and parameter list.

# Arguments
- `dialect`: The SQL dialect to use for compilation
- `query`: The query AST to compile

# Returns
- `sql`: The generated SQL string
- `params`: A vector of parameter names in the order they appear in the SQL

# Example
```julia
q = from(:users) |> where(col(:users, :id) == param(Int, :user_id))
sql, params = compile(SQLiteDialect(), q)
# sql    → "SELECT * FROM `users` WHERE `users`.`id` = ?"
# params → [:user_id]
```
"""
function compile end

"""
    compile_expr(dialect::Dialect, expr::SQLExpr, params::Vector{Symbol}) -> String

Compile an Expression AST into a SQL fragment.

This function is called recursively to build SQL expressions.
When a `Param` is encountered, its name is appended to the `params` vector.

# Arguments
- `dialect`: The SQL dialect to use for compilation
- `expr`: The expression AST to compile
- `params`: A mutable vector to collect parameter names

# Returns
- A SQL fragment string

# Example
```julia
expr = col(:users, :age) > literal(18)
params = Symbol[]
sql_fragment = compile_expr(SQLiteDialect(), expr, params)
# → "`users`.`age` > 18"
```
"""
function compile_expr end

"""
    quote_identifier(dialect::Dialect, name::Symbol) -> String

Quote an identifier (table name, column name, alias) according to the dialect's rules.

# Arguments
- `dialect`: The SQL dialect
- `name`: The identifier to quote

# Returns
- The quoted identifier

# Examples
```julia
quote_identifier(SQLiteDialect(), :users)     # → "`users`"
quote_identifier(PostgreSQLDialect(), :users) # → "\"users\""
```
"""
function quote_identifier end

"""
    placeholder(dialect::Dialect, idx::Int) -> String

Generate a parameter placeholder for the given index.

# Arguments
- `dialect`: The SQL dialect
- `idx`: The 1-based parameter index

# Returns
- The placeholder string

# Examples
```julia
placeholder(SQLiteDialect(), 1)     # → "?"
placeholder(PostgreSQLDialect(), 1) # → "\$1"
```
"""
function placeholder end

"""
    supports(dialect::Dialect, cap::Capability) -> Bool

Check if the dialect supports a specific capability.

# Arguments
- `dialect`: The SQL dialect
- `cap`: The capability to check

# Returns
- `true` if supported, `false` otherwise

# Example
```julia
supports(SQLiteDialect(), CAP_CTE)       # → true
supports(SQLiteDialect(), CAP_LATERAL)   # → false
```
"""
function supports end
