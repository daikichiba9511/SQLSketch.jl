"""
# Migration Runner

This module implements database migration management for SQLSketch.

Migrations allow you to evolve your database schema over time in a controlled,
version-controlled manner. Each migration represents a discrete change to the schema.

## Design Principles

- **Migration-based versioning**: Track individual migration files, not schema state
- **Timestamp ordering**: Use YYYYMMDDHHMMSS format for deterministic ordering
- **Checksum validation**: Detect modifications to applied migrations
- **Idempotency**: Re-running migration discovery and application is safe
- **Transaction-wrapped**: Each migration runs in a transaction (rollback on failure)

## Migration File Format

Migration files should be named: `{YYYYMMDDHHMMSS}_{name}.sql`

Example: `20250120150000_create_users_table.sql`

Each file can contain SQL statements separated by semicolons.
Use `-- UP` and `-- DOWN` comments to separate up/down migrations (optional).

```sql
-- UP
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- DOWN
DROP TABLE users;
```

## API

### Discovery

- `discover_migrations(dir)` → Vector{Migration} – scan directory for migration files

### Application

- `apply_migration(conn, dialect, migration)` → nothing – apply single migration
- `apply_migrations(conn, dialect, migrations_dir)` → Vector{Migration} – apply all pending

### Status

- `migration_status(conn, dialect, migrations_dir)` → Vector{MigrationStatus}
- `validate_migration_checksums(conn, dialect, migrations_dir)` → Bool

### Utilities

- `generate_migration(dir, name)` → String – create new migration file
- `migration_checksum(content)` → String – SHA256 hash of migration SQL

## Usage

```julia
using SQLSketch
using SQLSketch: apply_migrations, migration_status, generate_migration

db = connect(SQLiteDriver(), "app.db")
dialect = SQLiteDialect()

# Generate new migration
path = generate_migration("db/migrations", "create_users_table")
# Creates: db/migrations/20250120150000_create_users_table.sql

# Apply all pending migrations
applied = apply_migrations(db, dialect, "db/migrations")
println("Applied \$(length(applied)) migrations")

# Check migration status
status = migration_status(db, dialect, "db/migrations")
for s in status
    println("\$(s.migration.version) \$(s.migration.name): \$(s.applied ? "✓" : "✗")")
end
```

See `docs/design.md` Section 16 for detailed design rationale.
"""

using SHA
using Dates
using ..Core: Dialect, Connection, execute_sql, transaction, TransactionHandle

"""
    Migration

Represents a single database migration.

# Fields

  - `version::String` - Timestamp version (YYYYMMDDHHMMSS)
  - `name::String` - Human-readable migration name
  - `up_sql::String` - SQL to apply the migration
  - `down_sql::String` - SQL to rollback the migration (optional, may be empty)
  - `filepath::String` - Full path to the migration file
  - `checksum::String` - SHA256 hash of the up_sql content
"""
struct Migration
    version::String
    name::String
    up_sql::String
    down_sql::String
    filepath::String
    checksum::String
end

"""
    MigrationStatus

Represents the application status of a migration.

# Fields

  - `migration::Migration` - The migration
  - `applied::Bool` - Whether the migration has been applied
  - `applied_at::Union{DateTime, Nothing}` - When the migration was applied (Nothing if not applied)
"""
struct MigrationStatus
    migration::Migration
    applied::Bool
    applied_at::Union{DateTime, Nothing}
end

"""
    migration_checksum(sql::String) -> String

Calculate SHA256 checksum of migration SQL.

This is used to detect modifications to applied migrations.

# Arguments

  - `sql`: Migration SQL content

# Returns

SHA256 hash as a hexadecimal string

# Example

```julia
sql = "CREATE TABLE users (id INTEGER PRIMARY KEY);"
checksum = migration_checksum(sql)
# → "a3b2c1d4..."
```
"""
function migration_checksum(sql::String)::String
    return bytes2hex(sha256(sql))
end

