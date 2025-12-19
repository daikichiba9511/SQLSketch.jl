"""
# Query Execution

This module defines the query execution API for SQLSketch.

This is where all components come together:
- Query AST → Dialect → SQL
- Driver → Execution → Raw results
- CodecRegistry → Mapped results

## Design Principles

- Query execution is explicit and type-safe
- SQL is always inspectable before execution
- Results are decoded according to the query's output type
- Observability hooks are supported at the execution layer

## API

- `all(conn, query, params)` → `Vector{OutT}` – fetch all rows
- `one(conn, query, params)` → `OutT` – fetch exactly one row (error otherwise)
- `maybeone(conn, query, params)` → `Union{OutT, Nothing}` – fetch zero or one row

## Inspection API

- `sql(dialect, query)` → SQL string for inspection
- `explain(conn, dialect, query)` → EXPLAIN output (if supported)

## Usage

```julia
db = connect(SQLiteDriver(), ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

q = from(:users) |>
    where(col(:users, :email) == param(String, :email)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

users = all(db, dialect, registry, q, (email="test@example.com",))
# → Vector{NamedTuple}

user = one(db, dialect, registry, q, (email="test@example.com",))
# → NamedTuple (error if 0 or 2+ rows)

maybe_user = maybeone(db, dialect, registry, q, (email="test@example.com",))
# → Union{NamedTuple, Nothing}
```

See `docs/design.md` Section 15 for detailed design rationale.
"""

# Note: This file is included in the Core module, so all types are already available
# via the parent module scope

# Helper: Bind parameters from NamedTuple to Vector according to param order
"""
    bind_params(param_names::Vector{Symbol}, params::NamedTuple) -> Vector

Bind parameters from a NamedTuple to a Vector in the order specified by param_names.

# Arguments

  - `param_names`: Ordered list of parameter names (from compile)
  - `params`: NamedTuple containing parameter values

# Returns

Vector of parameter values in the correct order for SQL execution

# Example

```julia
param_names = [:email, :age]
params = (email="test@example.com", age=30)
values = bind_params(param_names, params)
# → ["test@example.com", 30]
```

# Errors

Throws an error if a required parameter is missing from the params NamedTuple.
"""
function bind_params(param_names::Vector{Symbol}, params::NamedTuple)::Vector
    values = []
    for name in param_names
        if !haskey(params, name)
            error("Missing parameter: :$name")
        end
        push!(values, params[name])
    end
    return values
end

"""
    fetch_all(conn::Connection, dialect::Dialect, registry::CodecRegistry,
              query::Query{T}, params::NamedTuple = NamedTuple()) -> Vector{T}

Execute a query and fetch all rows.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `registry`: Codec registry for type conversion
  - `query`: Query AST to execute
  - `params`: Named parameters for the query (default: empty NamedTuple)

# Returns

Vector of results of type T (where T is the query's output type)

# Example

```julia
q = from(:users) |>
    where(col(:users, :age) > param(Int, :min_age)) |>
    select(NamedTuple, col(:users, :id), col(:users, :name))

results = fetch_all(db, dialect, registry, q, (min_age=25,))
# → Vector{NamedTuple}
```
"""
function fetch_all(conn::Connection,
                   dialect::Dialect,
                   registry::CodecRegistry,
                   query::Query{T},
                   params::NamedTuple=NamedTuple())::Vector{T} where {T}
    # Compile query to SQL
    sql, param_names = compile(dialect, query)

    # Bind parameters
    param_values = bind_params(param_names, params)

    # Execute query
    raw_result = execute(conn, sql, param_values)

    # Map rows to target type
    results = T[]
    for row in raw_result
        mapped = map_row(registry, T, row)
        push!(results, mapped)
    end

    return results
end

# Allow fetch_all to work with TransactionHandle
function fetch_all(tx::TransactionHandle,
                   dialect::Dialect,
                   registry::CodecRegistry,
                   query::Query{T},
                   params::NamedTuple=NamedTuple())::Vector{T} where {T}
    # Compile query to SQL
    sql, param_names = compile(dialect, query)

    # Bind parameters
    param_values = bind_params(param_names, params)

    # Execute query (will use TransactionHandle's execute() method)
    raw_result = execute(tx, sql, param_values)

    # Map rows to target type
    results = T[]
    for row in raw_result
        mapped = map_row(registry, T, row)
        push!(results, mapped)
    end

    return results
end

"""
    fetch_one(conn::Connection, dialect::Dialect, registry::CodecRegistry,
              query::Query{T}, params::NamedTuple = NamedTuple()) -> T

Execute a query and fetch exactly one row.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `registry`: Codec registry for type conversion
  - `query`: Query AST to execute
  - `params`: Named parameters for the query (default: empty NamedTuple)

# Returns

Single result of type T

# Errors

  - Throws an error if the query returns zero rows
  - Throws an error if the query returns more than one row

# Example

```julia
q = from(:users) |>
    where(col(:users, :id) == param(Int, :id)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

user = fetch_one(db, dialect, registry, q, (id=1,))
# → NamedTuple (exactly one row)
```
"""
function fetch_one(conn::Connection,
                   dialect::Dialect,
                   registry::CodecRegistry,
                   query::Query{T},
                   params::NamedTuple=NamedTuple())::T where {T}
    results = fetch_all(conn, dialect, registry, query, params)

    if length(results) == 0
        error("Expected exactly one row, but got zero rows")
    elseif length(results) > 1
        error("Expected exactly one row, but got $(length(results)) rows")
    end

    return results[1]
end

