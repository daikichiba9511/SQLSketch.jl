"""
Connection Pool Unit Tests

Tests for Core/pool.jl connection pooling implementation.

These tests verify:
- Pool creation and configuration
- Connection acquire/release semantics
- Thread safety (basic tests)
- Health checking
- Resource cleanup
- Error handling
"""

using Test
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers: SQLiteDriver, SQLiteConnection

@testset "Connection Pool" begin
    @testset "Pool Creation" begin
        @testset "Basic pool creation" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 2, max_size = 5)

            @test pool.min_size == 2
            @test pool.max_size == 5
            @test length(pool.connections) == 2  # min_size connections created
            @test !pool.closed

            # All connections should be available initially
            for pc in pool.connections
                @test !pc.in_use
            end

            close(pool)
        end

        @testset "Zero min_size" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 0, max_size = 3)

            @test pool.min_size == 0
            @test pool.max_size == 3
            @test length(pool.connections) == 0  # No connections created yet

            close(pool)
        end

        @testset "Parameter validation" begin
            # min_size < 0
            @test_throws AssertionError ConnectionPool(SQLiteDriver(), ":memory:",
                                                       min_size = -1, max_size = 5)

            # max_size < min_size
            @test_throws AssertionError ConnectionPool(SQLiteDriver(), ":memory:",
                                                       min_size = 5, max_size = 2)

            # Negative health check interval
            @test_throws AssertionError ConnectionPool(SQLiteDriver(), ":memory:",
                                                       min_size = 1, max_size = 5,
                                                       health_check_interval = -1.0)
        end

        @testset "Health check interval configuration" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3,
                                  health_check_interval = 30.0)

            @test pool.health_check_interval == 30.0

            close(pool)
        end
    end

    @testset "Connection Acquire/Release" begin
        @testset "Basic acquire/release" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 2, max_size = 5)

            # Acquire connection
            conn1 = acquire(pool)
            @test conn1 isa SQLiteConnection

            # One connection should be in use
            in_use_count = count(pc -> pc.in_use, pool.connections)
            @test in_use_count == 1

            # Release connection
            release(pool, conn1)

            # All connections should be available
            in_use_count = count(pc -> pc.in_use, pool.connections)
            @test in_use_count == 0

            close(pool)
        end

        @testset "Multiple acquire" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 2, max_size = 5)

            # Acquire multiple connections
            conn1 = acquire(pool)
            conn2 = acquire(pool)

            @test conn1 !== conn2  # Different connections

            # Two connections should be in use
            in_use_count = count(pc -> pc.in_use, pool.connections)
            @test in_use_count == 2

            # Release both
            release(pool, conn1)
            release(pool, conn2)

            # All available
            in_use_count = count(pc -> pc.in_use, pool.connections)
            @test in_use_count == 0

            close(pool)
        end

        @testset "Connection reuse" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            # Acquire, release, acquire again
            conn1 = acquire(pool)
            release(pool, conn1)
            conn2 = acquire(pool)

            # Should reuse the same connection
            @test conn1 === conn2

            release(pool, conn2)
            close(pool)
        end

        @testset "Pool expansion" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            @test length(pool.connections) == 1

            # Acquire all connections + 1
            conn1 = acquire(pool)
            @test length(pool.connections) == 1

            conn2 = acquire(pool)
            @test length(pool.connections) == 2  # Pool expanded

            conn3 = acquire(pool)
            @test length(pool.connections) == 3  # Max size reached

            # Release all
            release(pool, conn1)
            release(pool, conn2)
            release(pool, conn3)

            close(pool)
        end

        @testset "Acquire after release" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            conn = acquire(pool)
            execute_sql(conn, "CREATE TABLE test (id INTEGER)")
            release(pool, conn)

            # Acquire again - should get same connection with table still present
            conn2 = acquire(pool)
            result = execute_sql(conn2, "SELECT name FROM sqlite_master WHERE type='table'")
            tables = [row.name for row in result]
            @test "test" in tables

            release(pool, conn2)
            close(pool)
        end
    end

    @testset "with_connection Pattern" begin
        @testset "Basic with_connection" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            result = with_connection(pool) do conn
                execute_sql(conn, "SELECT 1 as value")
            end

            # Connection should be released
            in_use_count = count(pc -> pc.in_use, pool.connections)
            @test in_use_count == 0

            close(pool)
        end

        @testset "Exception handling" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            # Exception should be propagated
            @test_throws ErrorException begin
                with_connection(pool) do conn
                    error("Test error")
                end
            end

            # But connection should still be released
            in_use_count = count(pc -> pc.in_use, pool.connections)
            @test in_use_count == 0

            close(pool)
        end

        @testset "Nested with_connection" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 2, max_size = 5)

            with_connection(pool) do conn1
                execute_sql(conn1, "SELECT 1")

                with_connection(pool) do conn2
                    execute_sql(conn2, "SELECT 2")

                    # Different connections
                    @test conn1 !== conn2
                end
            end

            # All connections released
            in_use_count = count(pc -> pc.in_use, pool.connections)
            @test in_use_count == 0

            close(pool)
        end
    end

    @testset "Health Checking" begin
        @testset "Health check disabled" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3,
                                  health_check_interval = 0.0)  # Disabled

            conn = acquire(pool)
            release(pool, conn)

            # Wait a bit
            sleep(0.1)

            # Should get same connection without health check
            conn2 = acquire(pool)
            @test conn === conn2

            release(pool, conn2)
            close(pool)
        end

        @testset "Health check with healthy connection" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3,
                                  health_check_interval = 0.05)  # 50ms

            conn = acquire(pool)
            release(pool, conn)

            # Wait for health check interval
            sleep(0.1)

            # Should get same connection (health check should pass)
            conn2 = acquire(pool)
            @test conn === conn2

            release(pool, conn2)
            close(pool)
        end
    end

    @testset "Pool Close" begin
        @testset "Close empty pool" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 0, max_size = 3)

            close(pool)

            @test pool.closed
            @test length(pool.connections) == 0
        end

        @testset "Close pool with connections" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 2, max_size = 5)

            @test length(pool.connections) == 2

            close(pool)

            @test pool.closed
            @test length(pool.connections) == 0
        end

        @testset "Cannot acquire from closed pool" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            close(pool)

            @test_throws ErrorException acquire(pool)
        end

        @testset "Double close is safe" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            close(pool)
            close(pool)  # Should not error

            @test pool.closed
        end
    end

    @testset "Edge Cases" begin
        @testset "Release connection not in pool" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            # Create connection outside pool
            external_conn = connect(SQLiteDriver(), ":memory:")

            # Should warn but not error
            @test_logs (:warn,) release(pool, external_conn)

            Base.close(external_conn)
            close(pool)
        end

        @testset "Release already released connection" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            conn = acquire(pool)
            release(pool, conn)

            # Release again - should warn
            @test_logs (:warn,) release(pool, conn)

            close(pool)
        end

        @testset "Single connection pool" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 1)

            conn = acquire(pool)
            execute_sql(conn, "SELECT 1")
            release(pool, conn)

            close(pool)
        end
    end

    @testset "Type Safety" begin
        @testset "Pool type parameters" begin
            pool = ConnectionPool(SQLiteDriver(), ":memory:",
                                  min_size = 1, max_size = 3)

            @test pool isa ConnectionPool{SQLiteDriver, SQLiteConnection}

            conn = acquire(pool)
            @test conn isa SQLiteConnection

            release(pool, conn)
            close(pool)
        end
    end
end