"""
    create_migrations_table(conn::Connection, dialect::Dialect) -> Nothing

Create the schema_migrations table if it doesn't exist.

This table tracks which migrations have been applied to the database.

# Schema

  - `version TEXT PRIMARY KEY` - Migration version (YYYYMMDDHHMMSS)
  - `name TEXT NOT NULL` - Migration name
  - `applied_at DATETIME NOT NULL` - Timestamp when migration was applied
  - `checksum TEXT NOT NULL` - SHA256 hash of the migration SQL

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation

# Example

```julia
create_migrations_table(db, dialect)
```
"""
function create_migrations_table(conn::Connection, dialect::Dialect)::Nothing
    # Check if table already exists (SQLite-specific for now)
    check_sql = """
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='schema_migrations'
    """
    result = execute_sql(conn, check_sql, [])

    # If table doesn't exist, create it
    if isempty(result)
        create_sql = """
        CREATE TABLE schema_migrations (
            version TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            applied_at DATETIME NOT NULL,
            checksum TEXT NOT NULL
        )
        """
        execute_sql(conn, create_sql, [])
    end

    return nothing
end

# Allow create_migrations_table to work with TransactionHandle
function create_migrations_table(tx::TransactionHandle, dialect::Dialect)::Nothing
    # Check if table already exists (SQLite-specific for now)
    check_sql = """
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='schema_migrations'
    """
    result = execute_sql(tx, check_sql, [])

    # If table doesn't exist, create it
    if isempty(result)
        create_sql = """
        CREATE TABLE schema_migrations (
            version TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            applied_at DATETIME NOT NULL,
            checksum TEXT NOT NULL
        )
        """
        execute_sql(tx, create_sql, [])
    end

    return nothing
end

"""
    parse_migration_file(filepath::String) -> Migration

Parse a migration file into a Migration struct.

# File Format

Migration files should be named: `{YYYYMMDDHHMMSS}_{name}.sql`

The file can contain:

  - Just UP SQL (entire file)
  - UP and DOWN sections separated by `-- UP` and `-- DOWN` comments

# Arguments

  - `filepath`: Path to the migration file

# Returns

Migration struct with version, name, up_sql, down_sql, filepath, and checksum

# Example

```julia
migration = parse_migration_file("db/migrations/20250120150000_create_users.sql")
# → Migration(version="20250120150000", name="create_users", ...)
```

# Errors

  - Throws error if filename doesn't match expected format
  - Throws error if file cannot be read
"""
function parse_migration_file(filepath::String)::Migration
    # Extract version and name from filename
    filename = basename(filepath)

    # Expected format: YYYYMMDDHHMMSS_name.sql
    m = match(r"^(\d{14})_(.+)\.sql$", filename)
    if m === nothing
        error("Invalid migration filename: $filename (expected format: YYYYMMDDHHMMSS_name.sql)")
    end

    version = m.captures[1]
    name = m.captures[2]

    # Read file content
    content = read(filepath, String)

    # Split into UP and DOWN sections if markers exist
    up_sql = ""
    down_sql = ""

    if occursin("-- UP", content) && occursin("-- DOWN", content)
        # Split by markers
        parts = split(content, r"-- UP\s*\n"; limit = 2)
        if length(parts) == 2
            up_down = split(parts[2], r"-- DOWN\s*\n"; limit = 2)
            up_sql = strip(up_down[1])
            if length(up_down) == 2
                down_sql = strip(up_down[2])
            end
        end
    else
        # Entire file is UP migration
        up_sql = strip(content)
    end

    # Calculate checksum of up_sql (convert to String to avoid SubString issues)
    checksum = migration_checksum(String(up_sql))

    return Migration(version, name, up_sql, down_sql, filepath, checksum)
end

"""
    discover_migrations(dir::String) -> Vector{Migration}

Discover all migration files in a directory.

Scans the directory for files matching the pattern `YYYYMMDDHHMMSS_name.sql`
and returns them sorted by version (oldest first).

# Arguments

  - `dir`: Directory path to scan for migrations

# Returns

Vector of Migration structs, sorted by version (oldest to newest)

# Example

```julia
migrations = discover_migrations("db/migrations")
# → [Migration(version="20250120150000", ...), Migration(version="20250120160000", ...)]
```

# Errors

  - Throws error if directory doesn't exist
  - Throws error if any migration file has invalid format
"""
function discover_migrations(dir::String)::Vector{Migration}
    if !isdir(dir)
        error("Migration directory does not exist: $dir")
    end

    migrations = Migration[]

    # Find all .sql files
    for filename in readdir(dir)
        if endswith(filename, ".sql")
            filepath = joinpath(dir, filename)
            migration = parse_migration_file(filepath)
            push!(migrations, migration)
        end
    end

    # Sort by version (oldest first)
    sort!(migrations; by = m -> m.version)

    return migrations
end

