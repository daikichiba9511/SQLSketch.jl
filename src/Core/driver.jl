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
    execute_sql(conn::Connection, sql::String, params::Vector=Any[]) -> result

Execute a raw SQL statement with optional parameters.

This is a low-level API for direct SQL execution. It serves as an "escape hatch"
for executing SQL that isn't supported by the query AST (e.g., PRAGMA, VACUUM, vendor-specific commands).

Most users should use the high-level `execute()` API with query ASTs instead.

# Arguments

  - `conn`: An active database connection
  - `sql`: The SQL statement to execute
  - `params`: Optional vector of parameter values

# Returns

  - Raw database result (driver-specific type)

# Example

```julia
# Execute PostgreSQL-specific command
result = execute_sql(db, "VACUUM ANALYZE users", [])

# Execute with parameters
result = execute_sql(db, "SELECT * FROM users WHERE id = ?", [42])
```
"""
function execute_sql(conn::Connection, sql::String, params::Vector = Any[])
    error("execute_sql not implemented for $(typeof(conn))")
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

#
# Prepared Statement Interface (Optional)
#
# Drivers that support prepared statements should implement these methods.
# If not implemented, SQLSketch will fall back to execute_sql() without caching.
#

"""
    prepare_statement(conn::Connection, sql::String) -> Any

Prepare a SQL statement and return a prepared statement handle.

This is an optional driver method. If implemented, SQLSketch will cache
prepared statements for improved performance on repeated queries.

# Arguments

  - `conn`: An active database connection
  - `sql`: The SQL statement to prepare (with placeholders)

# Returns

  - A prepared statement handle (driver-specific type)

# Example

```julia
# SQLite example
stmt = prepare_statement(conn, "SELECT * FROM users WHERE id = ?")

# PostgreSQL example
stmt = prepare_statement(conn, "SELECT * FROM users WHERE id = \$1")
```

# Note

If not implemented for a driver, SQLSketch will use `execute_sql()` directly
without prepared statement caching.
"""
function prepare_statement(conn::Connection, sql::String)
    # Default implementation: not supported
    # Drivers that support prepared statements should override this
    return nothing
end

"""
    execute_prepared(conn::Connection, stmt, params::Vector) -> result

Execute a prepared statement with parameters.

This is an optional driver method. Must be implemented if `prepare_statement`
is implemented.

# Arguments

  - `conn`: An active database connection
  - `stmt`: A prepared statement handle (from `prepare_statement`)
  - `params`: Vector of parameter values

# Returns

  - Raw database result (driver-specific type)

# Example

```julia
stmt = prepare_statement(conn, "SELECT * FROM users WHERE id = ?")
result = execute_prepared(conn, stmt, [42])
```
"""
function execute_prepared(conn::Connection, stmt, params::Vector)
    # Default implementation: not supported
    error("execute_prepared not implemented for $(typeof(conn))")
end

"""
    supports_prepared_statements(driver::Driver) -> Bool

Check if a driver supports prepared statements.

# Arguments

  - `driver`: The database driver

# Returns

  - `true` if the driver implements `prepare_statement` and `execute_prepared`
  - `false` otherwise

# Example

```julia
driver = SQLiteDriver()
if supports_prepared_statements(driver)
    println("Prepared statements supported")
end
```
"""
function supports_prepared_statements(driver::Driver)::Bool
    # Default: not supported
    # Drivers should override this if they support prepared statements
    return false
end
