"""
# Database Metadata API

This module provides database introspection capabilities for SQLSketch.

## Features

- List tables in a database
- Describe table structure (columns, types, constraints)
- List schemas (PostgreSQL)

## Design Principles

- Driver-specific implementation (different DBs have different system catalogs)
- Read-only operations (no schema modifications)
- Consistent API across databases
- Graceful handling of DB-specific features

## Usage

```julia
conn = connect(SQLiteDriver(), "mydb.sqlite")

# List all tables
tables = list_tables(conn)
# → ["users", "posts", "comments"]

# Describe table structure
columns = describe_table(conn, :users)
# → [ColumnInfo("id", "INTEGER", false, nothing, true),
#     ColumnInfo("email", "TEXT", false, nothing, false),
#     ColumnInfo("created_at", "TIMESTAMP", true, "CURRENT_TIMESTAMP", false)]

# List schemas (PostgreSQL only)
schemas = list_schemas(conn)
# → ["public", "myapp"]
```

See CLAUDE.md for design rationale.
"""

"""
    ColumnInfo

Information about a database column.

# Fields

- `name::String`: Column name
- `type::String`: Column type (database-specific, e.g. "INTEGER", "TEXT", "VARCHAR(255)")
- `nullable::Bool`: Whether the column accepts NULL values
- `default::Union{String, Nothing}`: Default value expression (as string), or nothing
- `primary_key::Bool`: Whether this column is part of the primary key

# Example

```julia
col = ColumnInfo("id", "INTEGER", false, nothing, true)
println(col.name)         # "id"
println(col.type)         # "INTEGER"
println(col.nullable)     # false
println(col.primary_key)  # true
```
"""
struct ColumnInfo
    name::String
    type::String
    nullable::Bool
    default::Union{String,Nothing}
    primary_key::Bool
end

# Pretty printing for REPL
function Base.show(io::IO, col::ColumnInfo)
    pk_marker = col.primary_key ? " [PK]" : ""
    nullable_marker = col.nullable ? " NULL" : " NOT NULL"
    default_marker = col.default !== nothing ? " DEFAULT $(col.default)" : ""
    print(io,
          "ColumnInfo($(col.name): $(col.type)$(pk_marker)$(nullable_marker)$(default_marker))")
end

"""
    list_tables(conn::Connection) -> Vector{String}

List all tables in the database.

Returns a vector of table names as strings.

# Arguments

- `conn`: Active database connection

# Returns

Vector of table names (strings)

# Example

```julia
conn = connect(SQLiteDriver(), "mydb.sqlite")
tables = list_tables(conn)
# → ["users", "posts", "comments"]
```

# Implementation

This function must be implemented by each driver. The default implementation
throws an error.
"""
function list_tables(conn::Connection)::Vector{String}
    error("list_tables not implemented for $(typeof(conn))")
end

"""
    describe_table(conn::Connection, table::Symbol) -> Vector{ColumnInfo}

Describe the structure of a table.

Returns information about all columns in the specified table.

# Arguments

- `conn`: Active database connection
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

# Implementation

This function must be implemented by each driver. The default implementation
throws an error.
"""
function describe_table(conn::Connection, table::Symbol)::Vector{ColumnInfo}
    error("describe_table not implemented for $(typeof(conn))")
end

"""
    list_schemas(conn::Connection) -> Vector{String}

List all schemas in the database.

Note: This is primarily for PostgreSQL. SQLite does not have schemas,
and MySQL uses "databases" instead of schemas.

# Arguments

- `conn`: Active database connection

# Returns

Vector of schema names (strings)

# Example

```julia
conn = connect(PostgreSQLDriver(), "postgresql://localhost/mydb")
schemas = list_schemas(conn)
# → ["public", "myapp", "analytics"]
```

# Implementation

This function must be implemented by each driver. Drivers for databases
without schema support (e.g., SQLite) should return an empty vector or
a single default schema name.
"""
function list_schemas(conn::Connection)::Vector{String}
    # Default implementation: no schema support
    return String[]
end
