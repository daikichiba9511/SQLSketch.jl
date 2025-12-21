"""
MySQL Prepared Statement Caching Tests

Tests prepared statement caching functionality for MySQL driver.

Tests:
1. Prepared statement creation and caching
2. Cache hit/miss behavior
3. LRU eviction
4. Cache enable/disable
5. Parameterized query execution
6. Performance comparison

Requires: MySQL 8.0+ running locally (same as integration tests)
"""

using Test
using SQLSketch
using SQLSketch.Core: prepare_statement, execute_prepared, supports_prepared_statements,
                      execute_sql
using SQLSketch: MySQLDriver, MySQLDialect, MySQLConnection
using SQLSketch.Core: CodecRegistry, from, where, select, col, literal, param,
                      compile, fetch_all
using MySQL
using DBInterface

# Use same connection config as integration tests
const MYSQL_HOST = get(ENV, "MYSQL_HOST", "127.0.0.1")
const MYSQL_PORT = parse(Int, get(ENV, "MYSQL_PORT", "3307"))
const MYSQL_USER = get(ENV, "MYSQL_USER", "test_user")
const MYSQL_PASSWORD = get(ENV, "MYSQL_PASSWORD", "test_password")
const MYSQL_DATABASE = get(ENV, "MYSQL_DATABASE", "sqlsketch_test")

"""
    mysql_available() -> Bool

Check if MySQL is available for testing.
"""
function mysql_available()::Bool
    try
        driver = MySQLDriver()
        conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER,
                       password = MYSQL_PASSWORD,
                       port = MYSQL_PORT)
        close(conn)
        return true
    catch e
        @warn "MySQL not available for testing" exception = e
        return false
    end
end

