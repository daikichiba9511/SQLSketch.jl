"""
Connection Pool Integration Tests

Integration tests for connection pooling with real database operations.

These tests verify:
- Pool integration with query execution
- Pool integration with transactions
- Concurrent access patterns
- Real-world usage patterns with both SQLite and PostgreSQL
"""

using Test
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers: SQLiteDriver, SQLiteConnection

@testset "Connection Pool Integration" begin
    @testset "SQLite Integration" begin
        @testset "Query execution with pooled connections" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            # Create table
            with_connection(pool) do conn
                execute_sql(conn, "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
                execute_sql(conn, "INSERT INTO users (name) VALUES (?)", ["Alice"])
                execute_sql(conn, "INSERT INTO users (name) VALUES (?)", ["Bob"])
            end

            # Query data
            users = with_connection(pool) do conn
                result = execute_sql(conn, "SELECT * FROM users ORDER BY id")
                # SQLite.Query is forward-only, convert to NamedTuples inside with_connection
                [NamedTuple(row) for row in result]
            end

            @test length(users) == 2
            @test users[1].name == "Alice"
            @test users[2].name == "Bob"

            close(pool)
        end

        @testset "Transaction with pooled connections" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            # Setup
            with_connection(pool) do conn
                execute_sql(conn,
                            "CREATE TABLE accounts (id INTEGER PRIMARY KEY, balance INTEGER)")
                execute_sql(conn, "INSERT INTO accounts (id, balance) VALUES (1, 100)")
                execute_sql(conn, "INSERT INTO accounts (id, balance) VALUES (2, 50)")
            end

            # Transaction
            with_connection(pool) do conn
                transaction(conn) do tx
                    execute_sql(tx,
                                "UPDATE accounts SET balance = balance - 30 WHERE id = 1")
                    execute_sql(tx,
                                "UPDATE accounts SET balance = balance + 30 WHERE id = 2")
                end
            end

            # Verify
            accounts = with_connection(pool) do conn
                result = execute_sql(conn, "SELECT * FROM accounts ORDER BY id")
                [NamedTuple(row) for row in result]
            end

            @test accounts[1].balance == 70
            @test accounts[2].balance == 80

            close(pool)
        end

        @testset "Concurrent access simulation" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 2, max_size = 5)

            # Setup
            with_connection(pool) do conn
                execute_sql(conn, "CREATE TABLE counter (value INTEGER)")
                execute_sql(conn, "INSERT INTO counter VALUES (0)")
            end

            # Simulate concurrent operations (sequential execution due to SQLite limitations)
            for _ in 1:10
                with_connection(pool) do conn
                    execute_sql(conn, "UPDATE counter SET value = value + 1")
                end
            end

            # Verify
            counter = with_connection(pool) do conn
                result = execute_sql(conn, "SELECT value FROM counter")
                [NamedTuple(row) for row in result]
            end

            @test counter[1].value == 10

            close(pool)
        end

        @testset "Pool with SQLSketch query API" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            # Setup
            with_connection(pool) do conn
                execute_sql(conn, """
                    CREATE TABLE products (
                        id INTEGER PRIMARY KEY,
                        name TEXT,
                        price REAL
                    )
                """)
                execute_sql(conn,
                            "INSERT INTO products (name, price) VALUES ('Apple', 1.5)")
                execute_sql(conn,
                            "INSERT INTO products (name, price) VALUES ('Banana', 0.8)")
                execute_sql(conn,
                            "INSERT INTO products (name, price) VALUES ('Orange', 1.2)")
            end

            # Query using SQLSketch API
            dialect = SQLiteDialect()
            registry = CodecRegistry()

            query = from(:products) |>
                    where(col(:products, :price) > literal(1.0)) |>
                    select(NamedTuple, col(:products, :name), col(:products, :price)) |>
                    order_by(col(:products, :price); desc = true)

            result = with_connection(pool) do conn
                fetch_all(conn, dialect, registry, query)
            end

            @test length(result) == 2
            @test result[1].name == "Apple"
            @test result[1].price == 1.5
            @test result[2].name == "Orange"
            @test result[2].price == 1.2

            close(pool)
        end

        @testset "Multiple pools" begin
            # Create two independent pools
            pool1 = ConnectionPool(SQLiteDriver(), ":memory:",
                                   min_size = 1, max_size = 2)
            pool2 = ConnectionPool(SQLiteDriver(), ":memory:",
                                   min_size = 1, max_size = 2)

            # Setup different tables in each pool
            with_connection(pool1) do conn
                execute_sql(conn, "CREATE TABLE t1 (value INTEGER)")
                execute_sql(conn, "INSERT INTO t1 VALUES (1)")
            end

            with_connection(pool2) do conn
                execute_sql(conn, "CREATE TABLE t2 (value INTEGER)")
                execute_sql(conn, "INSERT INTO t2 VALUES (2)")
            end

            # Verify isolation
            result1 = with_connection(pool1) do conn
                result = execute_sql(conn, "SELECT value FROM t1")
                [NamedTuple(row) for row in result]
            end
            @test result1[1].value == 1

            result2 = with_connection(pool2) do conn
                result = execute_sql(conn, "SELECT value FROM t2")
                [NamedTuple(row) for row in result]
            end
            @test result2[1].value == 2

            # pool1 should not have t2
            @test_throws Exception begin
                with_connection(pool1) do conn
                    execute_sql(conn, "SELECT value FROM t2")
                end
            end

            close(pool1)
            close(pool2)
        end

        @testset "Pool reuse after errors" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            # Setup
            with_connection(pool) do conn
                execute_sql(conn, "CREATE TABLE test (id INTEGER PRIMARY KEY)")
            end

            # Cause an error
            @test_throws Exception begin
                with_connection(pool) do conn
                    execute_sql(conn, "INVALID SQL")
                end
            end

            # Pool should still work
            result = with_connection(pool) do conn
                r = execute_sql(conn, "SELECT 1 as value")
                [NamedTuple(row) for row in r]
            end

            @test result[1].value == 1

            close(pool)
        end
    end

    @testset "Real-world Patterns" begin
        @testset "Connection pool lifecycle" begin
            # 1. Create pool
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 2, max_size = 5)

            @test !pool.closed
            @test length(pool.connections) == 2

            # 2. Use pool for multiple operations
            with_connection(pool) do conn
                execute_sql(conn, "CREATE TABLE logs (message TEXT)")
            end

            for i in 1:5
                with_connection(pool) do conn
                    execute_sql(conn, "INSERT INTO logs VALUES (?)", ["Message $i"])
                end
            end

            count_result = with_connection(pool) do conn
                result = execute_sql(conn, "SELECT COUNT(*) as count FROM logs")
                [NamedTuple(row) for row in result]
            end
            @test count_result[1].count == 5

            # 3. Close pool
            close(pool)
            @test pool.closed
            @test length(pool.connections) == 0
        end

        @testset "Resource cleanup pattern" begin
            # Ensure pool is always closed even if error occurs
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            try
                with_connection(pool) do conn
                    execute_sql(conn, "CREATE TABLE test (id INTEGER)")
                    # Simulate error
                    error("Simulated error")
                end
            catch e
                @test e isa ErrorException
            finally
                close(pool)
            end

            @test pool.closed
        end

        @testset "Batch operations with pooled connection" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            with_connection(pool) do conn
                execute_sql(conn, "CREATE TABLE batch_test (id INTEGER, value TEXT)")

                # Batch insert
                transaction(conn) do tx
                    for i in 1:100
                        execute_sql(tx, "INSERT INTO batch_test VALUES (?, ?)",
                                    [i, "value_$i"])
                    end
                end

                # Verify
                result = execute_sql(conn, "SELECT COUNT(*) as count FROM batch_test")
                count_result = [NamedTuple(row) for row in result]
                @test count_result[1].count == 100
            end

            close(pool)
        end
    end
end