"""
    get_applied_migrations(conn::Connection, dialect::Dialect) -> Dict{String, Tuple{String, DateTime}}

Get the set of applied migrations from the database.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect

# Returns

Dictionary mapping version → (checksum, applied_at)

# Example

```julia
applied = get_applied_migrations(db, dialect)
# → Dict("20250120150000" => ("a3b2c1...", DateTime(2025, 1, 20, 15, 0, 0)))
```
"""
function get_applied_migrations(conn::Connection,
                                dialect::Dialect)::Dict{String, Tuple{String, DateTime}}
    # Ensure migrations table exists
    create_migrations_table(conn, dialect)

    # Query applied migrations
    query_sql = "SELECT version, checksum, applied_at FROM schema_migrations ORDER BY version"
    rows = execute_sql(conn, query_sql, [])

    applied = Dict{String, Tuple{String, DateTime}}()
    for row in rows
        version = row[1]
        checksum = row[2]
        applied_at_str = row[3]

        # Parse DateTime (SQLite format: YYYY-MM-DD HH:MM:SS)
        applied_at = DateTime(applied_at_str, dateformat"yyyy-mm-dd HH:MM:SS")

        applied[version] = (checksum, applied_at)
    end

    return applied
end

# Allow get_applied_migrations to work with TransactionHandle
function get_applied_migrations(tx::TransactionHandle,
                                dialect::Dialect)::Dict{String, Tuple{String, DateTime}}
    # Ensure migrations table exists
    create_migrations_table(tx, dialect)

    # Query applied migrations
    query_sql = "SELECT version, checksum, applied_at FROM schema_migrations ORDER BY version"
    rows = execute_sql(tx, query_sql, [])

    applied = Dict{String, Tuple{String, DateTime}}()
    for row in rows
        version = row[1]
        checksum = row[2]
        applied_at_str = row[3]

        # Parse DateTime (SQLite format: YYYY-MM-DD HH:MM:SS)
        applied_at = DateTime(applied_at_str, dateformat"yyyy-mm-dd HH:MM:SS")

        applied[version] = (checksum, applied_at)
    end

    return applied
end

"""
    apply_migration(conn::Connection, dialect::Dialect, migration::Migration) -> Nothing

Apply a single migration within a transaction.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect
  - `migration`: Migration to apply

# Returns

Nothing

# Example

```julia
migration = parse_migration_file("db/migrations/20250120150000_create_users.sql")
apply_migration(db, dialect, migration)
```

# Errors

  - Throws error if migration SQL fails to execute
  - Automatically rolls back transaction on failure
"""
function apply_migration(conn::Connection, dialect::Dialect, migration::Migration)::Nothing
    # Apply migration in a transaction
    transaction(conn) do tx
        # Ensure migrations table exists
        create_migrations_table(tx, dialect)

        # Execute the migration SQL
        # Split by semicolon and execute each statement
        statements = split(migration.up_sql, ";")
        for stmt in statements
            stmt_trimmed = String(strip(stmt))  # Convert to String to avoid SubString
            if !isempty(stmt_trimmed)
                execute_sql(tx, stmt_trimmed, [])
            end
        end

        # Record migration in schema_migrations
        now_str = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
        insert_sql = """
        INSERT INTO schema_migrations (version, name, applied_at, checksum)
        VALUES (?, ?, ?, ?)
        """
        execute_sql(tx, insert_sql,
                    [migration.version, migration.name, now_str, migration.checksum])
    end

    return nothing
end

"""
    apply_migrations(conn::Connection, dialect::Dialect, migrations_dir::String) -> Vector{Migration}

Apply all pending migrations from a directory.

Discovers all migrations in the directory, identifies which have not been applied,
and applies them in order (oldest first). Each migration runs in its own transaction.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect
  - `migrations_dir`: Path to directory containing migration files

# Returns

Vector of migrations that were applied (empty if all migrations were already applied)

# Example

```julia
applied = apply_migrations(db, dialect, "db/migrations")
println("Applied \$(length(applied)) migrations")
```

# Errors

  - Throws error if migration directory doesn't exist
  - Throws error if any migration fails (already-applied migrations are not rolled back)
  - Throws error if applied migration checksum doesn't match file checksum (modification detected)
"""
function apply_migrations(conn::Connection, dialect::Dialect,
                          migrations_dir::String)::Vector{Migration}
    # Discover all migrations
    all_migrations = discover_migrations(migrations_dir)

    # Get applied migrations
    applied = get_applied_migrations(conn, dialect)

    # Validate checksums of applied migrations
    for migration in all_migrations
        if haskey(applied, migration.version)
            stored_checksum, _ = applied[migration.version]
            if migration.checksum != stored_checksum
                error("Migration $(migration.version)_$(migration.name) has been modified after being applied!\n" *
                      "Stored checksum: $stored_checksum\n" *
                      "Current checksum: $(migration.checksum)")
            end
        end
    end

    # Filter to pending migrations
    pending = filter(m -> !haskey(applied, m.version), all_migrations)

    # Apply each pending migration
    newly_applied = Migration[]
    for migration in pending
        println("Applying migration: $(migration.version)_$(migration.name)")
        apply_migration(conn, dialect, migration)
        push!(newly_applied, migration)
    end

    return newly_applied