@testset "MySQL Prepared Statement Caching" begin
    if !mysql_available()
        @warn "Skipping MySQL prepared statement tests (MySQL not available)"
        return
    end

    driver = MySQLDriver()

    @testset "Driver capabilities" begin
        @test supports_prepared_statements(driver) == true
    end

    @testset "Basic preparation and execution" begin
        conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER,
                       password = MYSQL_PASSWORD,
                       port = MYSQL_PORT)

        try
            # Setup test table (use VARCHAR instead of TEXT for better MySQL.jl compatibility)
            execute_sql(conn, "DROP TABLE IF EXISTS test_prep")
            execute_sql(conn,
                        "CREATE TABLE test_prep (id INT PRIMARY KEY, value VARCHAR(255))")
            execute_sql(conn,
                        "INSERT INTO test_prep VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie')")

            # Prepare statement
            sql = "SELECT * FROM test_prep WHERE id = ?"
            stmt_id = prepare_statement(conn, sql)
            @test stmt_id isa String
            @test !isempty(stmt_id)

            # Execute prepared statement
            result = execute_prepared(conn, stmt_id, [1])
            row_count = 0
            for row in result
                row_count += 1
                @test row[1] == 1  # id
                @test row[2] == "Alice"  # value
            end
            @test row_count == 1

            # Execute with different params
            result2 = execute_prepared(conn, stmt_id, [2])
            row_count2 = 0
            for row in result2
                row_count2 += 1
                @test row[2] == "Bob"
            end
            @test row_count2 == 1

            # Cleanup
            execute_sql(conn, "DROP TABLE test_prep")
        finally
            close(conn)
        end
    end

    @testset "Cache hit behavior" begin
        conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER,
                       password = MYSQL_PASSWORD,
                       port = MYSQL_PORT)

        try
            # Prepare same SQL twice
            sql = "SELECT 1"
            stmt_id1 = prepare_statement(conn, sql)
            stmt_id2 = prepare_statement(conn, sql)

            # Should return same stmt_id (cache hit)
            @test stmt_id1 == stmt_id2

            # Prepare different SQL
            sql2 = "SELECT 2"
            stmt_id3 = prepare_statement(conn, sql2)

            # Should return different stmt_id
            @test stmt_id1 != stmt_id3
        finally
            close(conn)
        end
    end

    @testset "LRU eviction" begin
        # Create connection with small cache (3 statements)
        raw_conn = DBInterface.connect(MySQL.Connection, MYSQL_HOST, MYSQL_USER,
                                       MYSQL_PASSWORD;
                                       db = MYSQL_DATABASE,
                                       port = MYSQL_PORT,
                                       local_files = true)
        conn = MySQLConnection(raw_conn; cache_size = 3, enable_cache = true)

        try
            # Prepare 4 different statements
            stmt1 = prepare_statement(conn, "SELECT 1 AS val")
            stmt2 = prepare_statement(conn, "SELECT 2 AS val")
            stmt3 = prepare_statement(conn, "SELECT 3 AS val")
            stmt4 = prepare_statement(conn, "SELECT 4 AS val")

            # Cache should only have 3 statements (stmt1 evicted)
            @test length(conn.stmt_cache) == 3

            # stmt1 should be evicted, so executing it should fail
            @test_throws ErrorException execute_prepared(conn, stmt1, [])

            # stmt2, stmt3, stmt4 should still be in cache
            result2 = execute_prepared(conn, stmt2, [])
            @test result2 !== nothing
            result3 = execute_prepared(conn, stmt3, [])
            @test result3 !== nothing
            result4 = execute_prepared(conn, stmt4, [])
            @test result4 !== nothing
        finally
            close(conn)
        end
    end

    @testset "Cache disabled" begin
        # Create connection with cache disabled
        raw_conn = DBInterface.connect(MySQL.Connection, MYSQL_HOST, MYSQL_USER,
                                       MYSQL_PASSWORD;
                                       db = MYSQL_DATABASE,
                                       port = MYSQL_PORT,
                                       local_files = true)
        conn = MySQLConnection(raw_conn; enable_cache = false)

        try
            # Prepare statement
            sql = "SELECT 1 AS val"
            stmt_id = prepare_statement(conn, sql)

            # Cache should be empty
            @test length(conn.stmt_cache) == 0

            # Execution should fail (not in cache)
            @test_throws ErrorException execute_prepared(conn, stmt_id, [])
        finally
            close(conn)
        end
    end

    @testset "Parameterized queries" begin
        conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER,
                       password = MYSQL_PASSWORD,
                       port = MYSQL_PORT)

        try
            # Setup
            execute_sql(conn, "DROP TABLE IF EXISTS test_params")
            execute_sql(conn,
                        "CREATE TABLE test_params (id INT, name VARCHAR(255), age INT)")
            execute_sql(conn,
                        "INSERT INTO test_params VALUES (1, 'Alice', 30), (2, 'Bob', 25), (3, 'Charlie', 35)")

            # Test multiple parameters
            sql = "SELECT * FROM test_params WHERE age > ? AND age < ?"
            stmt_id = prepare_statement(conn, sql)

            result = execute_prepared(conn, stmt_id, [20, 32])
            rows = collect(result)
            @test length(rows) == 2  # Alice (30), Bob (25)

            # Test with different params
            result2 = execute_prepared(conn, stmt_id, [28, 40])
            rows2 = collect(result2)
            @test length(rows2) == 2  # Alice (30), Charlie (35)

            # Cleanup
            execute_sql(conn, "DROP TABLE test_params")
        finally
            close(conn)
        end
    end

    @testset "Integration with fetch_all" begin
        conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER,
                       password = MYSQL_PASSWORD,
                       port = MYSQL_PORT)
        dialect = MySQLDialect()
        registry = CodecRegistry()
        SQLSketch.Codecs.MySQL.register_mysql_codecs!(registry)

        try
            # Setup
            execute_sql(conn, "DROP TABLE IF EXISTS test_fetch")
            execute_sql(conn, "CREATE TABLE test_fetch (id INT, value VARCHAR(255))")
            execute_sql(conn, "INSERT INTO test_fetch VALUES (1, 'test1'), (2, 'test2')")

            # Query with use_prepared=true
            q = from(:test_fetch) |>
                where(col(:test_fetch, :id) == param(Int, :id)) |>
                select(NamedTuple, col(:test_fetch, :id), col(:test_fetch, :value))

            # First execution (cache miss)
            results1 = fetch_all(conn, dialect, registry, q, (id = 1,); use_prepared = true)
            @test length(results1) == 1
            @test results1[1].id == 1
            @test results1[1].value == "test1"

            # Second execution (cache hit)
            results2 = fetch_all(conn, dialect, registry, q, (id = 2,); use_prepared = true)
            @test length(results2) == 1
            @test results2[1].id == 2
            @test results2[1].value == "test2"

            # Cache should have the statement
            @test length(conn.stmt_cache) >= 1

            # Cleanup
            execute_sql(conn, "DROP TABLE test_fetch")
        finally
            close(conn)
        end
    end
end
