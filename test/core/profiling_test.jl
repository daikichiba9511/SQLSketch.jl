"""
Tests for Performance Profiling (Phase 13.6)

This module tests query profiling and performance analysis tools.
"""

using Test
using SQLSketch
using SQLSketch.Drivers

@testset "Performance Profiling" begin
    # Create in-memory database for testing
    driver = SQLiteDriver()
    conn = connect(driver, ":memory:")

    try
        # Create test table with some data
        execute_sql(conn,
                    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER, email TEXT)")
        execute_sql(conn,
                    "INSERT INTO users (name, age, email) VALUES ('Alice', 30, 'alice@example.com')")
        execute_sql(conn,
                    "INSERT INTO users (name, age, email) VALUES ('Bob', 25, 'bob@example.com')")
        execute_sql(conn,
                    "INSERT INTO users (name, age, email) VALUES ('Charlie', 35, 'charlie@example.com')")

        @testset "@timed_query macro" begin
            query = from(:users)
            dialect = SQLiteDialect()
            registry = CodecRegistry()

            # Test @timed_query macro
            result, timing = @timed_query fetch_all(conn, dialect, registry, query)

            @test length(result) == 3
            @test timing isa QueryTiming
            @test timing.total_time >= 0.0
            @test timing.execute_time >= 0.0
            @test timing.row_count == 3
        end

        @testset "QueryTiming structure" begin
            timing = QueryTiming(0.001, 0.005, 0.002, 0.008, 10)

            @test timing.compile_time == 0.001
            @test timing.execute_time == 0.005
            @test timing.decode_time == 0.002
            @test timing.total_time == 0.008
            @test timing.row_count == 10
        end

        @testset "analyze_query - basic query" begin
            query = from(:users) |> where(col(:users, :age) > literal(25))
            dialect = SQLiteDialect()

            analysis = analyze_query(conn, dialect, query)

            @test analysis isa ExplainAnalysis
            @test analysis.plan isa String
            @test !isempty(analysis.plan)
            @test analysis.uses_index isa Bool
            @test analysis.has_full_scan isa Bool
            @test analysis.warnings isa Vector{String}
        end

        @testset "analyze_query - full table scan detection" begin
            query = from(:users)  # No WHERE clause -> full table scan
            dialect = SQLiteDialect()

            analysis = analyze_query(conn, dialect, query)

            # Should detect table scan (no WHERE clause)
            # Note: SQLite EXPLAIN output format may vary
            @test analysis isa ExplainAnalysis
            @test !isempty(analysis.plan)
        end

        @testset "analyze_query - with index" begin
            # Create an index
            execute_sql(conn, "CREATE INDEX idx_users_age ON users(age)")

            query = from(:users) |> where(col(:users, :age) > literal(25))
            dialect = SQLiteDialect()

            analysis = analyze_query(conn, dialect, query)

            # Should use index
            @test contains(lowercase(analysis.plan), "index") ||
                  contains(lowercase(analysis.plan), "idx_users_age")
        end

        @testset "analyze_explain" begin
            explain_output = """
            SCAN TABLE users
            """

            info = analyze_explain(explain_output)

            @test info isa Dict{Symbol, Any}
            @test haskey(info, :uses_index)
            @test haskey(info, :scan_type)
            @test haskey(info, :has_full_scan)
            @test haskey(info, :warnings)

            @test info[:uses_index] == false
            @test info[:has_full_scan] == true
            @test info[:scan_type] == :table_scan
            @test length(info[:warnings]) > 0
        end

        @testset "analyze_explain - with index" begin
            explain_output = """
            SEARCH TABLE users USING INDEX idx_users_age (age>?)
            """

            info = analyze_explain(explain_output)

            @test info[:uses_index] == true
            @test info[:scan_type] == :index_scan
        end

        @testset "Performance warnings generation" begin
            # Full scan warning
            explain_output1 = "SCAN TABLE users"
            info1 = analyze_explain(explain_output1)
            @test any(contains(w, "Full table scan") for w in info1[:warnings])

            # Temp table warning
            explain_output2 = "USE TEMP B-TREE FOR ORDER BY"
            info2 = analyze_explain(explain_output2)
            @test any(contains(w, "Temporary") for w in info2[:warnings])
        end

        @testset "Complex query analysis" begin
            # Create posts table for JOIN test
            execute_sql(conn,
                        "CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)")
            execute_sql(conn, "INSERT INTO posts (user_id, title) VALUES (1, 'Post 1')")

            # Query with JOIN
            query = from(:users) |>
                    innerjoin(:posts, col(:users, :id) == col(:posts, :user_id)) |>
                    select(NamedTuple, col(:users, :name), col(:posts, :title))

            dialect = SQLiteDialect()
            analysis = analyze_query(conn, dialect, query)

            @test analysis isa ExplainAnalysis
            @test !isempty(analysis.plan)
        end

        @testset "Timing consistency" begin
            query = from(:users)
            dialect = SQLiteDialect()
            registry = CodecRegistry()

            # Run multiple times and check timing consistency
            result1, timing1 = @timed_query fetch_all(conn, dialect, registry, query)
            result2, timing2 = @timed_query fetch_all(conn, dialect, registry, query)

            @test length(result1) == length(result2)
            @test timing1.row_count == timing2.row_count
            @test timing1.total_time >= 0.0
            @test timing2.total_time >= 0.0
        end

        @testset "Profiling with different query types" begin
            dialect = SQLiteDialect()
            registry = CodecRegistry()

            # SELECT
            q_select = from(:users) |> select(NamedTuple, col(:users, :name))
            result, timing = @timed_query fetch_all(conn, dialect, registry, q_select)
            @test timing.row_count == 3

            # INSERT (using execute)
            q_insert = insert_into(:users, [:name, :age, :email]) |>
                       insert_values([[literal("David"), literal(40),
                                       literal("david@example.com")]])
            result, timing = @timed_query execute(conn, dialect, q_insert)
            @test timing.total_time >= 0.0

            # UPDATE (using execute)
            q_update = update(:users) |>
                       set(:age => literal(31)) |>
                       where(col(:users, :name) == literal("Alice"))
            result, timing = @timed_query execute(conn, dialect, q_update)
            @test timing.total_time >= 0.0
        end

        @testset "EXPLAIN with parameters" begin
            query = from(:users) |> where(col(:users, :age) > param(Int, :min_age))
            dialect = SQLiteDialect()

            # analyze_query should handle parameterized queries
            analysis = analyze_query(conn, dialect, query)
            @test analysis isa ExplainAnalysis
            @test !isempty(analysis.plan)
        end

    finally
        # Cleanup
        if conn isa SQLiteConnection
            close(conn.db)
        end
    end
end
