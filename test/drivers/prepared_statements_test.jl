# Tests for prepared statement support in drivers

using Test
using SQLSketch
using SQLite

# Access internal APIs for testing
using SQLSketch.Core: prepare_statement, execute_prepared, supports_prepared_statements

@testset "Prepared Statements - SQLite" begin
    @testset "Driver support detection" begin
        driver = SQLiteDriver()
        @test supports_prepared_statements(driver) == true
    end

    @testset "Prepare and execute" begin
        driver = SQLiteDriver()
        conn = connect(driver, ":memory:")

        # Create test table
        execute_sql(conn,
                    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, active INTEGER)",
                    [])
        execute_sql(conn, "INSERT INTO users (name, active) VALUES (?, ?)", ["Alice", 1])
        execute_sql(conn, "INSERT INTO users (name, active) VALUES (?, ?)", ["Bob", 0])

        # Prepare statement
        sql = "SELECT * FROM users WHERE active = ?"
        stmt = prepare_statement(conn, sql)
        @test stmt !== nothing
        @test stmt isa SQLite.Stmt

        # Execute prepared statement
        result = execute_prepared(conn, stmt, [1])
        rows = collect(result)
        @test length(rows) == 1
        # Note: Low-level SQLite.Row access is tested via integration tests

        close(conn)
    end

    @testset "Connection-level cache" begin
        driver = SQLiteDriver()
        conn = connect(driver, ":memory:")

        execute_sql(conn, "CREATE TABLE test (id INTEGER)", [])

        sql = "SELECT * FROM test WHERE id = ?"

        # First prepare
        stmt1 = prepare_statement(conn, sql)
        @test stmt1 !== nothing

        # Second prepare with same SQL - should return cached
        stmt2 = prepare_statement(conn, sql)
        @test stmt2 !== nothing
        @test stmt2 === stmt1  # Same object from cache

        # Different SQL
        stmt3 = prepare_statement(conn, "SELECT * FROM test WHERE id > ?")
        @test stmt3 !== nothing
        @test stmt3 !== stmt1  # Different statement

        close(conn)
    end

    @testset "Integration with fetch_all" begin
        driver = SQLiteDriver()
        conn = connect(driver, ":memory:")
        dialect = SQLiteDialect()
        registry = CodecRegistry()

        # Create test table
        execute_sql(conn, "CREATE TABLE users (id INTEGER, name TEXT, active INTEGER)", [])
        execute_sql(conn, "INSERT INTO users VALUES (1, 'Alice', 1)", [])
        execute_sql(conn, "INSERT INTO users VALUES (2, 'Bob', 0)", [])
        execute_sql(conn, "INSERT INTO users VALUES (3, 'Charlie', 1)", [])

        # Query with prepared statements
        q = from(:users) |> where(col(:users, :active) == literal(1)) |>
            select(NamedTuple, col(:users, :id), col(:users, :name))

        results = fetch_all(conn, dialect, registry, q; use_prepared = true)
        @test length(results) == 2
        @test results[1].name == "Alice"
        @test results[2].name == "Charlie"

        # Query without prepared statements
        results2 = fetch_all(conn, dialect, registry, q; use_prepared = false)
        @test length(results2) == 2
        @test results2 == results

        close(conn)
    end
end

@testset "Prepared Statements - PostgreSQL" begin
    @testset "Driver support detection" begin
        driver = PostgreSQLDriver()
        @test supports_prepared_statements(driver) == true
    end

    # PostgreSQL integration tests require a running PostgreSQL instance
    # Skip for now unless PGTEST environment variable is set
    if haskey(ENV, "PGTEST")
        @testset "Prepare and execute (PostgreSQL)" begin
            driver = PostgreSQLDriver()
            # Would need actual PostgreSQL connection
            # conn = connect(driver, ENV["PGTEST"])
            # ... tests ...
            @test_skip "PostgreSQL integration tests require PGTEST env var"
        end
    end
end
