"""
SQLite Driver Tests

Integration tests for SQLite driver implementation.
These tests use an in-memory SQLite database for fast, isolated testing.
"""

using Test
using SQLSketch
using SQLSketch.Core
using SQLSketch.Core: create_table, add_column
using SQLSketch.Core: insert_into, insert_values, literal
using SQLSketch.Drivers: SQLiteDriver, SQLiteConnection
using SQLite
import Tables

@testset "SQLite Driver Tests" begin
    @testset "Driver Construction" begin
        driver = SQLiteDriver()
        @test driver isa Driver
        @test driver isa SQLiteDriver
    end

    @testset "In-Memory Connection" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")

        @test db isa Connection
        @test db isa SQLiteConnection
        @test db.db isa SQLite.DB

        close(db)
    end

    @testset "File-Based Connection" begin
        # Use temporary file for testing
        tmpfile = tempname() * ".sqlite"

        try
            driver = SQLiteDriver()
            db = connect(driver, tmpfile)

            @test db isa SQLiteConnection
            @test isfile(tmpfile)

            close(db)
        finally
            # Cleanup
            if isfile(tmpfile)
                rm(tmpfile)
            end
        end
    end

    @testset "DDL Execution - CREATE TABLE" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Execute CREATE TABLE
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text)
        execute(db, dialect, ddl)

        # Verify table exists by querying sqlite_master
        result = execute_sql(db,
                             "SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
        rows = Tables.rowtable(result)
        @test length(rows) == 1
        @test rows[1].name == "users"

        close(db)
    end

    @testset "DML Execution - INSERT" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Setup
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text)
        execute(db, dialect, ddl)

        # Execute INSERT without parameters
        q = insert_into(:users, [:email]) |>
            insert_values([[literal("test1@example.com")]])
        execute(db, dialect, q)

        # Verify insertion
        result = execute_sql(db, "SELECT COUNT(*) as count FROM users")
        rows = Tables.rowtable(result)
        @test rows[1].count == 1

        close(db)
    end

    @testset "Parameter Binding - Single Parameter" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Setup
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text)
        execute(db, dialect, ddl)

        # Execute INSERT with parameter
        q = insert_into(:users, [:email]) |>
            insert_values([[literal("param@example.com")]])
        execute(db, dialect, q)

        # Verify with parameter binding in SELECT
        result = execute_sql(db, "SELECT email FROM users WHERE email = ?",
                             ["param@example.com"])
        rows = Tables.rowtable(result)
        @test length(rows) == 1
        @test rows[1].email == "param@example.com"

        close(db)
    end

    @testset "Parameter Binding - Multiple Parameters" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Setup
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text) |>
              add_column(:active, :integer)
        execute(db, dialect, ddl)

        # Execute INSERT with multiple parameters
        q1 = insert_into(:users, [:email, :active]) |>
             insert_values([[literal("multi@example.com"), literal(1)]])
        execute(db, dialect, q1)

        q2 = insert_into(:users, [:email, :active]) |>
             insert_values([[literal("inactive@example.com"), literal(0)]])
        execute(db, dialect, q2)

        # Query with multiple parameters
        result = execute_sql(db, "SELECT email FROM users WHERE active = ?", [1])
        rows = Tables.rowtable(result)
        @test length(rows) == 1
        @test rows[1].email == "multi@example.com"

        close(db)
    end

    @testset "Query Execution - SELECT" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Setup
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text)
        execute(db, dialect, ddl)

        q1 = insert_into(:users, [:email]) |>
             insert_values([[literal("user1@example.com")]])
        execute(db, dialect, q1)
        q2 = insert_into(:users, [:email]) |>
             insert_values([[literal("user2@example.com")]])
        execute(db, dialect, q2)
        q3 = insert_into(:users, [:email]) |>
             insert_values([[literal("user3@example.com")]])
        execute(db, dialect, q3)

        # Execute SELECT
        result = execute_sql(db, "SELECT * FROM users ORDER BY id")
        rows = Tables.rowtable(result)

        @test length(rows) == 3
        @test rows[1].id == 1
        @test rows[1].email == "user1@example.com"
        @test rows[2].id == 2
        @test rows[2].email == "user2@example.com"
        @test rows[3].id == 3
        @test rows[3].email == "user3@example.com"

        close(db)
    end

    @testset "Query Execution - SELECT with WHERE" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Setup
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text) |>
              add_column(:active, :integer)
        execute(db, dialect, ddl)

        q1 = insert_into(:users, [:email, :active]) |>
             insert_values([[literal("active1@example.com"), literal(1)]])
        execute(db, dialect, q1)
        q2 = insert_into(:users, [:email, :active]) |>
             insert_values([[literal("inactive@example.com"), literal(0)]])
        execute(db, dialect, q2)
        q3 = insert_into(:users, [:email, :active]) |>
             insert_values([[literal("active2@example.com"), literal(1)]])
        execute(db, dialect, q3)

        # Execute filtered SELECT
        result = execute_sql(db, "SELECT email FROM users WHERE active = 1 ORDER BY email")
        rows = Tables.rowtable(result)

        @test length(rows) == 2
        @test rows[1].email == "active1@example.com"
        @test rows[2].email == "active2@example.com"

        close(db)
    end

    @testset "Query Execution - Empty Result" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Setup
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text)
        execute(db, dialect, ddl)

        # Execute query that returns no rows
        result = execute_sql(db, "SELECT * FROM users WHERE id = 999")
        rows = Tables.rowtable(result)

        @test length(rows) == 0

        close(db)
    end

    @testset "Connection Cleanup" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text)
        execute(db, dialect, ddl)

        q = insert_into(:users, [:email]) |> insert_values([[literal("test@example.com")]])
        execute(db, dialect, q)

        # Close connection
        close(db)

        # After closing, the connection should not be usable
        # (This is implicit - we just verify close doesn't error)
        @test true
    end

    @testset "Multiple Connections" begin
        driver = SQLiteDriver()
        db1 = connect(driver, ":memory:")
        db2 = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Each connection should have its own database
        ddl1 = create_table(:users) |>
               add_column(:id, :integer, primary_key = true) |>
               add_column(:email, :text)
        execute(db1, dialect, ddl1)

        q1 = insert_into(:users, [:email]) |> insert_values([[literal("db1@example.com")]])
        execute(db1, dialect, q1)

        ddl2 = create_table(:users) |>
               add_column(:id, :integer, primary_key = true) |>
               add_column(:email, :text)
        execute(db2, dialect, ddl2)

        q2 = insert_into(:users, [:email]) |> insert_values([[literal("db2@example.com")]])
        execute(db2, dialect, q2)

        # Verify isolation
        result1 = execute_sql(db1, "SELECT email FROM users")
        rows1 = Tables.rowtable(result1)
        @test length(rows1) == 1
        @test rows1[1].email == "db1@example.com"

        result2 = execute_sql(db2, "SELECT email FROM users")
        rows2 = Tables.rowtable(result2)
        @test length(rows2) == 1
        @test rows2[1].email == "db2@example.com"

        close(db1)
        close(db2)
    end

    @testset "Complex Query - JOIN" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Setup tables
        users_ddl = create_table(:users) |>
                    add_column(:id, :integer, primary_key = true) |>
                    add_column(:email, :text)
        execute(db, dialect, users_ddl)

        posts_ddl = create_table(:posts) |>
                    add_column(:id, :integer, primary_key = true) |>
                    add_column(:user_id, :integer) |>
                    add_column(:title, :text)
        execute(db, dialect, posts_ddl)

        q1 = insert_into(:users, [:email]) |>
             insert_values([[literal("user1@example.com")]])
        execute(db, dialect, q1)
        q2 = insert_into(:users, [:email]) |>
             insert_values([[literal("user2@example.com")]])
        execute(db, dialect, q2)

        q3 = insert_into(:posts, [:user_id, :title]) |>
             insert_values([[literal(1), literal("Post 1")]])
        execute(db, dialect, q3)
        q4 = insert_into(:posts, [:user_id, :title]) |>
             insert_values([[literal(1), literal("Post 2")]])
        execute(db, dialect, q4)
        q5 = insert_into(:posts, [:user_id, :title]) |>
             insert_values([[literal(2), literal("Post 3")]])
        execute(db, dialect, q5)

        # Execute JOIN query
        sql = """
        SELECT users.email, posts.title
        FROM users
        INNER JOIN posts ON users.id = posts.user_id
        WHERE users.id = ?
        ORDER BY posts.id
        """
        result = execute_sql(db, sql, [1])
        rows = Tables.rowtable(result)

        @test length(rows) == 2
        @test rows[1].email == "user1@example.com"
        @test rows[1].title == "Post 1"
        @test rows[2].email == "user1@example.com"
        @test rows[2].title == "Post 2"

        close(db)
    end

    @testset "Type Handling - Various Types" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Create table with various types
        ddl = create_table(:data) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:int_val, :integer) |>
              add_column(:real_val, :real) |>
              add_column(:text_val, :text) |>
              add_column(:blob_val, :blob)
        execute(db, dialect, ddl)

        # Insert data with various types
        q = insert_into(:data, [:int_val, :real_val, :text_val]) |>
            insert_values([[literal(42), literal(3.14), literal("hello")]])
        execute(db, dialect, q)

        # Query back
        result = execute_sql(db, "SELECT * FROM data WHERE id = 1")
        rows = Tables.rowtable(result)

        @test length(rows) == 1
        @test rows[1].int_val == 42
        @test rows[1].real_val ≈ 3.14
        @test rows[1].text_val == "hello"

        close(db)
    end

    @testset "NULL Handling" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")
        dialect = SQLiteDialect()

        # Create table
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text)
        execute(db, dialect, ddl)

        # Insert NULL value
        q1 = insert_into(:users, [:email]) |> insert_values([[literal(nothing)]])
        execute(db, dialect, q1)
        q2 = insert_into(:users, [:email]) |> insert_values([[literal("test@example.com")]])
        execute(db, dialect, q2)

        # Query NULL values
        result = execute_sql(db, "SELECT * FROM users WHERE email IS NULL")
        rows = Tables.rowtable(result)

        @test length(rows) == 1
        @test ismissing(rows[1].email)

        close(db)
    end
end
