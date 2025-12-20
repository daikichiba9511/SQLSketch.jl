"""
# PostgreSQL Driver

PostgreSQL driver implementation for SQLSketch.

This driver uses LibPQ.jl and DBInterface.jl to execute queries
against PostgreSQL databases.

## Features

- Connection pooling support
- Transaction support
- Prepared statement support
- Full PostgreSQL type system support
- Advanced features (LISTEN/NOTIFY, COPY, etc.)

## Dependencies

- LibPQ.jl
- DBInterface.jl

## Usage

```julia
driver = PostgreSQLDriver()
db = connect(driver, "host=localhost dbname=mydb user=postgres password=secret")
result = execute(db, "SELECT * FROM users WHERE id = \$1", [42])
close(db)
```

See `docs/design.md` Section 11 for detailed design rationale.
"""

using LibPQ
using DBInterface
import ..Core: Driver, Connection, connect, execute_sql
import ..Core: TransactionHandle, transaction, savepoint

"""
    PostgreSQLDriver()

PostgreSQL database driver.

# Example

```julia
driver = PostgreSQLDriver()
db = connect(driver, "host=localhost dbname=mydb")
```
"""
struct PostgreSQLDriver <: Driver
end

"""
    PostgreSQLConnection(conn::LibPQ.Connection)

PostgreSQL database connection wrapper.

# Fields

  - `conn`: The underlying LibPQ.Connection instance
"""
struct PostgreSQLConnection <: Connection
    conn::LibPQ.Connection
end

#
# Driver Interface Implementation
#

"""
    connect(driver::PostgreSQLDriver, conninfo::String) -> PostgreSQLConnection

Connect to a PostgreSQL database.

# Arguments

  - `driver`: PostgreSQLDriver instance
  - `conninfo`: PostgreSQL connection string (libpq format)

# Returns

  - PostgreSQLConnection instance

# Example

```julia
# Using connection string
db = connect(PostgreSQLDriver(), "host=localhost dbname=mydb user=postgres")

# Using PostgreSQL URI
db = connect(PostgreSQLDriver(), "postgresql://user:password@localhost:5432/mydb")
```

# Connection String Format

The connection string uses libpq format with space-separated key=value pairs:

  - `host=localhost` - Server hostname
  - `port=5432` - Server port (default: 5432)
  - `dbname=mydb` - Database name
  - `user=postgres` - Username
  - `password=secret` - Password
  - `sslmode=require` - SSL mode (disable, allow, prefer, require, verify-ca, verify-full)

Alternatively, use PostgreSQL URI format:
`postgresql://[user[:password]@][host][:port][/dbname][?param1=value1&...]`
"""
function connect(driver::PostgreSQLDriver, conninfo::String)::PostgreSQLConnection
    conn = LibPQ.Connection(conninfo)
    return PostgreSQLConnection(conn)
end

"""
    execute(conn::PostgreSQLConnection, sql::String, params::Vector=Any[])

Execute a SQL statement against a PostgreSQL database.

# Arguments

  - `conn`: Active PostgreSQL connection
  - `sql`: SQL statement to execute (use \$1, \$2, etc. for parameters)
  - `params`: Optional vector of parameter values

# Returns

  - LibPQ.Result object for SELECT statements
  - Statement result for DDL/DML statements

# Example

```julia
# DDL
execute(db, "CREATE TABLE users (id SERIAL PRIMARY KEY, email TEXT)")

# DML with parameters
execute_sql(db, "INSERT INTO users (email) VALUES (\$1)", ["test@example.com"])

# Query
result = execute_sql(db, "SELECT * FROM users WHERE id = \$1", [1])
```
"""
function execute_sql(conn::PostgreSQLConnection, sql::String, params::Vector = Any[])
    # LibPQ.execute handles parameter binding automatically
    return LibPQ.execute(conn.conn, sql, params)
end

"""
    Base.close(conn::PostgreSQLConnection) -> Nothing

Close a PostgreSQL connection and release resources.

# Arguments

  - `conn`: The connection to close

# Example

```julia
close(db)
```
"""
function Base.close(conn::PostgreSQLConnection)::Nothing
    close(conn.conn)
    return nothing
