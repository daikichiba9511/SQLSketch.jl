"""
SQLite Driver Tests

Integration tests for SQLite driver implementation.
These tests use an in-memory SQLite database for fast, isolated testing.
"""

using Test
using SQLSketch
using SQLSketch.Core: Driver, Connection, connect, execute
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

        # Execute CREATE TABLE
        result = execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")

        # Verify table exists by querying sqlite_master
        result = execute(db,
                         "SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
        rows = Tables.rowtable(result)
        @test length(rows) == 1
        @test rows[1].name == "users"

        close(db)
    end

    @testset "DML Execution - INSERT" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")

        # Setup
        execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")

        # Execute INSERT without parameters
        execute(db, "INSERT INTO users (email) VALUES ('test1@example.com')")

        # Verify insertion
        result = execute(db, "SELECT COUNT(*) as count FROM users")
        rows = Tables.rowtable(result)
        @test rows[1].count == 1

        close(db)
    end

    @testset "Parameter Binding - Single Parameter" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")

        # Setup
        execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")

        # Execute INSERT with parameter
        execute(db, "INSERT INTO users (email) VALUES (?)", ["param@example.com"])

        # Verify with parameter binding in SELECT
        result = execute(db, "SELECT email FROM users WHERE email = ?",
                         ["param@example.com"])
        rows = Tables.rowtable(result)
        @test length(rows) == 1
        @test rows[1].email == "param@example.com"

        close(db)
    end

    @testset "Parameter Binding - Multiple Parameters" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")

        # Setup
        execute(db,
                "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT, active INTEGER)")

        # Execute INSERT with multiple parameters
        execute(db, "INSERT INTO users (email, active) VALUES (?, ?)",
                ["multi@example.com", 1])
        execute(db, "INSERT INTO users (email, active) VALUES (?, ?)",
                ["inactive@example.com", 0])

        # Query with multiple parameters
        result = execute(db, "SELECT email FROM users WHERE active = ?", [1])
        rows = Tables.rowtable(result)
        @test length(rows) == 1
        @test rows[1].email == "multi@example.com"

        close(db)
    end

    @testset "Query Execution - SELECT" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")

        # Setup
        execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")
        execute(db, "INSERT INTO users (email) VALUES ('user1@example.com')")
        execute(db, "INSERT INTO users (email) VALUES ('user2@example.com')")
        execute(db, "INSERT INTO users (email) VALUES ('user3@example.com')")

        # Execute SELECT
        result = execute(db, "SELECT * FROM users ORDER BY id")
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

        # Setup
        execute(db,
                "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT, active INTEGER)")
        execute(db, "INSERT INTO users (email, active) VALUES ('active1@example.com', 1)")
        execute(db, "INSERT INTO users (email, active) VALUES ('inactive@example.com', 0)")
        execute(db, "INSERT INTO users (email, active) VALUES ('active2@example.com', 1)")

        # Execute filtered SELECT
        result = execute(db, "SELECT email FROM users WHERE active = 1 ORDER BY email")
        rows = Tables.rowtable(result)

        @test length(rows) == 2
        @test rows[1].email == "active1@example.com"
        @test rows[2].email == "active2@example.com"

        close(db)
    end

    @testset "Query Execution - Empty Result" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")

        # Setup
        execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")

        # Execute query that returns no rows
        result = execute(db, "SELECT * FROM users WHERE id = 999")
        rows = Tables.rowtable(result)

        @test length(rows) == 0

        close(db)
    end

    @testset "Connection Cleanup" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")

        execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")
        execute(db, "INSERT INTO users (email) VALUES ('test@example.com')")

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

        # Each connection should have its own database
        execute(db1, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")
        execute(db1, "INSERT INTO users (email) VALUES ('db1@example.com')")

        execute(db2, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")
        execute(db2, "INSERT INTO users (email) VALUES ('db2@example.com')")

        # Verify isolation
        result1 = execute(db1, "SELECT email FROM users")
        rows1 = Tables.rowtable(result1)
        @test length(rows1) == 1
        @test rows1[1].email == "db1@example.com"

        result2 = execute(db2, "SELECT email FROM users")
        rows2 = Tables.rowtable(result2)
        @test length(rows2) == 1
        @test rows2[1].email == "db2@example.com"

        close(db1)
        close(db2)
    end

    @testset "Complex Query - JOIN" begin
        driver = SQLiteDriver()
        db = connect(driver, ":memory:")

        # Setup tables
        execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")
        execute(db,
                "CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)")

        execute(db, "INSERT INTO users (email) VALUES ('user1@example.com')")
        execute(db, "INSERT INTO users (email) VALUES ('user2@example.com')")

        execute(db, "INSERT INTO posts (user_id, title) VALUES (1, 'Post 1')")
        execute(db, "INSERT INTO posts (user_id, title) VALUES (1, 'Post 2')")
        execute(db, "INSERT INTO posts (user_id, title) VALUES (2, 'Post 3')")

        # Execute JOIN query
        sql = """
        SELECT users.email, posts.title
        FROM users
        INNER JOIN posts ON users.id = posts.user_id
        WHERE users.id = ?
        ORDER BY posts.id
        """
        result = execute(db, sql, [1])
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

        # Create table with various types
        execute(db, """
            CREATE TABLE data (
                id INTEGER PRIMARY KEY,
                int_val INTEGER,
                real_val REAL,
                text_val TEXT,
                blob_val BLOB
            )
        """)

        # Insert data with various types
        execute(db, "INSERT INTO data (int_val, real_val, text_val) VALUES (?, ?, ?)",
                [42, 3.14, "hello"])

        # Query back
        result = execute(db, "SELECT * FROM data WHERE id = 1")
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

        # Create table
        execute(db, "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)")

        # Insert NULL value
        execute(db, "INSERT INTO users (email) VALUES (NULL)")
        execute(db, "INSERT INTO users (email) VALUES ('test@example.com')")

        # Query NULL values
        result = execute(db, "SELECT * FROM users WHERE email IS NULL")
        rows = Tables.rowtable(result)

        @test length(rows) == 1
        @test ismissing(rows[1].email)

        close(db)
    end
end
