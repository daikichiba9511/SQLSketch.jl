"""
# Database Migrations Example

This file demonstrates database migration functionality in SQLSketch.jl:
- Generating migration files
- Applying migrations
- Checking migration status
- Checksum validation
"""

using SQLSketch          # Core query building functions
using SQLSketch.Drivers  # Database drivers

println("="^80)
println("Database Migrations Example")
println("="^80)

# Setup
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()

# Create migrations directory
migrations_dir = mktempdir()
println("\n[1] Created temporary migrations directory: $migrations_dir")

# Generate initial migration
println("\n[2] Generating initial migration...")
migration1_path = generate_migration(migrations_dir, "create_users_table")
println("✓ Generated: $migration1_path")

# Write migration content
migration1_content = """
-- UP
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL
);

-- DOWN
DROP TABLE users;
"""

write(migration1_path, migration1_content)
println("✓ Wrote migration content")

# Generate another migration
println("\n[3] Generating second migration...")
sleep(1)  # Ensure different timestamp
migration2_path = generate_migration(migrations_dir, "add_user_status")
println("✓ Generated: $migration2_path")

migration2_content = """
-- UP
ALTER TABLE users ADD COLUMN status TEXT DEFAULT 'active';

-- DOWN
-- SQLite doesn't support DROP COLUMN easily
"""

write(migration2_path, migration2_content)
println("✓ Wrote migration content")

# Check migration status before applying
println("\n[4] Checking migration status (before applying)...")
status = migration_status(db, dialect, migrations_dir)
for s in status
    status_icon = s.applied ? "✓" : "✗"
    println("  $status_icon $(s.migration.version) - $(s.migration.name)")
end

# Apply migrations
println("\n[5] Applying migrations...")
applied = apply_migrations(db, dialect, migrations_dir)
println("✓ Applied $(length(applied)) migrations:")
for mig in applied
    println("  - $(mig.version) $(mig.name)")
end

# Check migration status after applying
println("\n[6] Checking migration status (after applying)...")
status = migration_status(db, dialect, migrations_dir)
for s in status
    status_icon = s.applied ? "✓" : "✗"
    println("  $status_icon $(s.migration.version) - $(s.migration.name)")
end

# Verify table was created
println("\n[7] Verifying table creation...")
result = execute(db, dialect,
                 insert_into(:users, [:email, :name, :status, :created_at]) |>
                 insert_values([[literal("alice@example.com"), literal("Alice"),
                                 literal("active"), literal("2025-01-01")]]))
println("✓ Successfully inserted into users table")

# Query the data
q = from(:users) |>
    select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email),
           col(:users, :status))

registry = CodecRegistry()
println("\nUsers table content:")
for row in fetch_all(db, dialect, registry, q)
    println("  $row")
end

# Validate checksums
println("\n[8] Validating migration checksums...")
validate_migration_checksums(db, dialect, migrations_dir)
println("✓ All checksums valid")

# Try to apply migrations again (should be idempotent)
println("\n[9] Attempting to apply migrations again (idempotency test)...")
applied_again = apply_migrations(db, dialect, migrations_dir)
println("✓ Applied $(length(applied_again)) migrations (should be 0)")

# Demonstrate checksum validation failure
println("\n[10] Demonstrating checksum validation failure...")
println("Modifying first migration file...")
original_content = read(migration1_path, String)
write(migration1_path, original_content * "\n-- Modified")

try
    validate_migration_checksums(db, dialect, migrations_dir)
    println("❌ Checksum validation should have failed!")
catch e
    println("✓ Checksum validation failed as expected:")
    println("  Error: ", sprint(showerror, e))
end

# Restore original content
write(migration1_path, original_content)
println("✓ Restored original migration content")

# Final validation
println("\n[11] Final checksum validation...")
validate_migration_checksums(db, dialect, migrations_dir)
println("✓ All checksums valid after restoration")

# Cleanup
close(db)
rm(migrations_dir; recursive = true)

println("\n" * "="^80)
println("✅ Migration example completed successfully!")
println("="^80)

println("\nKey takeaways:")
println("  - Migrations are applied in timestamp order")
println("  - SHA256 checksums prevent modification of applied migrations")
println("  - Migrations are idempotent (safe to run multiple times)")
println("  - Failed migrations roll back automatically (transaction-wrapped)")
