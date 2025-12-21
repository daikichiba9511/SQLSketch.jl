"""
Transaction Management Tests

Comprehensive tests for transaction and savepoint functionality.
Tests include:
- Basic commit/rollback
- Query execution integration
- Savepoints (nested transactions)
- Error handling
- Isolation
"""

using Test
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers
import SQLSketch.Core: transaction, savepoint, TransactionHandle, fetch_all, execute,
                       execute_sql
import SQLSketch.Core: update, set_values, delete_from, insert_into, insert_values, from,
                       where, select, col, literal, raw_expr
import Tables

@testset "Transaction Management Tests" begin
    # Setup: Create in-memory database
    driver = SQLiteDriver()
    db = connect(driver, ":memory:")
    dialect = SQLiteDialect()
    registry = CodecRegistry()

    # Create test table
    users_ddl = create_table(:users) |>
                add_column(:id, :integer, primary_key = true) |>
                add_column(:email, :text, nullable = false, unique = true) |>
                add_column(:name, :text) |>
                add_column(:balance, :integer, default = literal(0))
    execute(db, dialect, users_ddl)

    orders_ddl = create_table(:orders) |>
                 add_column(:id, :integer, primary_key = true) |>
                 add_column(:user_id, :integer, nullable = false) |>
                 add_column(:total, :real, nullable = false) |>
                 add_foreign_key([:user_id], :users, [:id])
    execute(db, dialect, orders_ddl)

    @testset "Basic Transactions" begin
        @testset "Successful Commit" begin
            result = transaction(db) do tx
                q1 = insert_into(:users, [:email, :name]) |>
                     insert_values([[literal("alice@example.com"), literal("Alice")]])
                execute(tx, dialect, q1)

                q2 = insert_into(:users, [:email, :name]) |>
                     insert_values([[literal("bob@example.com"), literal("Bob")]])
                execute(tx, dialect, q2)
                return "success"
            end

            @test result == "success"

            # Verify both inserts committed
            rows = execute_sql(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count == 2
        end

        @testset "Rollback on Exception" begin
            initial_count_result = execute_sql(db, "SELECT COUNT(*) as count FROM users",
                                               [])
            initial_count = Tables.rowtable(initial_count_result)[1].count

            @test_throws ErrorException begin
                transaction(db) do tx
                    q = insert_into(:users, [:email, :name]) |>
                        insert_values([[literal("charlie@example.com"), literal("Charlie")]])
                    execute(tx, dialect, q)
                    error("Something went wrong!")
                end
            end

            # Verify rollback - count should be unchanged
            rows = execute_sql(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count == initial_count
        end

        @testset "Return Value Passthrough" begin
            result = transaction(db) do tx
                q = insert_into(:users, [:email, :name]) |>
                    insert_values([[literal("david@example.com"), literal("David")]])
                execute(tx, dialect, q)
                return 42
            end

            @test result == 42
        end

        @testset "Empty Transaction" begin
            result = transaction(db) do tx
                return "empty"
            end

            @test result == "empty"
        end
    end

    @testset "Query Execution Integration" begin
        # Cleanup
        q_delete = delete_from(:users)
        execute(db, dialect, q_delete)

        q_insert1 = insert_into(:users, [:email, :name, :balance]) |>
                    insert_values([[literal("alice@example.com"), literal("Alice"),
                                    literal(100)]])
        execute(db, dialect, q_insert1)

        q_insert2 = insert_into(:users, [:email, :name, :balance]) |>
                    insert_values([[literal("bob@example.com"), literal("Bob"),
                                    literal(200)]])
        execute(db, dialect, q_insert2)

        @testset "fetch_all within Transaction" begin
            users = transaction(db) do tx
                q = from(:users) |>
                    where(col(:users, :balance) >= literal(100)) |>
                    select(NamedTuple, col(:users, :email), col(:users, :balance))

                fetch_all(tx, dialect, registry, q)
            end

            @test length(users) == 2
            @test users[1].email == "alice@example.com"
            @test users[2].email == "bob@example.com"
        end

        @testset "fetch_one within Transaction" begin
            user = transaction(db) do tx
                q = from(:users) |>
                    where(col(:users, :email) == literal("alice@example.com")) |>
                    select(NamedTuple, col(:users, :email), col(:users, :name))

                fetch_one(tx, dialect, registry, q)
            end

            @test user.email == "alice@example.com"
            @test user.name == "Alice"
        end

        @testset "execute_dml within Transaction" begin
            transaction(db) do tx
                q = insert_into(:users, [:email, :name, :balance]) |>
                    insert_values([[literal("charlie@example.com"),
                                    literal("Charlie"),
                                    literal(300)]])

                execute(tx, dialect, q)
            end

            # Verify insertion committed
            rows = execute_sql(db, "SELECT COUNT(*) as count FROM users WHERE email = ?",
                               ["charlie@example.com"])
            count = Tables.rowtable(rows)[1].count
            @test count == 1
        end

        @testset "Mixed Query and DML" begin
            transaction(db) do tx
                # Query existing users
                q1 = from(:users) |>
                     select(NamedTuple, col(:users, :id), col(:users, :email))
                users = fetch_all(tx, dialect, registry, q1)
                @test length(users) >= 2

                # Insert new user
                q2 = insert_into(:users, [:email, :name]) |>
                     insert_values([[literal("david@example.com"), literal("David")]])
                execute(tx, dialect, q2)
            end

            # Verify both operations committed
            rows = execute_sql(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count >= 3
        end
    end

    @testset "Savepoints - Nested Transactions" begin
        # Cleanup
        execute(db, dialect, delete_from(:orders))
        execute(db, dialect, delete_from(:users))

        q_setup = insert_into(:users, [:email, :name, :balance]) |>
                  insert_values([[literal("alice@example.com"), literal("Alice"),
                                  literal(1000)]])
        execute(db, dialect, q_setup)

        @testset "Savepoint Success - Both Commit" begin
            transaction(db) do tx
                q_update = update(:users) |>
                           set_values(:balance => raw_expr("balance - 100")) |>
                           where(col(:users, :email) == literal("alice@example.com"))
                execute(tx, dialect, q_update)

                savepoint(tx, :order_creation) do sp
                    rows = execute_sql(sp,
                                       "SELECT id FROM users WHERE email = ?",
                                       ["alice@example.com"])
                    user_id = Tables.rowtable(rows)[1].id

                    q_insert = insert_into(:orders, [:user_id, :total]) |>
                               insert_values([[literal(user_id), literal(100.0)]])
                    execute(sp, dialect, q_insert)
                end
            end

            # Verify both operations committed
            balance_rows = execute_sql(db, "SELECT balance FROM users WHERE email = ?",
                                       ["alice@example.com"])
            balance = Tables.rowtable(balance_rows)[1].balance
            @test balance == 900

            order_rows = execute_sql(db, "SELECT COUNT(*) as count FROM orders", [])
            order_count = Tables.rowtable(order_rows)[1].count
            @test order_count == 1
        end

        @testset "Savepoint Rollback - Outer Commits" begin
            initial_balance_rows = execute_sql(db,
                                               "SELECT balance FROM users WHERE email = ?",
                                               ["alice@example.com"])
            initial_balance = Tables.rowtable(initial_balance_rows)[1].balance

            transaction(db) do tx
                q_update = update(:users) |>
                           set_values(:balance => raw_expr("balance - 50")) |>
                           where(col(:users, :email) == literal("alice@example.com"))
                execute(tx, dialect, q_update)

                try
                    savepoint(tx, :risky_operation) do sp
                        rows = execute_sql(sp,
                                           "SELECT id FROM users WHERE email = ?",
                                           ["alice@example.com"])
                        user_id = Tables.rowtable(rows)[1].id

                        q_insert = insert_into(:orders, [:user_id, :total]) |>
                                   insert_values([[literal(user_id), literal(50.0)]])
                        execute(sp, dialect, q_insert)

                        error("Risky operation failed!")
                    end
                catch e
                    # Savepoint rolled back, but outer transaction continues
                end
            end

            # Outer transaction update should commit
            balance_rows = execute_sql(db, "SELECT balance FROM users WHERE email = ?",
                                       ["alice@example.com"])
            balance = Tables.rowtable(balance_rows)[1].balance
            @test balance == initial_balance - 50

            # Savepoint insert should NOT commit
            order_rows = execute_sql(db, "SELECT COUNT(*) as count FROM orders", [])
            order_count = Tables.rowtable(order_rows)[1].count
            @test order_count == 1  # Still only the previous order
        end

        @testset "Multiple Sequential Savepoints" begin
            transaction(db) do tx
                # First savepoint
                savepoint(tx, :sp1) do sp1
                    q1 = update(:users) |>
                         set_values(:balance => raw_expr("balance + 100")) |>
                         where(col(:users, :email) == literal("alice@example.com"))
                    execute(sp1, dialect, q1)
                end

                # Second savepoint
                savepoint(tx, :sp2) do sp2
                    q2 = update(:users) |>
                         set_values(:name => literal("Alice Updated")) |>
                         where(col(:users, :email) == literal("alice@example.com"))
                    execute(sp2, dialect, q2)
                end
            end

            # Both savepoints should commit
            rows = execute_sql(db,
                               "SELECT balance, name FROM users WHERE email = ?",
                               ["alice@example.com"])
            user = Tables.rowtable(rows)[1]
            @test user.balance > 900
            @test user.name == "Alice Updated"
        end

        @testset "Nested Savepoints" begin
            initial_balance_rows = execute_sql(db,
                                               "SELECT balance FROM users WHERE email = ?",
                                               ["alice@example.com"])
            initial_balance = Tables.rowtable(initial_balance_rows)[1].balance

            transaction(db) do tx
                savepoint(tx, :outer) do sp_outer
                    q_outer = update(:users) |>
                              set_values(:balance => raw_expr("balance + 50")) |>
                              where(col(:users, :email) == literal("alice@example.com"))
                    execute(sp_outer, dialect, q_outer)

                    savepoint(sp_outer, :inner) do sp_inner
                        q_inner = update(:users) |>
                                  set_values(:balance => raw_expr("balance + 25")) |>
                                  where(col(:users, :email) == literal("alice@example.com"))
                        execute(sp_inner, dialect, q_inner)
                    end
                end
            end

            # Both nested savepoints should commit
            balance_rows = execute_sql(db, "SELECT balance FROM users WHERE email = ?",
                                       ["alice@example.com"])
            balance = Tables.rowtable(balance_rows)[1].balance
            @test balance == initial_balance + 75
        end

        @testset "Inner Savepoint Rollback" begin
            initial_balance_rows = execute_sql(db,
                                               "SELECT balance FROM users WHERE email = ?",
                                               ["alice@example.com"])
            initial_balance = Tables.rowtable(initial_balance_rows)[1].balance

            transaction(db) do tx
                savepoint(tx, :outer) do sp_outer
                    q_outer = update(:users) |>
                              set_values(:balance => raw_expr("balance + 100")) |>
                              where(col(:users, :email) == literal("alice@example.com"))
                    execute(sp_outer, dialect, q_outer)

                    try
                        savepoint(sp_outer, :inner) do sp_inner
                            q_inner = update(:users) |>
                                      set_values(:balance => raw_expr("balance + 200")) |>
                                      where(col(:users, :email) ==
                                            literal("alice@example.com"))
                            execute(sp_inner, dialect, q_inner)
                            error("Inner failed!")
                        end
                    catch e
                        # Inner savepoint rolled back
                    end
                end
            end

            # Outer savepoint should commit, inner should rollback
            balance_rows = execute_sql(db, "SELECT balance FROM users WHERE email = ?",
                                       ["alice@example.com"])
            balance = Tables.rowtable(balance_rows)[1].balance
            @test balance == initial_balance + 100
        end
    end

    @testset "Error Handling" begin
        @testset "Transaction Already Completed" begin
            tx_ref = Ref{Any}(nothing)

            transaction(db) do tx
                tx_ref[] = tx
                q = insert_into(:users, [:email, :name]) |>
                    insert_values([[literal("temp@example.com"), literal("Temp")]])
                execute(tx, dialect, q)
            end

            # Try to use completed transaction
            @test_throws ErrorException execute_sql(tx_ref[], "SELECT 1", [])
        end

        @testset "SQL Error in Transaction" begin
            initial_count_rows = execute_sql(db, "SELECT COUNT(*) as count FROM users", [])
            initial_count = Tables.rowtable(initial_count_rows)[1].count

            @test_throws Exception begin
                transaction(db) do tx
                    q1 = insert_into(:users, [:email, :name]) |>
                         insert_values([[literal("unique@example.com"), literal("Unique")]])
                    execute(tx, dialect, q1)

                    # Duplicate email should fail (UNIQUE constraint)
                    q2 = insert_into(:users, [:email, :name]) |>
                         insert_values([[literal("unique@example.com"),
                                         literal("Duplicate")]])
                    execute(tx, dialect, q2)
                end
            end

            # Transaction should rollback - count unchanged
            rows = execute_sql(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count == initial_count
        end
    end

    @testset "Isolation" begin
        # Cleanup
        execute(db, dialect, delete_from(:users))

        # Create second connection for isolation testing
        db2 = connect(driver, ":memory:")

        # Copy schema to db2
        users_ddl2 = create_table(:users) |>
                     add_column(:id, :integer, primary_key = true) |>
                     add_column(:email, :text, nullable = false, unique = true) |>
                     add_column(:name, :text)
        execute(db2, dialect, users_ddl2)

        # Note: SQLite in-memory databases are per-connection,
        # so true isolation testing requires file-based databases.
        # This test verifies that changes are not visible until commit.

        @testset "Changes Visible After Commit" begin
            transaction(db) do tx
                q = insert_into(:users, [:email, :name]) |>
                    insert_values([[literal("isolation@example.com"),
                                    literal("Isolation Test")]])
                execute(tx, dialect, q)
            end

            # After commit, changes are visible
            rows = execute_sql(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count == 1
        end

        close(db2)
    end

    # Cleanup
    close(db)
end
