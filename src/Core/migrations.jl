"""
# Migration Runner

This module defines the minimal migration runner for SQLSketch.

The migration runner applies schema changes in a deterministic order
and tracks which migrations have been applied.

## Design Principles

- Migrations are **opaque units of change**
- The runner tracks applied migrations in a metadata table
- Migrations are applied in deterministic order
- Re-application is prevented
- Migrations can be raw SQL or structured DDL operations

## Scope

The Core layer is responsible for:
- Applying migrations
- Tracking which migrations have been applied
- Compiling DDL statements in a dialect-aware way

The Core layer explicitly does **not**:
- Infer schema differences
- Auto-generate migrations
- Manage online or zero-downtime migrations

## API

- `apply_migrations(db, migrations_dir)` – discover and apply pending migrations
- `list_migrations(db)` – list applied migrations
- `migration_status(db, migrations_dir)` – show pending vs applied

## Migration Format

Migrations can be:
- Raw SQL files (e.g., `001_create_users.sql`)
- Structured DDL operations compiled by the Dialect

## Usage

```julia
# migrations/001_create_users.sql
# CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT);

apply_migrations(db, "migrations/")
# → users table created, migration tracked in schema_migrations

apply_migrations(db, "migrations/")
# → no-op, already applied
```

See `docs/design.md` Section 14 for detailed design rationale.
"""

# TODO: Implement migration runner
# This is Phase 8 of the roadmap

# Placeholder functions - to be completed in Phase 8

# TODO: Implement apply_migrations(db::Connection, migrations_dir::String)
# TODO: Implement list_migrations(db::Connection) -> Vector{String}
# TODO: Implement migration_status(db::Connection, migrations_dir::String)
# TODO: Implement create_migrations_table(db::Connection)
# TODO: Implement discover_migrations(migrations_dir::String) -> Vector{Migration}
# TODO: Implement apply_migration(db::Connection, migration::Migration)
