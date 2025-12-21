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

"""
    ExecResult

Result of executing a statement with side effects (DML/DDL).

# Fields

  - `command_type::Symbol`: Type of command executed (:insert, :update, :delete, :create_table, :drop_table, :alter_table, :create_index, :drop_index, :unknown)
  - `rowcount::Union{Int, Nothing}`: Number of rows affected (Nothing if unknown or not applicable)

# Example

```julia
result = execute(conn, dialect, insert_query, params)
println(result.command_type)  # :insert
println(result.rowcount)      # Nothing (currently not implemented)
```
"""
struct ExecResult
    command_type::Symbol
    rowcount::Union{Int, Nothing}
end

# Helper: Infer command type from Query (DML only)
"""
    infer_command_type(stmt::Query) -> Symbol

Infer the command type from a Query AST node.

Returns one of: :insert, :update, :delete, :unknown
"""
function infer_command_type(stmt::Query)::Symbol
    # Check for RETURNING wrapper first
    if stmt isa Returning
        # Unwrap and check the source query
        return infer_command_type(stmt.source)
    end

    # Check DML types
    if stmt isa InsertValues || stmt isa InsertInto
        return :insert
    elseif stmt isa UpdateSet || stmt isa UpdateWhere || stmt isa Update
        return :update
    elseif stmt isa DeleteFrom || stmt isa DeleteWhere
        return :delete
    else
        return :unknown
    end
end

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
params = (email = "test@example.com", age = 30)
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
              query::Query{T}, params::NamedTuple = NamedTuple();
              use_prepared::Bool = true) -> Vector{T}

Execute a query and fetch all rows.

Automatically uses prepared statements if the driver supports them.
Prepared statements are cached at the driver level for improved performance.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `registry`: Codec registry for type conversion
  - `query`: Query AST to execute
  - `params`: Named parameters for the query (default: empty NamedTuple)
  - `use_prepared`: Whether to use prepared statements if available (default: true)

# Returns

Vector of results of type T (where T is the query's output type)

# Example

```julia
q = from(:users) |>
    where(col(:users, :age) > param(Int, :min_age)) |>
    select(NamedTuple, col(:users, :id), col(:users, :name))

results = fetch_all(db, dialect, registry, q, (min_age = 25,))
# → Vector{NamedTuple}
# Automatically uses prepared statements if driver supports them

# Disable prepared statements for specific query
results = fetch_all(db, dialect, registry, q, (min_age = 25,); use_prepared=false)
# → Uses direct SQL execution
```
"""
function fetch_all(conn::Connection,
                   dialect::Dialect,
                   registry::CodecRegistry,
                   query::Query{T},
                   params::NamedTuple = NamedTuple();
                   use_prepared::Bool = true)::Vector{T} where {T}
    # Compile query to SQL
    sql, param_names = compile(dialect, query)

    # Bind parameters
    param_values = bind_params(param_names, params)

    # Execute query (use prepared statements if available and enabled)
    raw_result = if use_prepared
        stmt = prepare_statement(conn, sql)
        if stmt !== nothing
            # Driver supports prepared statements - use them
            execute_prepared(conn, stmt, param_values)
        else
            # Fallback to direct execution
            execute_sql(conn, sql, param_values)
        end
    else
        # Direct execution (no prepared statements)
        execute_sql(conn, sql, param_values)
    end

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
                   params::NamedTuple = NamedTuple())::Vector{T} where {T}
    # Compile query to SQL
    sql, param_names = compile(dialect, query)

    # Bind parameters
    param_values = bind_params(param_names, params)

    # Execute query (will use TransactionHandle's execute_sql() method)
    raw_result = execute_sql(tx, sql, param_values)

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

user = fetch_one(db, dialect, registry, q, (id = 1,))
# → NamedTuple (exactly one row)
```
"""
function fetch_one(conn::Connection,
                   dialect::Dialect,
                   registry::CodecRegistry,
                   query::Query{T},
                   params::NamedTuple = NamedTuple())::T where {T}
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
                   params::NamedTuple = NamedTuple())::T where {T}
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

