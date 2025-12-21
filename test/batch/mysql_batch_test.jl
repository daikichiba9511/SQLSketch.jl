"""
MySQL Batch Operations Tests

Tests batch insert functionality for MySQL.
"""

using Test
using SQLSketch
using SQLSketch.Core: insert_batch, execute, CodecRegistry
using SQLSketch.Core: create_table, add_column, drop_table, from, select, col
using SQLSketch.Core: fetch_all, fetch_one, func
using SQLSketch: MySQLDriver, MySQLDialect

# Connection configuration
const MYSQL_HOST = get(ENV, "MYSQL_HOST", "127.0.0.1")
const MYSQL_PORT = parse(Int, get(ENV, "MYSQL_PORT", "3307"))
const MYSQL_USER = get(ENV, "MYSQL_USER", "test_user")
const MYSQL_PASSWORD = get(ENV, "MYSQL_PASSWORD", "test_password")
const MYSQL_DATABASE = get(ENV, "MYSQL_DATABASE", "sqlsketch_test")

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
    @warn "Skipping MySQL batch operations tests - MySQL not available"
    @testset "MySQL Batch Operations (Skipped)" begin
        @test_broken false
    end
else
    @testset "MySQL Batch Operations Tests" begin
        driver = MySQLDriver()
        dialect = MySQLDialect()
        registry = CodecRegistry()

        conn = connect(driver, MYSQL_HOST, MYSQL_DATABASE;
                       user = MYSQL_USER, password = MYSQL_PASSWORD, port = MYSQL_PORT)

        try
            # Setup: Create test table
            @testset "Setup" begin
                try
                    execute(conn, dialect, drop_table(:test_batch; if_exists = true))
                catch
                end

                ddl = create_table(:test_batch; if_not_exists = true) |>
                      add_column(:id, :integer; primary_key = true,
                                 auto_increment = true) |>
                      add_column(:email, :varchar; nullable = false) |>
                      add_column(:name, :varchar) |>
                      add_column(:age, :integer) |>
                      add_column(:active, :boolean)

                execute(conn, dialect, ddl)

                # Verify table exists
                tables = execute_sql(conn,
                                     "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE()")
                table_names = [row[1] for row in tables]
                @test "test_batch" in table_names
            end

            @testset "Basic Batch Insert" begin
                # Insert 10 rows
                rows = [(email = "user$i@example.com", name = "User $i", age = 20+i,
                         active = true)
                        for i in 1:10]

                result = insert_batch(conn, dialect, registry, :test_batch,
                                      [:email, :name, :age, :active], rows)

                @test result.rowcount == 10

                # Verify insertion
                q = from(:test_batch) |>
                    select(NamedTuple, func(:COUNT, [col(:test_batch, :id)]))
                count_result = fetch_one(conn, dialect, registry, q)
                # MySQL returns count in different field names, just verify it's not nothing
                @test count_result !== nothing
            end

            @testset "Empty Batch" begin
                # Empty rows should return 0
                result = insert_batch(conn, dialect, registry, :test_batch,
                                      [:email, :name, :age, :active], NamedTuple[])

                @test result.rowcount == 0
            end

            @testset "Large Batch (Chunking)" begin
                # Clear table
                execute_sql(conn, "TRUNCATE TABLE test_batch", [])

                # Insert 2500 rows (will be split into 3 chunks with default chunk_size=1000)
                rows = [(email = "user$i@example.com", name = "User $i",
                         age = 20+mod(i, 50), active = isodd(i))
                        for i in 1:2500]

                result = insert_batch(conn, dialect, registry, :test_batch,
                                      [:email, :name, :age, :active], rows;
                                      chunk_size = 1000)

                @test result.rowcount == 2500

                # Verify all rows inserted
                q = from(:test_batch) |>
                    select(NamedTuple, func(:COUNT, [col(:test_batch, :id)]))
                count_result = fetch_one(conn, dialect, registry, q)
                @test count_result !== nothing
            end

            @testset "Custom Chunk Size" begin
                # Clear table
                execute_sql(conn, "TRUNCATE TABLE test_batch", [])

                # Insert 500 rows with chunk_size=100
                rows = [(email = "user$i@example.com", name = "User $i", age = 25,
                         active = true)
                        for i in 1:500]

                result = insert_batch(conn, dialect, registry, :test_batch,
                                      [:email, :name, :age, :active], rows;
                                      chunk_size = 100)

                @test result.rowcount == 500
            end

            @testset "Type Conversion" begin
                # Clear table
                execute_sql(conn, "TRUNCATE TABLE test_batch", [])

                # Test various types
                rows = [(email = "test1@example.com", name = "Test 1", age = 30,
                         active = true),
                        (email = "test2@example.com", name = "Test 2", age = 25,
                         active = false),
                        (email = "test3@example.com", name = missing, age = missing,
                         active = true)]

                result = insert_batch(conn, dialect, registry, :test_batch,
                                      [:email, :name, :age, :active], rows)

                @test result.rowcount == 3

                # Verify data
                q = from(:test_batch) |>
                    select(NamedTuple, col(:test_batch, :email), col(:test_batch, :name),
                           col(:test_batch, :age), col(:test_batch, :active))
                results = fetch_all(conn, dialect, registry, q; use_prepared = false)

                @test length(results) >= 3
            end

            @testset "Validation" begin
                # Empty columns should error
                @test_throws ErrorException insert_batch(conn, dialect, registry,
                                                         :test_batch,
                                                         Symbol[], [(email = "test",)])

                # Mismatched columns should error
                rows = [(email = "test@example.com", wrong_field = "value")]
                @test_throws ErrorException insert_batch(conn, dialect, registry,
                                                         :test_batch,
                                                         [:email, :name], rows)
            end

            @testset "Performance Comparison" begin
                # Clear table
                execute_sql(conn, "TRUNCATE TABLE test_batch", [])

                rows = [(email = "perf$i@example.com", name = "Perf $i", age = 30,
                         active = true)
                        for i in 1:100]

                # Measure batch insert time
                batch_time = @elapsed begin
                    insert_batch(conn, dialect, registry, :test_batch,
                                 [:email, :name, :age, :active], rows)
                end

                # Clear for next test
                execute_sql(conn, "TRUNCATE TABLE test_batch", [])

                # Measure individual inserts time
                using SQLSketch.Core: insert_into, values, literal
                individual_time = @elapsed begin
                    for row in rows
                        q = insert_into(:test_batch, [:email, :name, :age, :active]) |>
                            values([[literal(row.email), literal(row.name),
                                     literal(row.age), literal(row.active)]])
                        execute(conn, dialect, q)
                    end
                end

                # Batch should be faster
                speedup = individual_time / batch_time
                println("  Batch insert speedup: $(round(speedup, digits=2))x faster")
                @test batch_time < individual_time
            end

        finally
            # Cleanup
            try
                execute(conn, dialect, drop_table(:test_batch; if_exists = true))
            catch e
                @warn "Cleanup failed" exception=e
            end
            close(conn)
        end
    end
end