end

#
# Transaction Support
#

"""
    PostgreSQLTransaction(conn::PostgreSQLConnection, active::Ref{Bool})

PostgreSQL transaction handle that wraps a connection.

# Fields

  - `conn`: The underlying PostgreSQLConnection
  - `active`: Reference to boolean tracking if transaction is still active
"""
struct PostgreSQLTransaction <: TransactionHandle
    conn::PostgreSQLConnection
    active::Ref{Bool}
end

"""
    transaction(f::Function, conn::PostgreSQLConnection) -> result

Execute a function within a PostgreSQL transaction.

Uses BEGIN / COMMIT / ROLLBACK commands.

# Arguments

  - `f`: Function to execute. Receives PostgreSQLTransaction handle as argument.
  - `conn`: PostgreSQL database connection

# Returns

The return value of the function `f`

# Example

```julia
result = transaction(db) do tx
    execute(tx, "INSERT INTO users (email) VALUES (\$1)", ["alice@example.com"])
    execute(tx, "INSERT INTO orders (user_id, total) VALUES (\$1, \$2)", [1, 100.0])
    return "success"
end
```

# Implementation Details

  - BEGIN starts the transaction
  - COMMIT is executed if the function completes successfully
  - ROLLBACK is executed if an exception occurs
  - The transaction handle can be used with execute() and all query execution APIs
"""
function transaction(f::Function, conn::PostgreSQLConnection)
    # 1. BEGIN TRANSACTION
    execute_sql(conn, "BEGIN", [])

    tx = PostgreSQLTransaction(conn, Ref(true))

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
                @warn "Failed to rollback transaction" exception = rollback_error
            end
            tx.active[] = false
        end
        rethrow(e)
    end
end

"""
    execute(tx::PostgreSQLTransaction, sql::String, params::Vector = Any[])

Execute a SQL statement within a PostgreSQL transaction.

# Arguments

  - `tx`: PostgreSQL transaction handle
  - `sql`: SQL statement to execute
  - `params`: Optional vector of parameter values

# Returns

LibPQ.Result object or statement result

# Errors

Throws an error if the transaction is no longer active

# Example

```julia
transaction(db) do tx
    execute_sql(tx, "INSERT INTO users (email) VALUES (\$1)", ["alice@example.com"])
end
```
"""
function execute_sql(tx::PostgreSQLTransaction, sql::String, params::Vector = Any[])
    if !tx.active[]
        error("Transaction is no longer active (already committed or rolled back)")
    end
    return execute_sql(tx.conn, sql, params)
end

"""
    savepoint(f::Function, tx::PostgreSQLTransaction, name::Symbol) -> result

Create a savepoint within a PostgreSQL transaction.

Uses SAVEPOINT / RELEASE / ROLLBACK TO commands.

# Arguments

  - `f`: Function to execute within the savepoint
  - `tx`: PostgreSQL transaction handle
  - `name`: Unique name for the savepoint

# Returns

The return value of the function `f`

# Example

```julia
transaction(db) do tx
    execute_sql(tx, "INSERT INTO users (email) VALUES (\$1)", ["alice@example.com"])

    savepoint(tx, :sp1) do sp
        execute_sql(sp, "INSERT INTO orders (user_id, total) VALUES (\$1, \$2)", [1, 100.0])
        # Rolls back to sp1 if error occurs
    end
end
```

# Implementation Details

  - SAVEPOINT creates a new savepoint on the transaction stack
  - RELEASE removes the savepoint on success
  - ROLLBACK TO restores database state to the savepoint
  - Savepoints can be nested
"""
function savepoint(f::Function, tx::PostgreSQLTransaction, name::Symbol)
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
            # PostgreSQL keeps savepoint after ROLLBACK TO, so release it
            execute_sql(tx, "RELEASE SAVEPOINT $savepoint_name", [])
        catch savepoint_error
            @warn "Failed to rollback to savepoint" exception = savepoint_error
        end
        rethrow(e)
    end
end