user = fetch_maybe(db, dialect, registry, q, (email = "test@example.com",))
# → NamedTuple or Nothing
```
"""
function fetch_maybe(conn::Connection,
                     dialect::Dialect,
                     registry::CodecRegistry,
                     query::Query{T},
                     params::NamedTuple = NamedTuple())::Union{T, Nothing} where {T}
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
                     params::NamedTuple = NamedTuple())::Union{T, Nothing} where {T}
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
    raw_result = execute_sql(conn, explain_sql, [])

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
                params::NamedTuple = NamedTuple()) -> ExecResult

Execute a DML statement (INSERT, UPDATE, DELETE) without fetching results.

This function is for DML operations that don't use RETURNING clauses.
For DML with RETURNING, use `fetch_all`, `fetch_one`, or `fetch_maybe` instead.

**Note:** This is an internal API. Most users should use the unified `execute()` API instead.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `query`: DML query AST (InsertValues, UpdateWhere, UpdateSet, DeleteFrom, DeleteWhere)
  - `params`: Named parameters for the query (default: empty NamedTuple)

# Returns

ExecResult with command_type and rowcount (currently Nothing)

# Example

```julia
# INSERT
q = insert_into(:users, [:name, :email]) |>
    values([[literal("Alice"), literal("alice@example.com")]])
result = execute_dml(db, dialect, q)
# -> ExecResult(:insert, nothing)

# UPDATE
q = update(:users) |>
    set(:name => param(String, :name)) |>
    where(col(:users, :id) == param(Int, :id))
result = execute_dml(db, dialect, q, (name = "Bob", id = 1))
# -> ExecResult(:update, nothing)

# DELETE
q = delete_from(:users) |>
    where(col(:users, :id) == param(Int, :id))
result = execute_dml(db, dialect, q, (id=1))
# -> ExecResult(:delete, nothing)
```
"""
function execute_dml(conn::Connection,
                     dialect::Dialect,
                     query::Query,
                     params::NamedTuple = NamedTuple())::ExecResult
    # Compile query to SQL
    sql, param_names = compile(dialect, query)

    # Bind parameters
    param_values = bind_params(param_names, params)

    # Execute DML
    execute_sql(conn, sql, param_values)

    # Return execution result
    return ExecResult(infer_command_type(query), nothing)
end

# Allow execute_dml to work with TransactionHandle
function execute_dml(tx::TransactionHandle,
                     dialect::Dialect,
                     query::Query,
                     params::NamedTuple = NamedTuple())::ExecResult
    # Compile query to SQL
    sql, param_names = compile(dialect, query)

    # Bind parameters
    param_values = bind_params(param_names, params)

    # Execute DML
    execute_sql(tx, sql, param_values)

    # Return execution result
    return ExecResult(infer_command_type(query), nothing)
end

"""
    execute(conn::Connection, dialect::Dialect, query::Query,
            params::NamedTuple = NamedTuple()) -> ExecResult

Unified API for executing DML statements (INSERT, UPDATE, DELETE) with side effects.

This is the recommended API for all DML execution. Dispatches internally to `execute_dml`.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `query`: DML query AST
  - `params`: Named parameters for the query (default: empty NamedTuple)

# Returns

ExecResult containing:

  - `command_type::Symbol`: Type of command executed (:insert, :update, :delete)
  - `rowcount::Union{Int, Nothing}`: Number of rows affected (currently Nothing)

# Example

```julia
# INSERT
q = insert_into(:users, [:name, :email]) |>
    values([[literal("Alice"), literal("alice@example.com")]])
result = execute(conn, dialect, q)
# -> ExecResult(:insert, nothing)

# UPDATE
q = update(:users) |>
    set(:status => literal("inactive")) |>
    where(col(:users, :age) > literal(100))
result = execute(conn, dialect, q)
# -> ExecResult(:update, nothing)

# DELETE
q = delete_from(:users) |>
    where(col(:users, :status) == literal("deleted"))
result = execute(conn, dialect, q)
# -> ExecResult(:delete, nothing)
```
"""
function execute(conn::Connection,
                 dialect::Dialect,
                 query::Query,
                 params::NamedTuple = NamedTuple())::ExecResult
    return execute_dml(conn, dialect, query, params)
end

# Allow execute with Query to work with TransactionHandle
function execute(tx::TransactionHandle,
                 dialect::Dialect,
                 query::Query,
                 params::NamedTuple = NamedTuple())::ExecResult
    return execute_dml(tx, dialect, query, params)
end

# Note: For raw SQL execution, use execute_sql() directly.
# execute() is reserved for AST-based execution (Query and DDLStatement).
