"""
End-to-End Integration Tests

This test suite verifies the complete query execution pipeline:
  Query AST → Dialect → SQL → Driver → Execution → CodecRegistry → Results

Tests cover:
- Basic query execution (all, one, maybeone)
- Parameter binding
- Type conversion
- Error handling
- Observability (sql, explain)
"""

using Test
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers
using Dates
using UUIDs

# Import execution functions with new names
import SQLSketch.Core: fetch_all, fetch_one, fetch_maybe, sql, explain, execute_dml

@testset "End-to-End Integration Tests" begin
    # Setup: Create in-memory database
    driver = SQLiteDriver()
    db = connect(driver, ":memory:")
    dialect = SQLiteDialect()
    registry = CodecRegistry()

    # Create test tables
    execute(db, """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            age INTEGER,
            is_active INTEGER DEFAULT 1,
            created_at TEXT
        )
    """, [])

    execute(db, """
        CREATE TABLE posts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            content TEXT,
            published INTEGER DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """, [])

    # Insert test data
    execute(db, "INSERT INTO users (name, email, age, is_active) VALUES (?, ?, ?, ?)",
            ["Alice", "alice@example.com", 30, 1])
    execute(db, "INSERT INTO users (name, email, age, is_active) VALUES (?, ?, ?, ?)",
            ["Bob", "bob@example.com", 25, 1])
    execute(db, "INSERT INTO users (name, email, age, is_active) VALUES (?, ?, ?, ?)",
            ["Charlie", "charlie@example.com", 35, 0])

    execute(db, "INSERT INTO posts (user_id, title, content, published) VALUES (?, ?, ?, ?)",
            [1, "First Post", "Hello World", 1])
    execute(db, "INSERT INTO posts (user_id, title, content, published) VALUES (?, ?, ?, ?)",
            [1, "Second Post", "More content", 0])
    execute(db, "INSERT INTO posts (user_id, title, content, published) VALUES (?, ?, ?, ?)",
            [2, "Bob's Post", "Bob's content", 1])

    @testset "Basic Query Execution - fetch_all()" begin
        # Simple SELECT all users
        q = from(:users) |>
            select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email))

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 3
        @test results[1].name == "Alice"
        @test results[1].email == "alice@example.com"
        @test results[2].name == "Bob"
        @test results[3].name == "Charlie"
    end

    @testset "Query with WHERE clause" begin
        # Filter by age
        q = from(:users) |>
            where(col(:users, :age) > literal(26)) |>
            select(NamedTuple, col(:users, :name), col(:users, :age))

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 2  # Alice (30), Charlie (35)
        @test Base.all(r -> r.age > 26, results)
    end

    @testset "Query with ORDER BY" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :name), col(:users, :age)) |>
            order_by(col(:users, :age); desc=true)

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 3
        @test results[1].name == "Charlie"  # age 35
        @test results[2].name == "Alice"    # age 30
        @test results[3].name == "Bob"      # age 25
    end

    @testset "Query with LIMIT" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :name)) |>
            order_by(col(:users, :id)) |>
            limit(2)

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 2
        @test results[1].name == "Alice"
        @test results[2].name == "Bob"
    end

    @testset "Query with OFFSET" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :name)) |>
            order_by(col(:users, :id)) |>
            limit(2) |>
            offset(1)

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 2
        @test results[1].name == "Bob"
        @test results[2].name == "Charlie"
    end

    @testset "Query with DISTINCT" begin
        # All users have different ages, so DISTINCT should not change count
        q = from(:users) |>
            select(NamedTuple, col(:users, :age)) |>
            distinct

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 3
    end

    @testset "Query with JOIN" begin
        q = from(:users) |>
            join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
            select(NamedTuple,
                   col(:users, :name),
                   col(:posts, :title))

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 3  # Alice has 2 posts, Bob has 1 post
        # Note: Charlie has no posts, so won't appear in inner join
    end

    @testset "fetch_one() - Success" begin
        # Get exactly one user by email
        q = from(:users) |>
            where(col(:users, :email) == param(String, :email)) |>
            select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email))

        user = fetch_one(db, dialect, registry, q, (email="alice@example.com",))

        @test user.name == "Alice"
        @test user.email == "alice@example.com"
    end

    @testset "fetch_one() - Error on zero rows" begin
        q = from(:users) |>
            where(col(:users, :email) == param(String, :email)) |>
            select(NamedTuple, col(:users, :id), col(:users, :name))

        @test_throws ErrorException fetch_one(db, dialect, registry, q,
                                              (email="nonexistent@example.com",))
    end

    @testset "fetch_one() - Error on multiple rows" begin
        # Query that returns multiple users
        q = from(:users) |>
            where(col(:users, :age) > literal(20)) |>
            select(NamedTuple, col(:users, :name))

        @test_throws ErrorException fetch_one(db, dialect, registry, q)
    end

    @testset "fetch_maybe() - Returns value" begin
        q = from(:users) |>
            where(col(:users, :email) == param(String, :email)) |>
            select(NamedTuple, col(:users, :name), col(:users, :email))

        user = fetch_maybe(db, dialect, registry, q, (email="bob@example.com",))

        @test user !== nothing
        @test user.name == "Bob"
    end

    @testset "fetch_maybe() - Returns nothing" begin
        q = from(:users) |>
            where(col(:users, :email) == param(String, :email)) |>
            select(NamedTuple, col(:users, :name))

        user = fetch_maybe(db, dialect, registry, q, (email="nonexistent@example.com",))

        @test user === nothing
    end

    @testset "fetch_maybe() - Error on multiple rows" begin
        # Query that returns multiple users
        q = from(:users) |>
            where(col(:users, :age) > literal(20)) |>
            select(NamedTuple, col(:users, :name))

        @test_throws ErrorException fetch_maybe(db, dialect, registry, q)
    end

    @testset "Parameter Binding - Single parameter" begin
        q = from(:users) |>
            where(col(:users, :age) == param(Int, :min_age)) |>
            select(NamedTuple, col(:users, :name), col(:users, :age))

        results = fetch_all(db, dialect, registry, q, (min_age=30,))

        @test length(results) == 1  # Alice (30)
        @test Base.all(r -> r.age == 30, results)
    end

    @testset "Parameter Binding - Multiple parameters" begin
        q = from(:users) |>
            where((col(:users, :age) >= param(Int, :min_age)) &
                  (col(:users, :age) <= param(Int, :max_age))) |>
            select(NamedTuple, col(:users, :name), col(:users, :age))

        results = fetch_all(db, dialect, registry, q, (min_age=25, max_age=30))

        @test length(results) == 2  # Bob (25), Alice (30)
    end

    @testset "Parameter Binding - Missing parameter error" begin
        q = from(:users) |>
            where(col(:users, :age) == param(Int, :min_age)) |>
            select(NamedTuple, col(:users, :name))

        # Missing required parameter
        @test_throws ErrorException fetch_all(db, dialect, registry, q, NamedTuple())
    end

    @testset "Type Conversion - Integers" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :id), col(:users, :age))

        results = fetch_all(db, dialect, registry, q)

        @test Base.all(r -> r.id isa Integer, results)
        @test Base.all(r -> r.age isa Integer, results)
    end

    @testset "Type Conversion - Strings" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :name), col(:users, :email))

        results = fetch_all(db, dialect, registry, q)

        @test Base.all(r -> r.name isa String, results)
        @test Base.all(r -> r.email isa String, results)
    end

    @testset "Type Conversion - Booleans (SQLite integers)" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :is_active))

        results = fetch_all(db, dialect, registry, q)

        # SQLite stores booleans as integers (0 or 1)
        @test Base.all(r -> r.is_active in [0, 1], results)
    end

    @testset "Type Conversion to Struct" begin
        struct User
            id::Int
            name::String
            email::String
        end

        q = from(:users) |>
            where(col(:users, :id) == param(Int, :id)) |>
            select(User, col(:users, :id), col(:users, :name), col(:users, :email))

        user = fetch_one(db, dialect, registry, q, (id=1,))

        @test user isa User
        @test user.id == 1
        @test user.name == "Alice"
        @test user.email == "alice@example.com"
    end

    @testset "sql() - SQL inspection" begin
        q = from(:users) |>
            where(col(:users, :age) > param(Int, :min_age)) |>
            select(NamedTuple, col(:users, :name), col(:users, :email))

        sql_str = sql(dialect, q)

        @test occursin("SELECT", sql_str)
        @test occursin("FROM", sql_str)
        @test occursin("WHERE", sql_str)
        @test occursin("`users`", sql_str)
        @test occursin("`name`", sql_str)
        @test occursin("`email`", sql_str)
        @test occursin("`age`", sql_str)
        @test occursin("?", sql_str)  # Parameter placeholder
    end

    @testset "explain() - Query plan" begin
        q = from(:users) |>
            where(col(:users, :age) > literal(25)) |>
            select(NamedTuple, col(:users, :name))

        plan = explain(db, dialect, q)

        @test plan isa String
        @test !isempty(plan)
        # EXPLAIN output should contain query plan information
    end

    @testset "Complex Query - Multiple operations" begin
        # Complex query: JOIN, WHERE, ORDER BY, LIMIT
        q = from(:users) |>
            join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
            where(col(:posts, :published) == literal(1)) |>
            select(NamedTuple,
                   col(:users, :name),
                   col(:posts, :title)) |>
            order_by(col(:posts, :id)) |>
            limit(2)

        results = fetch_all(db, dialect, registry, q)

        @test length(results) <= 2
        @test Base.all(r -> haskey(r, :name) && haskey(r, :title), results)
    end

    @testset "Empty Result Set" begin
        q = from(:users) |>
            where(col(:users, :age) > literal(100)) |>
            select(NamedTuple, col(:users, :name))

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 0
        @test results isa Vector
    end

    # DML Operations Tests
    @testset "DML Operations" begin
        # Setup: Create a test table for DML operations
        execute(db, "CREATE TABLE dml_test (id INTEGER PRIMARY KEY, name TEXT, value INTEGER)", [])

        @testset "INSERT with literals" begin
            q = insert_into(:dml_test, [:name, :value]) |>
                values([[literal("test1"), literal(100)]])

            execute_dml(db, dialect, q)

            # Verify insertion
            verify_q = from(:dml_test) |>
                where(col(:dml_test, :name) == literal("test1")) |>
                select(NamedTuple, col(:dml_test, :name), col(:dml_test, :value))

            results = fetch_all(db, dialect, registry, verify_q)
            @test length(results) == 1
            @test results[1][:name] == "test1"
            @test results[1][:value] == 100
        end

        @testset "INSERT with parameters" begin
            q = insert_into(:dml_test, [:name, :value]) |>
                values([[param(String, :name), param(Int, :value)]])

            execute_dml(db, dialect, q, (name="test2", value=200))

            # Verify insertion
            verify_q = from(:dml_test) |>
                where(col(:dml_test, :name) == param(String, :name)) |>
                select(NamedTuple, col(:dml_test, :name), col(:dml_test, :value))

            results = fetch_all(db, dialect, registry, verify_q, (name="test2",))
            @test length(results) == 1
            @test results[1][:value] == 200
        end

        @testset "INSERT multiple rows" begin
            q = insert_into(:dml_test, [:name, :value]) |>
                values([
                    [literal("test3"), literal(300)],
                    [literal("test4"), literal(400)]
                ])

            execute_dml(db, dialect, q)

            # Verify insertions
            verify_q = from(:dml_test) |>
                where(col(:dml_test, :value) >= literal(300)) |>
                select(NamedTuple, col(:dml_test, :name), col(:dml_test, :value))

            results = fetch_all(db, dialect, registry, verify_q)
            @test length(results) == 2
        end

        @testset "UPDATE with WHERE" begin
            q = update(:dml_test) |>
                set(:value => param(Int, :new_value)) |>
                where(col(:dml_test, :name) == param(String, :name))

            execute_dml(db, dialect, q, (new_value=999, name="test1"))

            # Verify update
            verify_q = from(:dml_test) |>
                where(col(:dml_test, :name) == literal("test1")) |>
                select(NamedTuple, col(:dml_test, :value))

            results = fetch_all(db, dialect, registry, verify_q)
            @test length(results) == 1
            @test results[1][:value] == 999
        end

        @testset "DELETE with WHERE" begin
            q = delete_from(:dml_test) |>
                where(col(:dml_test, :name) == param(String, :name))

            execute_dml(db, dialect, q, (name="test2",))

            # Verify deletion
            verify_q = from(:dml_test) |>
                where(col(:dml_test, :name) == literal("test2")) |>
                select(NamedTuple, col(:dml_test, :name))

            results = fetch_all(db, dialect, registry, verify_q)
            @test length(results) == 0
        end

        @testset "DELETE with complex WHERE" begin
            q = delete_from(:dml_test) |>
                where(col(:dml_test, :value) < literal(500))

            execute_dml(db, dialect, q)

            # Verify remaining rows
            verify_q = from(:dml_test) |> select(NamedTuple, col(:dml_test, :name))
            results = fetch_all(db, dialect, registry, verify_q)

            # Only test1 (999) should remain
            @test length(results) == 1
            @test results[1][:name] == "test1"
        end

        # Cleanup DML test table
        execute(db, "DROP TABLE dml_test", [])
    end

    # Cleanup
    close(db)
end
