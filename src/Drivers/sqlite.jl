"""
# SQLite Driver

SQLite driver implementation for SQLSketch.

This driver uses SQLite.jl and DBInterface.jl to execute queries
against SQLite databases.

## Features

- In-memory databases (`:memory:`)
- File-based databases
- Transaction support
- Basic connection management

## Dependencies

- SQLite.jl
- DBInterface.jl

## Usage

```julia
driver = SQLiteDriver()
db = connect(driver, ":memory:")
result = execute(db, "SELECT * FROM users WHERE id = ?", [42])
close(db)
```

See `docs/design.md` Section 10 for detailed design rationale.
"""

using SQLite
using DBInterface
import ..Core: Driver, Connection, connect, execute_sql
import ..Core: TransactionHandle, transaction, savepoint
import ..Core: prepare_statement, execute_prepared, supports_prepared_statements
import ..Core: list_tables, describe_table, list_schemas, ColumnInfo

"""
    SQLiteDriver()

SQLite database driver.

# Example

```julia
driver = SQLiteDriver()
db = connect(driver, ":memory:")
```
"""
struct SQLiteDriver <: Driver
end

"""
    SQLiteConnection(db::SQLite.DB)

SQLite database connection wrapper.

# Fields

  - `db`: The underlying SQLite.DB instance
  - `stmt_cache`: Cache for prepared statements (Dict{String, SQLite.Stmt})
"""
mutable struct SQLiteConnection <: Connection
    db::SQLite.DB
    stmt_cache::Dict{String,SQLite.Stmt}

    SQLiteConnection(db::SQLite.DB)::SQLiteConnection = new(db, Dict{String,SQLite.Stmt}())
end

#
# Driver Interface Implementation
#

"""
    connect(driver::SQLiteDriver, path::String) -> SQLiteConnection

Connect to a SQLite database.

# Arguments

  - `driver`: SQLiteDriver instance
  - `path`: Database file path or `:memory:` for in-memory database

# Returns

  - SQLiteConnection instance

# Example

```julia
# In-memory database
db = connect(SQLiteDriver(), ":memory:")

# File-based database
db = connect(SQLiteDriver(), "mydb.sqlite")
```
"""
function connect(driver::SQLiteDriver, path::String)::SQLiteConnection
    db = SQLite.DB(path)
    return SQLiteConnection(db)
end

"""
    execute(conn::SQLiteConnection, sql::String, params::Vector=Any[])

Execute a SQL statement against a SQLite database.

# Arguments

  - `conn`: Active SQLite connection
  - `sql`: SQL statement to execute
  - `params`: Optional vector of parameter values (bound to `?` placeholders)

# Returns

  - SQLite.Query object for SELECT statements
  - Nothing for DDL/DML statements

# Example

```julia
# DDL
execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")

# DML with parameters
execute_sql(db, "INSERT INTO users (email) VALUES (?)", ["test@example.com"])

# Query
result = execute_sql(db, "SELECT * FROM users WHERE id = ?", [1])
```
"""
function execute_sql(conn::SQLiteConnection, sql::String, params::Vector = Any[])
    # Use DBInterface.execute for parameter binding
    # SQLite.jl automatically handles parameter binding with Vector
    return DBInterface.execute(conn.db, sql, params)
end

"""
    Base.close(conn::SQLiteConnection) -> Nothing

Close a SQLite connection and release resources.

# Arguments

  - `conn`: The connection to close

# Example

```julia
close(db)
```
"""
function Base.close(conn::SQLiteConnection)::Nothing
    # Finalize all cached statements
    for (_, stmt) in conn.stmt_cache
        try
            DBInterface.close!(stmt)
        catch e
            @warn "Failed to close prepared statement" exception = e
        end
    end
    empty!(conn.stmt_cache)

    # Close database connection
    DBInterface.close!(conn.db)
    return nothing
end

#
# Prepared Statement Support
#

"""
    supports_prepared_statements(driver::SQLiteDriver) -> Bool

SQLite driver supports prepared statements.

# Returns

Always returns `true` for SQLiteDriver.

# Example

```julia
driver = SQLiteDriver()
@assert supports_prepared_statements(driver)
```
"""
function supports_prepared_statements(driver::SQLiteDriver)::Bool
    return true
end

