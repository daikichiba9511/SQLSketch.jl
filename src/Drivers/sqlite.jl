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
import ..Core: Driver, Connection, connect, execute
import ..Core: TransactionHandle, transaction, savepoint

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
"""
struct SQLiteConnection <: Connection
    db::SQLite.DB
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
execute(db, "INSERT INTO users (email) VALUES (?)", ["test@example.com"])

# Query
result = execute(db, "SELECT * FROM users WHERE id = ?", [1])
```    # Use DBInterface.execute for parameter binding
"""
function execute(conn::SQLiteConnection, sql::String, params::Vector = Any[])
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
    DBInterface.close!(conn.db)
    return nothing
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
    execute(conn, "BEGIN TRANSACTION", [])

    tx = SQLiteTransaction(conn, Ref(true))

    try
        # 2. Execute user function
        result = f(tx)

        # 3. COMMIT on success
        if tx.active[]
            execute(conn, "COMMIT", [])
            tx.active[] = false
        end

        return result
    catch e
        # 4. ROLLBACK on exception
        if tx.active[]
            try
                execute(conn, "ROLLBACK", [])
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
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])
end
```
"""
function execute(tx::SQLiteTransaction, sql::String, params::Vector = Any[])
    if !tx.active[]
        error("Transaction is no longer active (already committed or rolled back)")
    end
    return execute(tx.conn, sql, params)
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
    execute(tx, "INSERT INTO users (email) VALUES (?)", ["alice@example.com"])

    savepoint(tx, :sp1) do sp
        execute(sp, "INSERT INTO orders (user_id, total) VALUES (?, ?)", [1, 100.0])
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
    execute(tx, "SAVEPOINT $savepoint_name", [])

    try
        # 2. Execute user function
        result = f(tx)

        # 3. RELEASE savepoint on success
        execute(tx, "RELEASE SAVEPOINT $savepoint_name", [])

        return result
    catch e
        # 4. ROLLBACK TO savepoint on exception
        try
            execute(tx, "ROLLBACK TO SAVEPOINT $savepoint_name", [])
            # Note: Savepoint remains on stack after ROLLBACK TO, so release it
            execute(tx, "RELEASE SAVEPOINT $savepoint_name", [])
        catch savepoint_error
            # Log savepoint error but prioritize original exception
            @warn "Failed to rollback to savepoint" exception = savepoint_error
        end
        rethrow(e)
    end
end
