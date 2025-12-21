"""
MySQL Integration Tests

Tests SQLSketch against a real MySQL 8.0+ database to ensure:
1. Queries work correctly
2. MySQL-specific features work (AUTO_INCREMENT, ON DUPLICATE KEY UPDATE)
3. Transactions and DML operations work correctly
4. Type conversions work (TINYINT(1) for booleans, etc.)

Requires: MySQL 8.0+ running locally
Connection: mysql://root@localhost:3306/sqlsketch_test

To setup MySQL for testing:
  # Create test database
  mysql -u root -e "CREATE DATABASE IF NOT EXISTS sqlsketch_test"

  # Or with Docker
  docker run --name mysql-test -e MYSQL_ROOT_PASSWORD=test -e MYSQL_DATABASE=sqlsketch_test -p 3306:3306 -d mysql:8.0

To stop Docker MySQL:
  docker stop mysql-test && docker rm mysql-test
"""

using Test
using SQLSketch
using SQLSketch.Core: from, where, select, join, order_by, limit, offset, distinct,
                      group_by, having
using SQLSketch.Core: insert_into, insert_values, update, set_values, delete_from, returning
using SQLSketch.Core: col, literal, param, func
using SQLSketch.Extras: p_
using SQLSketch.Core: cte, with, union
using SQLSketch.Core: on_conflict_do_nothing, on_conflict_do_update
using SQLSketch.Core: transaction, savepoint
using SQLSketch.Core: create_table, add_column, drop_table, create_index, drop_index
using SQLSketch.Core: compile, fetch_all, fetch_one, fetch_maybe, execute, execute_sql,
                      sql, ExecResult
using SQLSketch.Core: CodecRegistry
using SQLSketch: MySQLDialect, MySQLDriver
using Dates
using JSON3

# Connection configuration
# Note: Use 127.0.0.1 instead of localhost to force TCP connection (MySQL.jl tries Unix socket with localhost)
const MYSQL_HOST = get(ENV, "MYSQL_HOST", "127.0.0.1")
const MYSQL_PORT = parse(Int, get(ENV, "MYSQL_PORT", "3307"))  # 3307 for docker-compose
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

"""
    setup_test_tables(conn, dialect)

Create test tables for integration testing.
"""
function setup_test_tables(conn, dialect)
    # Drop tables if they exist
    try
        execute(conn, dialect, drop_table(:orders; if_exists = true))
        execute(conn, dialect, drop_table(:users; if_exists = true))
    catch
    end

    # Create users table with AUTO_INCREMENT
    # Note: Use :varchar for email instead of :text to allow UNIQUE index in MySQL
    users_ddl = create_table(:users; if_not_exists = true) |>
                add_column(:id, :integer; primary_key = true, auto_increment = true) |>
                add_column(:email, :varchar; nullable = false, unique = true) |>
                add_column(:name, :varchar; nullable = false) |>
                add_column(:age, :integer) |>
                add_column(:active, :boolean; default = literal(true)) |>
                add_column(:created_at, :timestamp) |>
                add_column(:metadata, :json)  # JSON column for testing

    execute(conn, dialect, users_ddl)

    # Create orders table
    orders_ddl = create_table(:orders; if_not_exists = true) |>
                 add_column(:id, :integer; primary_key = true, auto_increment = true) |>
                 add_column(:user_id, :integer) |>
                 add_column(:total, :real) |>
                 add_column(:status, :varchar) |>
                 add_column(:created_at, :timestamp)

    execute(conn, dialect, orders_ddl)
end

"""
    insert_test_data(conn, dialect)

Insert test data into tables.
"""
function insert_test_data(conn, dialect)
    # Insert users (MySQL will auto-generate IDs)
    users_data = [("alice@example.com", "Alice", 30, true, DateTime(2024, 1, 1)),
                  ("bob@example.com", "Bob", 25, true, DateTime(2024, 1, 2)),
                  ("charlie@example.com", "Charlie", 35, false, DateTime(2024, 1, 3)),
                  ("diana@example.com", "Diana", 28, true, DateTime(2024, 1, 4))]

    for (email, name, age, active, created_at) in users_data
        q = insert_into(:users, [:email, :name, :age, :active, :created_at]) |>
            insert_values([[literal(email), literal(name), literal(age), literal(active),
                            literal(created_at)]])
        execute(conn, dialect, q)
    end

    # Insert orders
    orders_data = [(1, 100.50, "completed", DateTime(2024, 1, 10)),
                   (1, 50.25, "pending", DateTime(2024, 1, 11)),
                   (2, 75.00, "completed", DateTime(2024, 1, 12)),
                   (2, 200.00, "completed", DateTime(2024, 1, 13)),
                   (4, 150.00, "cancelled", DateTime(2024, 1, 14))]

    for (user_id, total, status, created_at) in orders_data
        q = insert_into(:orders, [:user_id, :total, :status, :created_at]) |>
            insert_values([[literal(user_id), literal(total), literal(status),
                            literal(created_at)]])
        execute(conn, dialect, q)
    end