"""
    prepare_statement(conn::SQLiteConnection, sql::String) -> SQLite.Stmt

Prepare a SQL statement for SQLite.

Creates a SQLite.Stmt that can be executed multiple times with different parameters.

# Arguments

  - `conn`: Active SQLite connection
  - `sql`: SQL statement to prepare (with `?` placeholders)

# Returns

  - SQLite.Stmt handle

# Example

```julia
stmt = prepare_statement(conn, "SELECT * FROM users WHERE id = ?")
result = execute_prepared(conn, stmt, [42])
```
"""
function prepare_statement(conn::SQLiteConnection, sql::String)::SQLite.Stmt
    # Check if already in cache
    if haskey(conn.stmt_cache, sql)
        return conn.stmt_cache[sql]
    end

    # Prepare new statement
    stmt = SQLite.Stmt(conn.db, sql)

    # Cache it (connection-level cache, separate from PreparedStatementCache)
    conn.stmt_cache[sql] = stmt

    return stmt
end

"""
    execute_prepared(conn::SQLiteConnection, stmt::SQLite.Stmt,
                     params::Vector) -> SQLite.Query

Execute a prepared SQLite statement with parameters.

# Arguments

  - `conn`: Active SQLite connection
  - `stmt`: Prepared statement handle (from `prepare_statement`)
  - `params`: Vector of parameter values

# Returns

  - SQLite.Query object

# Example

```julia
stmt = prepare_statement(conn, "SELECT * FROM users WHERE id = ?")
result = execute_prepared(conn, stmt, [42])
for row in result
    println(row)
end
```
"""
function execute_prepared(conn::SQLiteConnection,
                          stmt::SQLite.Stmt,
                          params::Vector)::SQLite.Query
    return DBInterface.execute(stmt, params)
end

#
# Metadata API
#

"""
    list_tables(conn::SQLiteConnection) -> Vector{String}

List all tables in the SQLite database.

Queries the `sqlite_master` system table.

# Arguments

- `conn`: Active SQLite connection

# Returns

Vector of table names (excluding SQLite internal tables like sqlite_sequence)

# Example

```julia
conn = connect(SQLiteDriver(), "mydb.sqlite")
tables = list_tables(conn)
# → ["users", "posts", "comments"]
```
"""
function list_tables(conn::SQLiteConnection)::Vector{String}
    result = execute_sql(conn,
                         """
                         SELECT name FROM sqlite_master
                         WHERE type='table'
                           AND name NOT LIKE 'sqlite_%'
                         ORDER BY name
                         """,
                         [])

    tables = String[]
    for row in result
        push!(tables, row.name)
    end

    return tables
end

"""
    describe_table(conn::SQLiteConnection, table::Symbol) -> Vector{ColumnInfo}

Describe the structure of a SQLite table.

Uses `PRAGMA table_info` to get column information.

# Arguments

- `conn`: Active SQLite connection
- `table`: Table name as a symbol

# Returns

Vector of `ColumnInfo` structs describing each column

# Example

```julia
conn = connect(SQLiteDriver(), "mydb.sqlite")
columns = describe_table(conn, :users)
for col in columns
    println("\$(col.name): \$(col.type)")
end
```
"""
function describe_table(conn::SQLiteConnection, table::Symbol)::Vector{ColumnInfo}
    table_name = String(table)

    # PRAGMA table_info returns:
    # cid, name, type, notnull, dflt_value, pk
    result = execute_sql(conn, "PRAGMA table_info($table_name)", [])

    columns = ColumnInfo[]
    for row in result
        # Convert Missing to Nothing for default value
        default_val = row.dflt_value isa Missing ? nothing : row.dflt_value

        is_pk = row.pk > 0
        # PRIMARY KEY columns are implicitly NOT NULL in SQLite
        is_nullable = is_pk ? false : (row.notnull == 0)

        col = ColumnInfo(row.name,                      # name
                         row.type,                      # type
                         is_nullable,                   # nullable
                         default_val,                   # default value
                         is_pk)                         # primary_key
        push!(columns, col)
    end

    return columns
end

"""
    list_schemas(conn::SQLiteConnection) -> Vector{String}

List schemas in SQLite.

SQLite does not have schemas in the same sense as PostgreSQL.
Returns a single default schema name for compatibility.

# Arguments

- `conn`: Active SQLite connection

# Returns

Vector with single element ["main"]

# Example

```julia
conn = connect(SQLiteDriver(), "mydb.sqlite")
schemas = list_schemas(conn)
# → ["main"]
```
"""
function list_schemas(conn::SQLiteConnection)::Vector{String}
    # SQLite doesn't have schemas, return default
    return ["main"]
end

#
# Transaction Support
#