# Allow fetch_one to work with TransactionHandle
function fetch_one(tx::TransactionHandle,
                   dialect::Dialect,
                   registry::CodecRegistry,
                   query::Query{T},
                   params::NamedTuple=NamedTuple())::T where {T}
    results = fetch_all(tx, dialect, registry, query, params)

    if length(results) == 0
        error("Expected exactly one row, but got zero rows")
    elseif length(results) > 1
        error("Expected exactly one row, but got $(length(results)) rows")
    end

    return results[1]
end

"""
    fetch_maybe(conn::Connection, dialect::Dialect, registry::CodecRegistry,
                query::Query{T}, params::NamedTuple = NamedTuple()) -> Union{T, Nothing}

Execute a query and fetch zero or one row.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `registry`: Codec registry for type conversion
  - `query`: Query AST to execute
  - `params`: Named parameters for the query (default: empty NamedTuple)

# Returns

  - Single result of type T if exactly one row is returned
  - `Nothing` if zero rows are returned

# Errors

Throws an error if the query returns more than one row

# Example

```julia
q = from(:users) |>
    where(col(:users, :email) == param(String, :email)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

user = fetch_maybe(db, dialect, registry, q, (email="test@example.com",))
# → NamedTuple or Nothing
```
"""
function fetch_maybe(conn::Connection,
                     dialect::Dialect,
                     registry::CodecRegistry,
                     query::Query{T},
                     params::NamedTuple=NamedTuple())::Union{T, Nothing} where {T}
    results = fetch_all(conn, dialect, registry, query, params)

    if length(results) == 0
        return nothing
    elseif length(results) > 1
        error("Expected zero or one row, but got $(length(results)) rows")
    end

    return results[1]
end

# Allow fetch_maybe to work with TransactionHandle
function fetch_maybe(tx::TransactionHandle,
                     dialect::Dialect,
                     registry::CodecRegistry,
                     query::Query{T},
                     params::NamedTuple=NamedTuple())::Union{T, Nothing} where {T}
    results = fetch_all(tx, dialect, registry, query, params)

    if length(results) == 0
        return nothing
    elseif length(results) > 1
        error("Expected zero or one row, but got $(length(results)) rows")
    end

    return results[1]
end

"""
    sql(dialect::Dialect, query::Query) -> String

Generate SQL string from a query for inspection (without executing).

# Arguments

  - `dialect`: SQL dialect for compilation
  - `query`: Query AST to compile

# Returns

SQL string (with parameter placeholders)

# Example

```julia
q = from(:users) |>
    where(col(:users, :age) > param(Int, :min_age)) |>
    select(NamedTuple, col(:users, :name))

sql_str = sql(dialect, q)
# → "SELECT `name` FROM `users` WHERE `age` > ?"
```
"""
function sql(dialect::Dialect, query::Query)::String
    sql_str, _ = compile(dialect, query)
    return sql_str
end

"""
    explain(conn::Connection, dialect::Dialect, query::Query) -> String

Execute EXPLAIN on a query and return the query plan.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `query`: Query AST to explain

# Returns

EXPLAIN output as a string

# Example

```julia
q = from(:users) |>
    where(col(:users, :age) > literal(25)) |>
    select(NamedTuple, col(:users, :name))

plan = explain(db, dialect, q)
# → EXPLAIN output
```
"""
function explain(conn::Connection, dialect::Dialect, query::Query)::String
    # Compile the original query
    sql_str, param_names = compile(dialect, query)

    # Create EXPLAIN query
    explain_sql = "EXPLAIN QUERY PLAN $sql_str"

    # Execute EXPLAIN (no parameters needed for EXPLAIN)
    raw_result = execute(conn, explain_sql, [])

    # Collect results into a string
    lines = String[]
    for row in raw_result
        # Convert row to string representation
        push!(lines, string(row))
    end

    return Base.join(lines, "\n")
end

"""
    execute_dml(conn::Connection, dialect::Dialect, query::Query,
                params::NamedTuple = NamedTuple()) -> Nothing

Execute a DML statement (INSERT, UPDATE, DELETE) without fetching results.

This function is for DML operations that don't use RETURNING clauses.
For DML with RETURNING, use `fetch_all`, `fetch_one`, or `fetch_maybe` instead.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `query`: DML query AST (InsertValues, UpdateWhere, UpdateSet, DeleteFrom, DeleteWhere)
  - `params`: Named parameters for the query (default: empty NamedTuple)

# Returns

Nothing

# Example

```julia
# INSERT
q = insert_into(:users, [:name, :email]) |>
    values([[literal("Alice"), literal("alice@example.com")]])
execute_dml(db, dialect, q)

# UPDATE
q = update(:users) |>
    set(:name => param(String, :name)) |>
    where(col(:users, :id) == param(Int, :id))
execute_dml(db, dialect, q, (name="Bob", id=1))

# DELETE
q = delete_from(:users) |>
    where(col(:users, :id) == param(Int, :id))
execute_dml(db, dialect, q, (id=1))
```
"""
function execute_dml(conn::Connection,
                     dialect::Dialect,
                     query::Query,
                     params::NamedTuple=NamedTuple())::Nothing
    # Compile query to SQL
    sql, param_names = compile(dialect, query)

    # Bind parameters
    param_values = bind_params(param_names, params)

    # Execute DML (no result to process)
    execute(conn, sql, param_values)

    return nothing
end

# Allow execute_dml to work with TransactionHandle
function execute_dml(tx::TransactionHandle,
                     dialect::Dialect,
                     query::Query,
                     params::NamedTuple=NamedTuple())::Nothing
    # Compile query to SQL
    sql, param_names = compile(dialect, query)

    # Bind parameters
    param_values = bind_params(param_names, params)

    # Execute DML (no result to process)
    execute(tx, sql, param_values)

    return nothing
end