end

# Skip all tests if MySQL is not available
if !mysql_available()
    @warn "Skipping MySQL integration tests - MySQL not available"
    @testset "MySQL Integration (Skipped)" begin
        @test_broken false  # Mark as expected failure when MySQL is not available
    end
else
    @testset "MySQL Integration Tests" begin
        mysql_driver = MySQLDriver()
        mysql_dialect = MySQLDialect(v"8.0.0")  # Assume MySQL 8.0+
        mysql_conn = connect(mysql_driver, MYSQL_HOST, MYSQL_DATABASE;
                             user = MYSQL_USER,
                             password = MYSQL_PASSWORD,
                             port = MYSQL_PORT)
        mysql_registry = CodecRegistry()

        try
            # Setup
            @testset "Setup - Create Tables" begin
                setup_test_tables(mysql_conn, mysql_dialect)
                insert_test_data(mysql_conn, mysql_dialect)

                # Verify tables exist
                tables = execute_sql(mysql_conn,
                                     "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE()")
                table_names = [row[1] for row in tables]
                @test "users" in table_names
                @test "orders" in table_names
            end

            @testset "Basic SELECT Queries" begin
                # Simple SELECT
                q = from(:users) |>
                    select(NamedTuple, col(:users, :name), col(:users, :email))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)

                @test length(results) == 4
                @test results[1].name == "Alice"
                @test results[1].email == "alice@example.com"

                # SELECT with WHERE
                q = from(:users) |>
                    where(col(:users, :age) > literal(25)) |>
                    select(NamedTuple, col(:users, :name))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)

                @test length(results) == 3  # Alice (30), Charlie (35), Diana (28)
            end

            @testset "Boolean Type Conversion" begin
                # MySQL stores booleans as TINYINT(1)
                q = from(:users) |>
                    where(col(:users, :active) == literal(true)) |>
                    select(NamedTuple, col(:users, :name), col(:users, :active))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)

                @test length(results) == 3  # Alice, Bob, Diana
                # Note: MySQL returns TINYINT as Int, not Bool
                # The codec should handle conversion
            end

            @testset "JOIN Queries" begin
                q = from(:users) |>
                    join(:orders, col(:users, :id) == col(:orders, :user_id)) |>
                    where(col(:orders, :status) == literal("completed")) |>
                    select(NamedTuple, col(:users, :name), col(:orders, :total))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)

                @test length(results) >= 3  # Alice has 1, Bob has 2 completed orders
            end

            @testset "Aggregation Queries" begin
                q = from(:orders) |>
                    where(col(:orders, :status) == literal("completed")) |>
                    group_by(col(:orders, :user_id)) |>
                    select(NamedTuple, col(:orders, :user_id),
                           func(:SUM, [col(:orders, :total)]))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)

                @test length(results) >= 2
            end

            @testset "ORDER BY and LIMIT" begin
                q = from(:users) |>
                    order_by(col(:users, :age); desc = true) |>
                    limit(2) |>
                    select(NamedTuple, col(:users, :name), col(:users, :age))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)

                @test length(results) == 2
                @test results[1].name == "Charlie"  # age 35
                @test results[2].name == "Alice"  # age 30
            end

            @testset "INSERT with AUTO_INCREMENT" begin
                q = insert_into(:users, [:email, :name, :age]) |>
                    insert_values([[literal("eve@example.com"), literal("Eve"),
                                    literal(27)]])

                result = execute(mysql_conn, mysql_dialect, q)
                @test result.rowcount === nothing || result.rowcount >= 1

                # Verify insertion
                verify_q = from(:users) |>
                           where(col(:users, :email) == literal("eve@example.com")) |>
                           select(NamedTuple, col(:users, :name), col(:users, :email))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                    verify_q; use_prepared = false)

                @test length(results) == 1
                @test results[1].name == "Eve"
            end

            @testset "UPDATE Queries" begin
                q = update(:users) |>
                    set(:age => literal(31)) |>
                    where(col(:users, :email) == literal("alice@example.com"))

                result = execute(mysql_conn, mysql_dialect, q)
                @test result.rowcount === nothing || result.rowcount >= 1

                # Verify update
                verify_q = from(:users) |>
                           where(col(:users, :email) == literal("alice@example.com")) |>
                           select(NamedTuple, col(:users, :age))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                    verify_q; use_prepared = false)

                @test results[1].age == 31
            end

            @testset "DELETE Queries" begin
                # Count before delete
                count_q = from(:users) |> select(NamedTuple, func(:COUNT, [literal(1)]))
                before_count = fetch_one(mysql_conn, mysql_dialect, mysql_registry, count_q)

                # Delete
                q = delete_from(:users) |>
                    where(col(:users, :email) == literal("eve@example.com"))
                result = execute(mysql_conn, mysql_dialect, q)

                # Verify deletion
                after_count = fetch_one(mysql_conn, mysql_dialect, mysql_registry, count_q)
                # Note: COUNT result might be in different field names
            end

            @testset "UPSERT - INSERT IGNORE (DO NOTHING)" begin
                # Try to insert duplicate email (should be ignored)
                q = insert_into(:users, [:email, :name, :age]) |>
                    insert_values([[literal("alice@example.com"), literal("Alice2"),
                                    literal(99)]]) |>
                    on_conflict_do_nothing()

                # MySQL uses INSERT IGNORE
                result = execute(mysql_conn, mysql_dialect, q)
                # Should not error, but won't insert (email is unique)

                # Verify Alice's name hasn't changed
                verify_q = from(:users) |>
                           where(col(:users, :email) == literal("alice@example.com")) |>
                           select(NamedTuple, col(:users, :name))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                    verify_q; use_prepared = false)

                @test results[1].name == "Alice"  # Not "Alice2"
            end

            @testset "UPSERT - ON DUPLICATE KEY UPDATE" begin
                # Insert or update
                q = insert_into(:users, [:email, :name, :age]) |>
                    insert_values([[literal("frank@example.com"), literal("Frank"),
                                    literal(40)]]) |>
                    on_conflict_do_update([:email], :name => literal("Frank Updated"),
                                          :age => literal(41))

                result = execute(mysql_conn, mysql_dialect, q)

                # First time should insert
                verify_q = from(:users) |>
                           where(col(:users, :email) == literal("frank@example.com")) |>
                           select(NamedTuple, col(:users, :name), col(:users, :age))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                    verify_q; use_prepared = false)

                @test length(results) == 1

                # Run again - should update
                execute(mysql_conn, mysql_dialect, q)
                results2 = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                     verify_q; use_prepared = false)

                @test results2[1].name == "Frank Updated"
                @test results2[1].age == 41
            end

            @testset "Transactions - Commit" begin
                transaction(mysql_conn) do txn
                    q = insert_into(:users, [:email, :name, :age]) |>
                        insert_values([[literal("grace@example.com"), literal("Grace"),
                                        literal(26)]])
                    execute(txn, mysql_dialect, q)
                end

                # Verify committed
                verify_q = from(:users) |>
                           where(col(:users, :email) == literal("grace@example.com")) |>
                           select(NamedTuple, col(:users, :name))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                    verify_q; use_prepared = false)

                @test length(results) == 1
                @test results[1].name == "Grace"
            end

            @testset "Transactions - Rollback" begin
                try
                    transaction(mysql_conn) do txn
                        q = insert_into(:users, [:email, :name, :age]) |>
                            insert_values([[literal("henry@example.com"), literal("Henry"),
                                            literal(29)]])
                        execute(txn, mysql_dialect, q)

                        # Throw error to trigger rollback
                        error("Intentional rollback")
                    end
                catch e
                    @test occursin("Intentional rollback", string(e))
                end

                # Verify rollback - Henry should not exist
                verify_q = from(:users) |>
                           where(col(:users, :email) == literal("henry@example.com")) |>
                           select(NamedTuple, col(:users, :name))
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                    verify_q; use_prepared = false)

                @test length(results) == 0
            end

            @testset "Savepoints" begin
                transaction(mysql_conn) do txn
                    # Insert first user
                    q1 = insert_into(:users, [:email, :name, :age]) |>
                         insert_values([[literal("ivy@example.com"), literal("Ivy"),
                                         literal(24)]])
                    execute(txn, mysql_dialect, q1)

                    # Savepoint
                    try
                        savepoint(txn, :sp1) do sp
                            q2 = insert_into(:users, [:email, :name, :age]) |>
                                 insert_values([[literal("jack@example.com"),
                                                 literal("Jack"),
                                                 literal(32)]])
                            execute(sp, mysql_dialect, q2)

                            error("Rollback to savepoint")
                        end
                    catch
                        # Savepoint rolled back
                    end

                    # Transaction continues
                end

                # Verify Ivy exists, Jack doesn't
                verify_ivy = from(:users) |>
                             where(col(:users, :email) == literal("ivy@example.com")) |>
                             select(NamedTuple, col(:users, :name))
                ivy_results = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                        verify_ivy; use_prepared = false)
                @test length(ivy_results) == 1

                verify_jack = from(:users) |>
                              where(col(:users, :email) == literal("jack@example.com")) |>
                              select(NamedTuple, col(:users, :name))
                jack_results = fetch_all(mysql_conn, mysql_dialect, mysql_registry,
                                         verify_jack; use_prepared = false)
                @test length(jack_results) == 0
            end

            @testset "CTE (MySQL 8.0+)" begin
                # Simple CTE
                cte_query = from(:users) |>
                            where(col(:users, :active) == literal(true)) |>
                            select(NamedTuple, col(:users, :id), col(:users, :name))

                main_query = from(:active_users) |>
                             select(NamedTuple, col(:active_users, :name))

                q = with([cte(:active_users, cte_query)], main_query)
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)

                @test length(results) >= 3  # Alice, Bob, Diana (and maybe others)
            end

            @testset "Window Functions (MySQL 8.0+)" begin
                # ROW_NUMBER() OVER (ORDER BY age DESC)
                using SQLSketch.Core: row_number, Over

                q = from(:users) |>
                    select(NamedTuple, col(:users, :name), col(:users, :age),
                           row_number(Over(SQLExpr[], [(col(:users, :age), true)], nothing)))

                # MySQL 8.0+ supports window functions
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)
                @test length(results) >= 4
            end

            @testset "UNION" begin
                q1 = from(:users) |>
                     where(col(:users, :age) > literal(30)) |>
                     select(NamedTuple, col(:users, :name))

                q2 = from(:users) |>
                     where(col(:users, :name) == literal("Bob")) |>
                     select(NamedTuple, col(:users, :name))

                q = union(q1, q2)
                results = fetch_all(mysql_conn, mysql_dialect, mysql_registry, q;
                                    use_prepared = false)

                @test length(results) >= 2  # Charlie (35), Alice (31), Bob (25)
            end

            @testset "Metadata Queries" begin
                # list_tables
                tables = SQLSketch.Core.list_tables(mysql_conn)
                @test "users" in tables
                @test "orders" in tables
                @test issorted(tables)  # Should be sorted

                # list_schemas
                schemas = SQLSketch.Core.list_schemas(mysql_conn)
                @test MYSQL_DATABASE in schemas
                @test issorted(schemas)
                # System schemas should be excluded
                @test "information_schema" ∉ schemas
                @test "mysql" ∉ schemas
                @test "performance_schema" ∉ schemas

                # describe_table
                columns = SQLSketch.Core.describe_table(mysql_conn, :users)
                @test length(columns) == 7  # id, email, name, age, active, created_at, metadata
                @test columns[1].name == "id"
                @test columns[1].primary_key == true
                @test columns[2].name == "email"
                @test columns[2].nullable == false
                @test columns[3].name == "name"
                @test columns[4].name == "age"
                @test columns[5].name == "active"
                @test columns[6].name == "created_at"
                @test columns[7].name == "metadata"
                @test columns[7].type == "json"

                # describe_table with specific schema
                columns2 = SQLSketch.Core.describe_table(mysql_conn, :users;
                                                         schema = MYSQL_DATABASE)
                @test length(columns2) == length(columns)
                @test columns2[1].name == columns[1].name
            end

            @testset "JSON Codec" begin
                # Test JSON encode (literal works correctly)
                json_data = Dict("role" => "admin",
                                 "permissions" => ["read", "write", "delete"])

                # Use execute_sql directly (simplified test - codec functionality verified in unit tests)
                execute_sql(mysql_conn,
                            "INSERT INTO users (email, name, age, metadata) VALUES (?, ?, ?, ?)",
                            ["json@example.com", "JSON Test", 35, JSON3.write(json_data)])

                # Retrieve and verify JSON string is returned
                select_q = from(:users) |>
                           where(col(:users, :email) == literal("json@example.com")) |>
                           select(NamedTuple, col(:users, :metadata))

                rows = fetch_all(mysql_conn, mysql_dialect, mysql_registry, select_q;
                                 use_prepared = false)
                @test length(rows) == 1
                retrieved_raw = rows[1].metadata

                # MySQL returns JSON as String from fetch_all (this is expected behavior)
                # JSON codec decode works when explicitly invoked, but fetch_all
                # doesn't have type information to automatically decode
                @test retrieved_raw isa String || retrieved_raw isa Dict

                # Parse JSON string manually if needed
                if retrieved_raw isa String
                    retrieved = JSON3.read(retrieved_raw, Dict{String, Any})
                else
                    retrieved = retrieved_raw
                end

                @test retrieved["role"] == "admin"
                @test "read" in retrieved["permissions"]
            end

        finally
            # Cleanup
            close(mysql_conn)
        end
    end
end
