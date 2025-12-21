"""
MySQL Connection Pool Tests

Tests connection pooling functionality for MySQL.
"""

using Test
using SQLSketch
using SQLSketch.Core: ConnectionPool, acquire, release, with_connection
using SQLSketch.Core: execute_sql
using SQLSketch: MySQLDriver

# Connection configuration
const MYSQL_HOST = get(ENV, "MYSQL_HOST", "127.0.0.1")
const MYSQL_PORT = parse(Int, get(ENV, "MYSQL_PORT", "3307"))
const MYSQL_USER = get(ENV, "MYSQL_USER", "test_user")
const MYSQL_PASSWORD = get(ENV, "MYSQL_PASSWORD", "test_password")
const MYSQL_DATABASE = get(ENV, "MYSQL_DATABASE", "sqlsketch_test")

# Helper to create config string
mysql_config() = "$MYSQL_HOST,$MYSQL_DATABASE,$MYSQL_USER,$MYSQL_PASSWORD,$MYSQL_PORT"

"""
Check if MySQL is available for testing.
"""
function mysql_available()::Bool
    try
        driver = MySQLDriver()
        conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER, password = MYSQL_PASSWORD, port = MYSQL_PORT)
        close(conn)
        return true
    catch e
        @warn "MySQL not available for testing" exception=e
        return false
    end
end

# Skip all tests if MySQL is not available
if !mysql_available()
    @warn "Skipping MySQL connection pool tests - MySQL not available"
    @testset "MySQL Connection Pool (Skipped)" begin
        @test_broken false
    end
else
    @testset "MySQL Connection Pool Tests" begin
        driver = MySQLDriver()
        config = mysql_config()

        @testset "Pool Creation" begin
            # Minimum pool size
            pool = ConnectionPool(driver, config; min_size = 2, max_size = 10)
            @test length(pool.connections) == 2
            @test pool.min_size == 2
            @test pool.max_size == 10
            @test !pool.closed
            close(pool)

            # Zero minimum size
            pool = ConnectionPool(driver, config; min_size = 0, max_size = 5)
            @test length(pool.connections) == 0
            close(pool)
        end

        @testset "Acquire and Release" begin
            pool = ConnectionPool(driver, config; min_size = 1, max_size = 3)

            # Acquire connection
            conn1 = acquire(pool)
            @test conn1 !== nothing

            # Execute query to verify connection works
            result = execute_sql(conn1, "SELECT 1", [])
            @test result !== nothing

            # Release connection
            release(pool, conn1)

            # Acquire again (should get same connection)
            conn2 = acquire(pool)
            @test conn2 === conn1

            release(pool, conn2)
            close(pool)
        end

        @testset "with_connection Pattern" begin
            pool = ConnectionPool(driver, config; min_size = 1, max_size = 5)

            # Basic usage
            result = with_connection(pool) do conn
                execute_sql(conn, "SELECT 42", [])
            end

            @test result !== nothing

            # Exception handling (connection should be released)
            @test_throws ErrorException begin
                with_connection(pool) do conn
                    error("Test error")
                end
            end

            # Verify connection is still released
            conn = acquire(pool)
            @test conn !== nothing
            release(pool, conn)

            close(pool)
        end

        @testset "Pool Growth" begin
            pool = ConnectionPool(driver, config; min_size = 1, max_size = 5)

            # Initially has min_size connections
            @test length(pool.connections) == 1

            # Acquire multiple connections
            conn1 = acquire(pool)
            conn2 = acquire(pool)
            conn3 = acquire(pool)

            # Pool should have grown
            @test length(pool.connections) == 3

            release(pool, conn1)
            release(pool, conn2)
            release(pool, conn3)

            close(pool)
        end

        @testset "Max Size Limit" begin
            pool = ConnectionPool(driver, config; min_size = 1, max_size = 2)

            conn1 = acquire(pool)
            conn2 = acquire(pool)

            # Pool is at max size
            @test length(pool.connections) == 2

            # Third acquire should block
            # We'll test this with a timeout using a Task
            acquired = Ref(false)
            task = Threads.@spawn begin
                acquire(pool)
                acquired[] = true
            end

            # Wait a bit - should not acquire
            sleep(0.1)
            @test !acquired[]

            # Release one connection
            release(pool, conn1)

            # Now the task should complete
            wait(task)
            @test acquired[]

            # Clean up
            release(pool, conn2)
            close(pool)
        end

        @testset "Health Checking" begin
            pool = ConnectionPool(driver, config;
                                  min_size = 1, max_size = 3,
                                  health_check_interval = 0.1)

            # Acquire connection
            conn = acquire(pool)

            # Execute query (should work)
            result = execute_sql(conn, "SELECT 1", [])
            @test result !== nothing

            release(pool, conn)

            # Wait for health check interval
            sleep(0.2)

            # Acquire again - should trigger health check
            conn2 = acquire(pool)
            @test conn2 !== nothing

            # Verify it still works
            result = execute_sql(conn2, "SELECT 1", [])
            @test result !== nothing

            release(pool, conn2)
            close(pool)
        end

        @testset "Close Pool" begin
            pool = ConnectionPool(driver, config; min_size = 2, max_size = 5)

            # Close pool
            close(pool)

            @test pool.closed
            @test isempty(pool.connections)

            # Should not be able to acquire after close
            @test_throws ErrorException acquire(pool)

            # Double close should be safe
            close(pool)
        end

        @testset "Concurrent Access" begin
            pool = ConnectionPool(driver, config; min_size = 2, max_size = 5)

            # Run concurrent queries
            tasks = [Threads.@spawn with_connection(pool) do conn
                         execute_sql(conn, "SELECT $i", [])
                     end for i in 1:10]

            # Wait for all tasks
            results = [fetch(task) for task in tasks]

            @test length(results) == 10
            @test all(r !== nothing for r in results)

            close(pool)
        end

        @testset "Config String Parsing" begin
            # Valid config
            conn = connect(driver,
                           "$MYSQL_HOST,$MYSQL_DATABASE,$MYSQL_USER,$MYSQL_PASSWORD,$MYSQL_PORT")
            @test conn !== nothing
            result = execute_sql(conn, "SELECT 1", [])
            @test result !== nothing
            close(conn)

            # Invalid config
            @test_throws ErrorException connect(driver, "invalid_config")
        end
    end
end
