"""
PostgreSQL Integration Tests

Tests SQLSketch against a real PostgreSQL database to ensure:
1. Queries work correctly
2. Results match SQLite where applicable
3. PostgreSQL-specific features work
4. Transactions and DML operations work correctly

Requires: Docker Compose with PostgreSQL running
Connection: postgresql://test_user:test_password@localhost:5432/sqlsketch_test

To start PostgreSQL:
  cd test/integration && docker-compose up -d

To stop PostgreSQL:
  cd test/integration && docker-compose down
"""

using Test
using SQLSketch
using SQLSketch.Core: from, where, select, join, order_by, limit, offset, distinct,
                      group_by, having
using SQLSketch.Core: insert_into, values, update, set, delete_from, returning
using SQLSketch.Core: col, literal, param, func
using SQLSketch.Extras: p_
using SQLSketch.Core: cte, with, union, intersect, except
using SQLSketch.Core: on_conflict_do_nothing, on_conflict_do_update
using SQLSketch.Core: transaction, savepoint
using SQLSketch.Core: create_table, add_column, drop_table, create_index, drop_index
using SQLSketch.Core: compile, fetch_all, fetch_one, fetch_maybe, execute_dml, execute_ddl,
                      sql
using SQLSketch.Core: CodecRegistry, register!
using SQLSketch: PostgreSQLDialect, PostgreSQLDriver, SQLiteDialect, SQLiteDriver
using Dates

# Connection configuration
# Use 127.0.0.1 instead of localhost to force IPv4 connection
# Use port 5433 to avoid conflict with host PostgreSQL
const PG_CONNINFO = "host=127.0.0.1 port=5433 dbname=sqlsketch_test user=test_user password=test_password"

"""
    pg_available() -> Bool

Check if PostgreSQL is available for testing.
"""
function pg_available()::Bool
    try
        driver = PostgreSQLDriver()
        conn = connect(driver, PG_CONNINFO)
        close(conn)
        return true
    catch e
        @warn "PostgreSQL not available for testing" exception=e
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
        execute_ddl(conn, dialect, drop_table(:orders; if_exists = true, cascade = true))
        execute_ddl(conn, dialect, drop_table(:users; if_exists = true, cascade = true))
    catch
    end

    # Create users table
    users_ddl = create_table(:users; if_not_exists = true) |>
                add_column(:id, :integer; primary_key = true) |>
                add_column(:email, :text; nullable = false, unique = true) |>
                add_column(:name, :text; nullable = false) |>
                add_column(:age, :integer) |>
                add_column(:active, :boolean; default = literal(true)) |>
                add_column(:created_at, :timestamp)

    execute_ddl(conn, dialect, users_ddl)

    # Create orders table
    orders_ddl = create_table(:orders; if_not_exists = true) |>
                 add_column(:id, :integer; primary_key = true) |>
                 add_column(:user_id, :integer) |>
                 add_column(:total, :real) |>
                 add_column(:status, :text) |>
                 add_column(:created_at, :timestamp)

    execute_ddl(conn, dialect, orders_ddl)
end

"""
    insert_test_data(conn, dialect)

Insert test data into tables.
"""
function insert_test_data(conn, dialect)
    # Insert users
    users_data = [(1, "alice@example.com", "Alice", 30, true, DateTime(2024, 1, 1)),
                  (2, "bob@example.com", "Bob", 25, true, DateTime(2024, 1, 2)),
                  (3, "charlie@example.com", "Charlie", 35, false, DateTime(2024, 1, 3)),
                  (4, "diana@example.com", "Diana", 28, true, DateTime(2024, 1, 4))]

    for (id, email, name, age, active, created_at) in users_data
        q = insert_into(:users, [:id, :email, :name, :age, :active, :created_at]) |>
            values([[literal(id), literal(email), literal(name), literal(age),
                     literal(active),
                     literal(created_at)]])
        execute_dml(conn, dialect, q)
    end

    # Insert orders
    orders_data = [(1, 1, 100.50, "completed", DateTime(2024, 1, 10)),
                   (2, 1, 50.25, "pending", DateTime(2024, 1, 11)),
                   (3, 2, 75.00, "completed", DateTime(2024, 1, 12)),
                   (4, 2, 200.00, "completed", DateTime(2024, 1, 13)),
                   (5, 4, 150.00, "cancelled", DateTime(2024, 1, 14))]

    for (id, user_id, total, status, created_at) in orders_data
        q = insert_into(:orders, [:id, :user_id, :total, :status, :created_at]) |>
            values([[literal(id), literal(user_id), literal(total), literal(status),
                     literal(created_at)]])
        execute_dml(conn, dialect, q)
    end
