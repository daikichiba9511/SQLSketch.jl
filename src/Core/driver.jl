"""
# Driver Abstraction

This module defines the Driver abstraction for SQLSketch.

A Driver represents the execution layer for a specific database backend.
Drivers handle all interactions with the underlying database client
(e.g., DBInterface, libpq, mysqlclient).

## Design Principles

- Drivers handle connection management and SQL execution
- Drivers do **not** interpret query semantics or perform type conversion
- Drivers are independent of SQL generation (that's the Dialect's job)
- Driver errors should be normalized into common error types

## Responsibilities

- Open and close connections
- Prepare statements (if supported)
- Execute SQL statements
- Bind parameters
- Manage transactions
- Handle cancellation and timeouts (if supported)

## Usage

```julia
driver = SQLiteDriver()
db = connect(driver, ":memory:")
result = execute(db, "SELECT * FROM users WHERE id = ?", [42])
close(db)
```

See `docs/design.md` Section 10 for detailed design rationale.
"""

"""
Abstract base type for all database drivers.

Driver implementations must define:

  - `connect(driver, config)` → connection handle
  - `execute(conn, sql, params)` → raw result
  - `close(conn)`
"""
abstract type Driver end

"""
Abstract base type for database connections.

Connections are created by drivers and used to execute queries.
"""
abstract type Connection end

#
# Driver Interface Functions
#
# These functions must be implemented by all Driver subtypes.
#

"""
    connect(driver::Driver, config) -> Connection

Establish a connection to a database.

# Arguments

  - `driver`: The database driver to use
  - `config`: Driver-specific configuration (e.g., file path, connection string)

# Returns

  - A `Connection` instance

# Example

```julia
driver = SQLiteDriver()
db = connect(driver, ":memory:")
```
"""
function connect(driver::Driver, config)::Connection
    error("connect not implemented for $(typeof(driver))")
end

"""
    execute(conn::Connection, sql::String, params::Vector=Any[]) -> result

Execute a SQL statement with optional parameters.

# Arguments

  - `conn`: An active database connection
  - `sql`: The SQL statement to execute
  - `params`: Optional vector of parameter values

# Returns

  - Raw database result (driver-specific type)

# Example

```julia
result = execute(db, "SELECT * FROM users WHERE id = ?", [42])
```
"""
function execute(conn::Connection, sql::String, params::Vector = Any[])
    error("execute not implemented for $(typeof(conn))")
end

"""
    close(conn::Connection) -> Nothing

Close a database connection and release resources.

# Arguments

  - `conn`: The connection to close

# Example

```julia
close(db)
```
"""
function Base.close(conn::Connection)::Nothing
    error("close not implemented for $(typeof(conn))")
end
