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
import ..Core: prepare_statement, execute_prepared, supports_prepared_statements
import ..Core: list_tables, describe_table, list_schemas, ColumnInfo

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
  - `stmt_counter`: Counter for generating unique prepared statement names
"""
mutable struct PostgreSQLConnection <: Connection
    conn::LibPQ.Connection
    stmt_counter::Int

    function PostgreSQLConnection(conn::LibPQ.Connection)::PostgreSQLConnection
        return new(conn, 0)
    end
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
# Prepared Statement Support
#

"""
    supports_prepared_statements(driver::PostgreSQLDriver) -> Bool

PostgreSQL driver supports prepared statements.

# Returns

Always returns `true` for PostgreSQLDriver.

# Example

```julia
driver = PostgreSQLDriver()
@assert supports_prepared_statements(driver)
```
"""
function supports_prepared_statements(driver::PostgreSQLDriver)::Bool
    return true
end

"""
    prepare_statement(conn::PostgreSQLConnection, sql::String) -> String

Prepare a SQL statement for PostgreSQL.

PostgreSQL uses named prepared statements. This function generates a unique
name and prepares the statement on the server.

# Arguments

  - `conn`: Active PostgreSQL connection
  - `sql`: SQL statement to prepare (with \$1, \$2, etc. placeholders)

# Returns

  - Prepared statement name (String)

# Example

```julia
stmt_name = prepare_statement(conn, "SELECT * FROM users WHERE id = \$1")
result = execute_prepared(conn, stmt_name, [42])
```

# Note

PostgreSQL's PREPARE command creates a server-side prepared statement.
The statement name is auto-generated and managed internally.
"""
function prepare_statement(conn::PostgreSQLConnection, sql::String)::String
    # Generate unique statement name
    conn.stmt_counter += 1
    stmt_name = "sqlsketch_stmt_$(conn.stmt_counter)"

    # PREPARE statement on PostgreSQL server
    prepare_sql = "PREPARE $stmt_name AS $sql"
    LibPQ.execute(conn.conn, prepare_sql)

    return stmt_name
end

"""
    execute_prepared(conn::PostgreSQLConnection, stmt_name::String,
                     params::Vector) -> LibPQ.Result

Execute a prepared PostgreSQL statement with parameters.

# Arguments

  - `conn`: Active PostgreSQL connection
  - `stmt_name`: Prepared statement name (from `prepare_statement`)
  - `params`: Vector of parameter values

# Returns

  - LibPQ.Result object

# Example

```julia
stmt_name = prepare_statement(conn, "SELECT * FROM users WHERE id = \$1")
result = execute_prepared(conn, stmt_name, [42])
for row in result
    println(row)
end
```
"""
function execute_prepared(conn::PostgreSQLConnection,
                          stmt_name::String,
                          params::Vector)::LibPQ.Result
    # Build EXECUTE statement
    # PostgreSQL's EXECUTE needs parameter values passed as string interpolation
    # But LibPQ.execute handles parameter binding for us
    param_placeholders = join(["\$$i" for i in 1:length(params)], ", ")
    execute_sql_str = if isempty(params)
        "EXECUTE $stmt_name"
    else
        "EXECUTE $stmt_name($param_placeholders)"
    end

    return LibPQ.execute(conn.conn, execute_sql_str, params)
end

#
# Metadata API
#

"""
    list_tables(conn::PostgreSQLConnection; schema::String="public") -> Vector{String}

List all tables in a PostgreSQL database schema.

Queries the `information_schema.tables` catalog.

# Arguments

  - `conn`: Active PostgreSQL connection
  - `schema`: Schema name (default: "public")

# Returns

Vector of table names in the specified schema

# Example

```julia
conn = connect(PostgreSQLDriver(), "postgresql://localhost/mydb")
tables = list_tables(conn)
# → ["users", "posts", "comments"]

# List tables in specific schema
tables = list_tables(conn; schema = "analytics")
```
"""
function list_tables(conn::PostgreSQLConnection; schema::String = "public")::Vector{String}
    result = execute_sql(conn,
                         """
                         SELECT table_name
                         FROM information_schema.tables
                         WHERE table_schema = \$1
                           AND table_type = 'BASE TABLE'
                         ORDER BY table_name
                         """,
                         [schema])

    tables = String[]
    for row in result
        push!(tables, row[1])  # First column is table_name
    end

    return tables
end

"""
    describe_table(conn::PostgreSQLConnection, table::Symbol;
                   schema::String="public") -> Vector{ColumnInfo}

Describe the structure of a PostgreSQL table.

Queries `information_schema.columns` and `information_schema.key_column_usage`.

# Arguments

  - `conn`: Active PostgreSQL connection
  - `table`: Table name as a symbol
  - `schema`: Schema name (default: "public")

# Returns

Vector of `ColumnInfo` structs describing each column

# Example

```julia
conn = connect(PostgreSQLDriver(), "postgresql://localhost/mydb")
columns = describe_table(conn, :users)
for col in columns
    println("\$(col.name): \$(col.type)")
end
```
"""
function describe_table(conn::PostgreSQLConnection,
                        table::Symbol;
                        schema::String = "public")::Vector{ColumnInfo}
    table_name = String(table)

    # Get column information
    result = execute_sql(conn,
                         """
                         SELECT
                             c.column_name,
                             c.data_type,
                             c.is_nullable,
                             c.column_default,
                             CASE WHEN pk.column_name IS NOT NULL THEN true ELSE false END as is_primary_key
                         FROM information_schema.columns c
                         LEFT JOIN (
                             SELECT ku.column_name
                             FROM information_schema.table_constraints tc
                             JOIN information_schema.key_column_usage ku
                                 ON tc.constraint_name = ku.constraint_name
                                 AND tc.table_schema = ku.table_schema
                             WHERE tc.constraint_type = 'PRIMARY KEY'
                                 AND tc.table_schema = \$1
                                 AND tc.table_name = \$2
                         ) pk ON c.column_name = pk.column_name
                         WHERE c.table_schema = \$1
                             AND c.table_name = \$2
                         ORDER BY c.ordinal_position
                         """,
                         [schema, table_name])

    columns = ColumnInfo[]
    for row in result
        col = ColumnInfo(row[1],                                 # column_name
                         row[2],                                 # data_type
                         row[3] == "YES",                        # is_nullable
                         row[4],                                 # column_default
                         row[5])                                 # is_primary_key
        push!(columns, col)
    end

    return columns
end

"""
    list_schemas(conn::PostgreSQLConnection) -> Vector{String}

List all schemas in a PostgreSQL database.

Queries `information_schema.schemata`, excluding system schemas.

# Arguments

  - `conn`: Active PostgreSQL connection

# Returns

Vector of schema names (excluding pg_* and information_schema)

# Example

```julia
conn = connect(PostgreSQLDriver(), "postgresql://localhost/mydb")
schemas = list_schemas(conn)
# → ["public", "myapp", "analytics"]
```
"""
function list_schemas(conn::PostgreSQLConnection)::Vector{String}
    result = execute_sql(conn,
                         """
                         SELECT schema_name
                         FROM information_schema.schemata
                         WHERE schema_name NOT LIKE 'pg_%'
                           AND schema_name != 'information_schema'
                         ORDER BY schema_name
                         """,
                         [])

    schemas = String[]
    for row in result
        push!(schemas, row[1])  # First column is schema_name
    end

    return schemas
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