end

# Skip all tests if PostgreSQL is not available
if !pg_available()
    @warn "Skipping PostgreSQL integration tests - PostgreSQL not available"
    @testset "PostgreSQL Integration (Skipped)" begin
        @test_broken false  # Mark as expected failure when PostgreSQL is not available
    end
else
    @testset "PostgreSQL Integration Tests" begin
        pg_driver = PostgreSQLDriver()
        pg_dialect = PostgreSQLDialect()
        pg_conn = connect(pg_driver, PG_CONNINFO)
        pg_registry = CodecRegistry()  # Create registry for PostgreSQL

        sqlite_driver = SQLiteDriver()
        sqlite_dialect = SQLiteDialect()
        sqlite_conn = connect(sqlite_driver, ":memory:")
        sqlite_registry = CodecRegistry()  # Create registry for SQLite

        try
            # Setup
            @testset "Setup - Create Tables" begin
                setup_test_tables(pg_conn, pg_dialect)
                setup_test_tables(sqlite_conn, sqlite_dialect)

                insert_test_data(pg_conn, pg_dialect)
                insert_test_data(sqlite_conn, sqlite_dialect)

                # Verify data was inserted
                q = from(:users)
                pg_results = fetch_all(pg_conn, pg_dialect, pg_registry, q)
                sqlite_results = fetch_all(sqlite_conn, sqlite_dialect, sqlite_registry, q)

                @test length(pg_results) == 4
                @test length(sqlite_results) == 4
            end

            @testset "Comparison: Basic SELECT" begin
                q = from(:users) |>
                    where(p_.active == literal(true)) |>
                    select(NamedTuple, p_.id, p_.email, p_.name) |>
                    order_by(col(:users, :id))

                pg_results = fetch_all(pg_conn, pg_dialect, pg_registry, q)
                sqlite_results = fetch_all(sqlite_conn, sqlite_dialect, sqlite_registry, q)

                @test length(pg_results) == length(sqlite_results)
                @test length(pg_results) == 3  # Alice, Bob, Diana

                # Compare each row
                for i in 1:length(pg_results)
                    @test pg_results[i].id == sqlite_results[i].id
                    @test pg_results[i].email == sqlite_results[i].email
                    @test pg_results[i].name == sqlite_results[i].name
                end
            end

            @testset "Comparison: JOIN" begin
                q = from(:users) |>
                    join(:orders, col(:users, :id) == col(:orders, :user_id);
                         kind = :inner) |>
                    where(col(:orders, :status) == literal("completed")) |>
                    select(NamedTuple, col(:users, :name), col(:orders, :total)) |>
                    order_by(col(:users, :id)) |>
                    order_by(col(:orders, :id))  # Add secondary sort for deterministic order

                pg_results = fetch_all(pg_conn, pg_dialect, pg_registry, q)
                sqlite_results = fetch_all(sqlite_conn, sqlite_dialect, sqlite_registry, q)

                @test length(pg_results) == length(sqlite_results)
                @test length(pg_results) == 3  # Alice(1), Bob(2)

                for i in 1:length(pg_results)
                    @test pg_results[i].name == sqlite_results[i].name
                    @test pg_results[i].total ≈ sqlite_results[i].total
                end
            end

            @testset "Comparison: Aggregates" begin
                q = from(:orders) |>
                    where(col(:orders, :status) == literal("completed")) |>
                    select(NamedTuple,
                           func(:COUNT, [col(:orders, :id)]),
                           func(:SUM, [col(:orders, :total)]),
                           func(:AVG, [col(:orders, :total)]))

                pg_results = fetch_one(pg_conn, pg_dialect, pg_registry, q)
                sqlite_results = fetch_one(sqlite_conn, sqlite_dialect, sqlite_registry, q)

                @test pg_results[1] == sqlite_results[1]  # COUNT
                @test pg_results[2] ≈ sqlite_results[2]  # SUM
                @test pg_results[3] ≈ sqlite_results[3]  # AVG
            end

            @testset "Comparison: GROUP BY / HAVING" begin
                q = from(:orders) |>
                    select(NamedTuple,
                           col(:orders, :user_id),
                           func(:COUNT, [col(:orders, :id)]),
                           func(:SUM, [col(:orders, :total)])) |>
                    group_by(col(:orders, :user_id)) |>
                    having(func(:COUNT, [col(:orders, :id)]) > literal(1)) |>
                    order_by(col(:orders, :user_id))

                pg_results = fetch_all(pg_conn, pg_dialect, pg_registry, q)
                sqlite_results = fetch_all(sqlite_conn, sqlite_dialect, sqlite_registry, q)

                @test length(pg_results) == length(sqlite_results)
                @test length(pg_results) == 2  # user_id 1 and 2 have multiple orders

                for i in 1:length(pg_results)
                    @test pg_results[i][1] == sqlite_results[i][1]  # user_id
                    @test pg_results[i][2] == sqlite_results[i][2]  # count
                    @test pg_results[i][3] ≈ sqlite_results[i][3]  # sum
                end
            end

            @testset "PostgreSQL: RETURNING clause" begin
                # Test INSERT RETURNING
                q = insert_into(:users, [:id, :email, :name, :age, :active]) |>
                    values([[literal(5), literal("eve@example.com"), literal("Eve"),
                             literal(32),
                             literal(true)]]) |>
                    returning(NamedTuple, p_.id, p_.email, p_.name)

                result = fetch_one(pg_conn, pg_dialect, pg_registry, q)

                @test result.id == 5
                @test result.email == "eve@example.com"
                @test result.name == "Eve"

                # Test UPDATE RETURNING
                q2 = update(:users) |>
                     set(:age => literal(33)) |>
                     where(p_.id == literal(5)) |>
                     returning(NamedTuple, p_.id, p_.age)

                result2 = fetch_one(pg_conn, pg_dialect, pg_registry, q2)

                @test result2.id == 5
                @test result2.age == 33

                # Test DELETE RETURNING
                q3 = delete_from(:users) |>
                     where(p_.id == literal(5)) |>
                     returning(NamedTuple, p_.id, p_.email)

                result3 = fetch_one(pg_conn, pg_dialect, pg_registry, q3)

                @test result3.id == 5
                @test result3.email == "eve@example.com"
            end

            @testset "PostgreSQL: UPSERT (ON CONFLICT)" begin
                # Test ON CONFLICT DO NOTHING
                q1 = insert_into(:users, [:id, :email, :name, :age, :active]) |>
                     values([[literal(1), literal("alice@example.com"),
                              literal("Alice Updated"),
                              literal(31), literal(true)]]) |>
                     on_conflict_do_nothing()

                affected = execute_dml(pg_conn, pg_dialect, q1)
                # Should not insert because id=1 already exists

                # Verify Alice's name didn't change
                verify_q = from(:users) |>
                           where(p_.id == literal(1)) |>
                           select(NamedTuple, p_.name)
                result = fetch_one(pg_conn, pg_dialect, pg_registry, verify_q)
                @test result.name == "Alice"

                # Test ON CONFLICT DO UPDATE
                q2 = insert_into(:users, [:id, :email, :name, :age]) |>
                     values([[literal(1), literal("alice@example.com"),
                              literal("Alice Updated"),
                              literal(31)]]) |>
                     on_conflict_do_update([:email], :name => col(:excluded, :name),
                                           :age => col(:excluded, :age))

                execute_dml(pg_conn, pg_dialect, q2)

                # Verify Alice's data was updated
                result2 = fetch_one(pg_conn, pg_dialect, pg_registry, verify_q)
                @test result2.name == "Alice Updated"

                verify_age_q = from(:users) |>
                               where(p_.id == literal(1)) |>
                               select(NamedTuple, p_.age)
                result3 = fetch_one(pg_conn, pg_dialect, pg_registry, verify_age_q)
                @test result3.age == 31
            end

            @testset "PostgreSQL: Transactions" begin
                # Test COMMIT
                transaction(pg_conn) do tx
                    q = insert_into(:users, [:id, :email, :name, :age, :active]) |>
                        values([[literal(6), literal("frank@example.com"), literal("Frank"),
                                 literal(40), literal(true)]])
                    execute_dml(tx, pg_dialect, q)
                end

                # Verify Frank was inserted
                verify_q = from(:users) |>
                           where(p_.id == literal(6)) |>
                           select(NamedTuple, p_.name)
                result = fetch_one(pg_conn, pg_dialect, pg_registry, verify_q)
                @test result.name == "Frank"

                # Test ROLLBACK
                try
                    transaction(pg_conn) do tx
                        q = insert_into(:users, [:id, :email, :name, :age, :active]) |>
                            values([[literal(7), literal("grace@example.com"),
                                     literal("Grace"),
                                     literal(45), literal(true)]])
                        execute_dml(tx, pg_dialect, q)

                        # Force an error to trigger rollback
                        error("Intentional error for rollback test")
                    end
                catch
                end

                # Verify Grace was NOT inserted
                verify_q2 = from(:users) |>
                            where(p_.id == literal(7))
                result2 = fetch_maybe(pg_conn, pg_dialect, pg_registry, verify_q2)
                @test result2 === nothing

                # Test SAVEPOINT
                transaction(pg_conn) do tx
                    # Insert Henry
                    q1 = insert_into(:users, [:id, :email, :name, :age, :active]) |>
                         values([[literal(8), literal("henry@example.com"),
                                  literal("Henry"),
                                  literal(50), literal(true)]])
                    execute_dml(tx, pg_dialect, q1)

                    # Savepoint - try to insert Iris but rollback
                    try
                        savepoint(tx, :sp1) do sp
                            q2 = insert_into(:users, [:id, :email, :name, :age, :active]) |>
                                 values([[literal(9), literal("iris@example.com"),
                                          literal("Iris"),
                                          literal(55), literal(true)]])
                            execute_dml(sp, pg_dialect, q2)

                            error("Rollback to savepoint")
                        end
                    catch
                    end

                    # Transaction should still be active, Henry should remain
                end

                # Verify Henry was inserted
                verify_q3 = from(:users) |>
                            where(p_.id == literal(8)) |>
                            select(NamedTuple, p_.name)
                result3 = fetch_one(pg_conn, pg_dialect, pg_registry, verify_q3)
                @test result3.name == "Henry"

                # Verify Iris was NOT inserted
                verify_q4 = from(:users) |>
                            where(p_.id == literal(9))
                result4 = fetch_maybe(pg_conn, pg_dialect, pg_registry, verify_q4)
                @test result4 === nothing
            end

            @testset "PostgreSQL: CTE" begin
                active_users_cte = cte(:active_users,
                                       from(:users) |>
                                       where(p_.active == literal(true)))

                main_q = from(:active_users) |>
                         select(NamedTuple, col(:active_users, :name)) |>
                         order_by(col(:active_users, :id))

                q = with([active_users_cte], main_q)

                results = fetch_all(pg_conn, pg_dialect, pg_registry, q)

                @test length(results) == 5  # Alice (Updated), Bob, Diana, Frank, Henry
                @test results[1].name == "Alice Updated"
                @test results[2].name == "Bob"
                @test results[3].name == "Diana"
                @test results[4].name == "Frank"
                @test results[5].name == "Henry"
            end

            @testset "PostgreSQL: Set Operations" begin
                # UNION
                q1 = from(:users) |>
                     where(p_.age > literal(30)) |>
                     select(NamedTuple, p_.name)

                q2 = from(:users) |>
                     where(p_.name == literal("Bob")) |>
                     select(NamedTuple, p_.name)

                union_q = union(q1, q2)

                results = fetch_all(pg_conn, pg_dialect, pg_registry, union_q)

                @test length(results) >= 3  # Should include Alice Updated, Charlie, Henry, and Bob
            end

        finally
            # Cleanup
            close(pg_conn)
            close(sqlite_conn)
        end
    end
end
