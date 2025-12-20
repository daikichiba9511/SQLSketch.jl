"""
Migration Runner Tests

Tests for Phase 8: Migration Runner
"""

using Test
using SQLSketch
using SQLSketch: Migration, MigrationStatus
using SQLSketch: migration_checksum, discover_migrations, parse_migration_file
using SQLSketch: apply_migration, apply_migrations
using SQLSketch: migration_status, validate_migration_checksums, generate_migration
using SQLSketch.Drivers: SQLiteDriver, SQLiteConnection
using Dates

@testset "Migration Runner Tests" begin
    # Test fixtures directory
    fixtures_dir = joinpath(@__DIR__, "..", "fixtures", "migrations")

    @testset "Migration File Parsing" begin
        @testset "Parse migration with UP/DOWN sections" begin
            filepath = joinpath(fixtures_dir, "20250120100000_create_users_table.sql")
            migration = parse_migration_file(filepath)

            @test migration.version == "20250120100000"
            @test migration.name == "create_users_table"
            @test occursin("CREATE TABLE users", migration.up_sql)
            @test occursin("DROP TABLE users", migration.down_sql)
            @test migration.filepath == filepath
            @test length(migration.checksum) == 64  # SHA256 produces 64 hex chars
        end

        @testset "Parse migration without UP/DOWN markers" begin
            filepath = joinpath(fixtures_dir, "20250120120000_add_user_status.sql")
            migration = parse_migration_file(filepath)

            @test migration.version == "20250120120000"
            @test migration.name == "add_user_status"
            @test occursin("ALTER TABLE users", migration.up_sql)
            @test migration.down_sql == ""  # No down migration
            @test migration.filepath == filepath
        end

        @testset "Invalid migration filename" begin
            # Create a temporary file with invalid name
            invalid_file = joinpath(fixtures_dir, "invalid_migration.sql")
            write(invalid_file, "SELECT 1;")

            @test_throws ErrorException parse_migration_file(invalid_file)

            # Clean up
            rm(invalid_file)
        end
    end

    @testset "Migration Discovery" begin
        @testset "Discover all migrations in directory" begin
            migrations = discover_migrations(fixtures_dir)

            @test length(migrations) == 3
            @test migrations[1].version == "20250120100000"
            @test migrations[2].version == "20250120110000"
            @test migrations[3].version == "20250120120000"
        end

        @testset "Migrations are sorted by version" begin
            migrations = discover_migrations(fixtures_dir)

            for i in 1:(length(migrations) - 1)
                @test migrations[i].version < migrations[i+1].version
            end
        end

        @testset "Error on non-existent directory" begin
            @test_throws ErrorException discover_migrations("/nonexistent/path")
        end
    end

    @testset "Migration Checksum" begin
        @testset "Checksum is deterministic" begin
            sql = "CREATE TABLE users (id INTEGER PRIMARY KEY);"
            checksum1 = migration_checksum(sql)
            checksum2 = migration_checksum(sql)

            @test checksum1 == checksum2
        end

        @testset "Different SQL produces different checksum" begin
            sql1 = "CREATE TABLE users (id INTEGER PRIMARY KEY);"
            sql2 = "CREATE TABLE orders (id INTEGER PRIMARY KEY);"

            @test migration_checksum(sql1) != migration_checksum(sql2)
        end

        @testset "Whitespace changes affect checksum" begin
            sql1 = "CREATE TABLE users (id INTEGER PRIMARY KEY);"
            sql2 = "CREATE TABLE users  (id INTEGER PRIMARY KEY);"

            # Checksums should differ if whitespace differs
            @test migration_checksum(sql1) != migration_checksum(sql2)
        end
    end

    @testset "Migration Application" begin
        @testset "Apply single migration" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            migration = parse_migration_file(joinpath(fixtures_dir,
                                                      "20250120100000_create_users_table.sql"))
            apply_migration(db, dialect, migration)

            # Verify table was created
            query = execute_sql(db,
                                "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
                                [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test length(result) == 1
            @test result[1][1] == "users"

            # Verify migration was recorded
            query = execute_sql(db, "SELECT version, name, checksum FROM schema_migrations",
                                [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test length(result) == 1
            @test result[1][1] == "20250120100000"
            @test result[1][2] == "create_users_table"
            @test result[1][3] == migration.checksum
        end

        @testset "Apply migration with multiple statements" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # First apply users table
            migration1 = parse_migration_file(joinpath(fixtures_dir,
                                                       "20250120100000_create_users_table.sql"))
            apply_migration(db, dialect, migration1)

            # Then apply orders table (has multiple statements)
            migration2 = parse_migration_file(joinpath(fixtures_dir,
                                                       "20250120110000_create_orders_table.sql"))
            apply_migration(db, dialect, migration2)

            # Verify table was created
            query = execute_sql(db,
                                "SELECT name FROM sqlite_master WHERE type='table' AND name='orders'",
                                [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test length(result) == 1

            # Verify index was created
            query = execute_sql(db,
                                "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_orders_user_id'",
                                [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test length(result) == 1
        end

        @testset "Migration failure rolls back transaction" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # First create schema_migrations table by applying a valid migration
            valid_migration = parse_migration_file(joinpath(fixtures_dir,
                                                            "20250120100000_create_users_table.sql"))
            apply_migration(db, dialect, valid_migration)

            # Now try to apply invalid migration
            invalid_migration = Migration("20250120130000",
                                          "invalid_sql",
                                          "THIS IS INVALID SQL;",
                                          "",
                                          "/tmp/invalid.sql",
                                          migration_checksum("THIS IS INVALID SQL;"))

            @test_throws Exception apply_migration(db, dialect, invalid_migration)

            # Verify migration was NOT recorded (but schema_migrations table still exists)
            query = execute_sql(db,
                                "SELECT COUNT(*) FROM schema_migrations WHERE version='20250120130000'",
                                [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test result[1][1] == 0
        end
    end

    @testset "Batch Migration Application" begin
        @testset "Apply all pending migrations" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            applied = apply_migrations(db, dialect, fixtures_dir)

            @test length(applied) == 3
            @test applied[1].version == "20250120100000"
            @test applied[2].version == "20250120110000"
            @test applied[3].version == "20250120120000"

            # Verify all tables were created
            query = execute_sql(db,
                                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
                                [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            table_names = [row[1] for row in result]
            @test "users" in table_names
            @test "orders" in table_names
            @test "schema_migrations" in table_names
        end

        @testset "Re-applying migrations is idempotent" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # First application
            applied1 = apply_migrations(db, dialect, fixtures_dir)
            @test length(applied1) == 3

            # Second application should be no-op
            applied2 = apply_migrations(db, dialect, fixtures_dir)
            @test length(applied2) == 0

            # Verify migration count in database
            query = execute_sql(db, "SELECT COUNT(*) FROM schema_migrations", [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test result[1][1] == 3
        end

        @testset "Apply only pending migrations" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # Apply first migration manually
            migration1 = parse_migration_file(joinpath(fixtures_dir,
                                                       "20250120100000_create_users_table.sql"))
            apply_migration(db, dialect, migration1)

            # Apply_migrations should only apply the remaining 2
            applied = apply_migrations(db, dialect, fixtures_dir)
            @test length(applied) == 2
            @test applied[1].version == "20250120110000"
            @test applied[2].version == "20250120120000"
        end
    end

    @testset "Migration Status" begin
        @testset "Show all migrations with status" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # Apply first two migrations
            migration1 = parse_migration_file(joinpath(fixtures_dir,
                                                       "20250120100000_create_users_table.sql"))
            migration2 = parse_migration_file(joinpath(fixtures_dir,
                                                       "20250120110000_create_orders_table.sql"))
            apply_migration(db, dialect, migration1)
            apply_migration(db, dialect, migration2)

            # Get status
            status = migration_status(db, dialect, fixtures_dir)

            @test length(status) == 3

            # First two should be applied
            @test status[1].migration.version == "20250120100000"
            @test status[1].applied == true
            @test status[1].applied_at !== nothing

            @test status[2].migration.version == "20250120110000"
            @test status[2].applied == true
            @test status[2].applied_at !== nothing

            # Third should be pending
            @test status[3].migration.version == "20250120120000"
            @test status[3].applied == false
            @test status[3].applied_at === nothing
        end

        @testset "Empty database shows all pending" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            status = migration_status(db, dialect, fixtures_dir)

            @test length(status) == 3
            @test all(s -> !s.applied, status)
            @test all(s -> s.applied_at === nothing, status)
        end
    end

    @testset "Checksum Validation" begin
        @testset "Valid checksums pass validation" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            apply_migrations(db, dialect, fixtures_dir)

            @test validate_migration_checksums(db, dialect, fixtures_dir) == true
        end

        @testset "Modified migration fails validation" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # Apply migrations
            apply_migrations(db, dialect, fixtures_dir)

            # Modify a migration file (modify the UP section)
            original_file = joinpath(fixtures_dir, "20250120100000_create_users_table.sql")
            original_content = read(original_file, String)

            try
                # Write modified content - add comment in the UP section
                modified_content = replace(original_content,
                                           "CREATE TABLE users" => "-- MODIFIED\nCREATE TABLE users")
                write(original_file, modified_content)

                # Validation should fail
                @test validate_migration_checksums(db, dialect, fixtures_dir) == false

            finally
                # Restore original content
                write(original_file, original_content)
            end
        end

        @testset "Detect modified migration on apply" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # Apply migrations
            apply_migrations(db, dialect, fixtures_dir)

            # Modify a migration file (modify the UP section)
            original_file = joinpath(fixtures_dir, "20250120100000_create_users_table.sql")
            original_content = read(original_file, String)

            try
                # Write modified content - add comment in the UP section
                modified_content = replace(original_content,
                                           "CREATE TABLE users" => "-- MODIFIED\nCREATE TABLE users")
                write(original_file, modified_content)

                # Trying to apply again should throw error
                @test_throws ErrorException apply_migrations(db, dialect, fixtures_dir)

            finally
                # Restore original content
                write(original_file, original_content)
            end
        end
    end

    @testset "Generate Migration" begin
        @testset "Generate migration file" begin
            # Create temporary directory for test
            temp_dir = mktempdir()

            try
                filepath = generate_migration(temp_dir, "create products table")

                # Verify file was created
                @test isfile(filepath)

                # Verify filename format
                filename = basename(filepath)
                @test occursin(r"^\d{14}_create_products_table\.sql$", filename)

                # Verify content has UP/DOWN template
                content = read(filepath, String)
                @test occursin("-- UP", content)
                @test occursin("-- DOWN", content)

            finally
                # Clean up
                rm(temp_dir, recursive = true)
            end
        end

        @testset "Sanitize migration name" begin
            temp_dir = mktempdir()

            try
                filepath = generate_migration(temp_dir, "Create Products Table!!! @#\$")

                filename = basename(filepath)
                @test occursin("create_products_table", filename)
                @test !occursin("!", filename)
                @test !occursin("@", filename)

            finally
                rm(temp_dir, recursive = true)
            end
        end

        @testset "Create directory if not exists" begin
            temp_dir = mktempdir()
            migrations_dir = joinpath(temp_dir, "db", "migrations")

            try
                @test !isdir(migrations_dir)

                filepath = generate_migration(migrations_dir, "test_migration")

                @test isdir(migrations_dir)
                @test isfile(filepath)

            finally
                rm(temp_dir, recursive = true)
            end
        end
    end

    @testset "Schema Migrations Table" begin
        @testset "Table is created automatically" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # Apply a migration
            migration = parse_migration_file(joinpath(fixtures_dir,
                                                      "20250120100000_create_users_table.sql"))
            apply_migration(db, dialect, migration)

            # Verify schema_migrations table exists
            query = execute_sql(db,
                                "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations'",
                                [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test length(result) == 1

            # Verify schema
            query = execute_sql(db, "PRAGMA table_info(schema_migrations)", [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            column_names = [row[2] for row in result]
            @test "version" in column_names
            @test "name" in column_names
            @test "applied_at" in column_names
            @test "checksum" in column_names
        end

        @testset "Multiple calls to create_migrations_table are safe" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # Call multiple times - should not error
            SQLSketch.Extras.create_migrations_table(db, dialect)
            SQLSketch.Extras.create_migrations_table(db, dialect)
            SQLSketch.Extras.create_migrations_table(db, dialect)

            # Verify table exists only once
            query = execute_sql(db,
                                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_migrations'",
                                [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test result[1][1] == 1
        end
    end

    @testset "Integration with Transactions" begin
        @testset "Migration runs within transaction" begin
            db = connect(SQLiteDriver(), ":memory:")
            dialect = SQLiteDialect()

            # Apply migration that creates users table
            migration = parse_migration_file(joinpath(fixtures_dir,
                                                      "20250120100000_create_users_table.sql"))
            apply_migration(db, dialect, migration)

            # Verify we can use the table
            q = insert_into(:users, [:email, :name]) |>
                insert_values([[literal("test@example.com"), literal("Test User")]])
            execute(db, dialect, q)

            query = execute_sql(db, "SELECT email FROM users", [])
            result = [[row[i] for i in 1:length(propertynames(row))] for row in query]
            @test length(result) == 1
            @test result[1][1] == "test@example.com"
        end
    end
end
