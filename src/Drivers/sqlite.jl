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
import ..Core: Driver, Connection, connect, execute

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