end

"""
    migration_status(conn::Connection, dialect::Dialect, migrations_dir::String) -> Vector{MigrationStatus}

Get the status of all migrations (applied and pending).

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect
  - `migrations_dir`: Path to directory containing migration files

# Returns

Vector of MigrationStatus structs, sorted by version (oldest first)

# Example

```julia
status = migration_status(db, dialect, "db/migrations")
for s in status
    applied_str = s.applied ? "✓" : "✗"
    println("\$applied_str \$(s.migration.version) \$(s.migration.name)")
end
```
"""
function migration_status(conn::Connection, dialect::Dialect,
                          migrations_dir::String)::Vector{MigrationStatus}
    # Discover all migrations
    all_migrations = discover_migrations(migrations_dir)

    # Get applied migrations
    applied = get_applied_migrations(conn, dialect)

    # Build status list
    status_list = MigrationStatus[]
    for migration in all_migrations
        if haskey(applied, migration.version)
            _, applied_at = applied[migration.version]
            push!(status_list, MigrationStatus(migration, true, applied_at))
        else
            push!(status_list, MigrationStatus(migration, false, nothing))
        end
    end

    return status_list
end

"""
    validate_migration_checksums(conn::Connection, dialect::Dialect, migrations_dir::String) -> Bool

Validate that all applied migrations have matching checksums.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect
  - `migrations_dir`: Path to directory containing migration files

# Returns

  - `true` if all applied migrations have matching checksums
  - `false` if any applied migration has been modified

# Example

```julia
if validate_migration_checksums(db, dialect, "db/migrations")
    println("All migrations are valid")
else
    println("WARNING: Some migrations have been modified!")
end
```
"""
function validate_migration_checksums(conn::Connection, dialect::Dialect,
                                      migrations_dir::String)::Bool
    # Discover all migrations
    all_migrations = discover_migrations(migrations_dir)

    # Get applied migrations
    applied = get_applied_migrations(conn, dialect)

    # Check each applied migration
    for migration in all_migrations
        if haskey(applied, migration.version)
            stored_checksum, _ = applied[migration.version]
            if migration.checksum != stored_checksum
                @warn "Migration $(migration.version)_$(migration.name) has been modified!" stored=stored_checksum current=migration.checksum
                return false
            end
        end
    end

    return true
end

"""
    generate_migration(dir::String, name::String) -> String

Generate a new migration file with timestamp version.

Creates a new migration file in the specified directory with the current timestamp
as the version and the provided name.

# Arguments

  - `dir`: Directory where migration file should be created
  - `name`: Human-readable name for the migration (will be used in filename)

# Returns

Full path to the created migration file

# Example

```julia
path = generate_migration("db/migrations", "create_users_table")
# Creates: db/migrations/20250120150000_create_users_table.sql
# Returns: "db/migrations/20250120150000_create_users_table.sql"
```

# File Template

The generated file contains a template with UP and DOWN sections:

```sql
-- UP


-- DOWN

```
"""
function generate_migration(dir::String, name::String)::String
    # Ensure directory exists
    if !isdir(dir)
        mkpath(dir)
    end

    # Generate version from current timestamp
    version = Dates.format(now(), "yyyymmddHHMMSS")

    # Sanitize name (replace spaces with underscores, remove special characters)
    safe_name = replace(name, r"[^a-zA-Z0-9_]" => "_")
    safe_name = replace(safe_name, r"_+" => "_")  # Collapse multiple underscores
    safe_name = lowercase(safe_name)

    # Create filename
    filename = "$(version)_$(safe_name).sql"
    filepath = joinpath(dir, filename)

    # Create file with template
    template = """
    -- UP


    -- DOWN

    """

    write(filepath, template)

    return filepath
end