"""
    SQLiteTransaction(conn::SQLiteConnection, active::Ref{Bool})

SQLite transaction handle that wraps a connection.

This handle is compatible with execute() for query execution within transactions.

# Fields

  - `conn`: The underlying SQLiteConnection
  - `active`: Reference to boolean tracking if transaction is still active
"""
struct SQLiteTransaction <: TransactionHandle
    conn::SQLiteConnection
    active::Ref{Bool}
end

"""
    transaction(f::Function, conn::SQLiteConnection) -> result

Execute a function within a SQLite transaction.

Uses BEGIN TRANSACTION / COMMIT / ROLLBACK commands.

# Arguments

  - `f`: Function to execute. Receives SQLiteTransaction handle as argument.
  - `conn`: SQLite database connection

# Returns

The return value of the function `f`

# Example

```julia
result = transaction(db) do tx
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])
    execute(tx, "INSERT INTO orders (user_id, total) VALUES (?, ?)", [1, 100.0])
    return "success"
end
```

# Implementation Details

  - BEGIN TRANSACTION starts the transaction
  - COMMIT is executed if the function completes successfully
  - ROLLBACK is executed if an exception occurs
  - The transaction handle can be used with execute() and all query execution APIs
"""
function transaction(f::Function, conn::SQLiteConnection)
    # 1. BEGIN TRANSACTION
    execute_sql(conn, "BEGIN TRANSACTION", [])

    tx = SQLiteTransaction(conn, Ref(true))

    try
        # 2. Execute user function
        result = f(tx)

        # 3. COMMIT on success
        if tx.active[]
            execute_sql(conn, "COMMIT", [])
            tx.active[] = false
        end

        return result
    catch e
        # 4. ROLLBACK on exception
        if tx.active[]
            try
                execute_sql(conn, "ROLLBACK", [])
            catch rollback_error
                # Log rollback error but prioritize original exception
                @warn "Failed to rollback transaction" exception = rollback_error
            end
            tx.active[] = false
        end
        rethrow(e)
    end
end

"""
    execute(tx::SQLiteTransaction, sql::String, params::Vector = Any[])

Execute a SQL statement within a SQLite transaction.

# Arguments

  - `tx`: SQLite transaction handle
  - `sql`: SQL statement to execute
  - `params`: Optional vector of parameter values

# Returns

SQLite.Query object or nothing (depending on statement type)

# Errors

Throws an error if the transaction is no longer active (already committed/rolled back)

# Example

```julia
transaction(db) do tx
    execute_sql(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])
end
```
"""
function execute_sql(tx::SQLiteTransaction, sql::String, params::Vector = Any[])
    if !tx.active[]
        error("Transaction is no longer active (already committed or rolled back)")
    end
    return execute_sql(tx.conn, sql, params)
end

"""
    savepoint(f::Function, tx::SQLiteTransaction, name::Symbol) -> result

Create a savepoint within a SQLite transaction for nested transaction semantics.

Uses SAVEPOINT / RELEASE / ROLLBACK TO commands.

# Arguments

  - `f`: Function to execute within the savepoint. Receives transaction handle.
  - `tx`: SQLite transaction handle
  - `name`: Unique name for the savepoint

# Returns

The return value of the function `f`

# Example

```julia
transaction(db) do tx
    execute_sql(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])

    savepoint(tx, :sp1) do sp
        execute_sql(sp, "INSERT INTO orders (user_id, total) VALUES (?, ?)", [1, 100.0])
        # Rolls back to sp1 if error occurs
    end
end
```

# Implementation Details

  - SAVEPOINT creates a new savepoint on the transaction stack
  - RELEASE removes the savepoint on success
  - ROLLBACK TO restores database state to the savepoint, then RELEASE removes it
  - Savepoints can be nested
"""
function savepoint(f::Function, tx::SQLiteTransaction, name::Symbol)
    savepoint_name = String(name)

    # 1. SAVEPOINT
    execute_sql(tx, "SAVEPOINT $savepoint_name", [])

    try
        # 2. Execute user function
        result = f(tx)

        # 3. RELEASE savepoint on success
        execute_sql(tx, "RELEASE SAVEPOINT $savepoint_name", [])

        return result
    catch e
        # 4. ROLLBACK TO savepoint on exception
        try
            execute_sql(tx, "ROLLBACK TO SAVEPOINT $savepoint_name", [])
            # Note: Savepoint remains on stack after ROLLBACK TO, so release it
            execute_sql(tx, "RELEASE SAVEPOINT $savepoint_name", [])
        catch savepoint_error
            # Log savepoint error but prioritize original exception
            @warn "Failed to rollback to savepoint" exception = savepoint_error
        end
        rethrow(e)
    end
end
