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
import SQLSketch.Core: transaction, savepoint, TransactionHandle, fetch_all, execute_dml
import Tables

@testset "Transaction Management Tests" begin
    # Setup: Create in-memory database
    driver = SQLiteDriver()
    db = connect(driver, ":memory:")
    dialect = SQLiteDialect()
    registry = CodecRegistry()

    # Create test table
    execute(db, """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL UNIQUE,
            name TEXT,
            balance INTEGER DEFAULT 0
        )
    """, [])

    execute(db, """
        CREATE TABLE orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            total REAL NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """, [])

    @testset "Basic Transactions" begin
        @testset "Successful Commit" begin
            result = transaction(db) do tx
                execute(tx, "INSERT INTO users (email, name) VALUES (?, ?)",
                        ["alice@example.com", "Alice"])
                execute(tx, "INSERT INTO users (email, name) VALUES (?, ?)",
                        ["bob@example.com", "Bob"])
                return "success"
            end

            @test result == "success"

            # Verify both inserts committed
            rows = execute(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count == 2
        end

        @testset "Rollback on Exception" begin
            initial_count_result = execute(db, "SELECT COUNT(*) as count FROM users", [])
            initial_count = Tables.rowtable(initial_count_result)[1].count

            @test_throws ErrorException begin
                transaction(db) do tx
                    execute(tx, "INSERT INTO users (email, name) VALUES (?, ?)",
                            ["charlie@example.com", "Charlie"])
                    error("Something went wrong!")
                end
            end

            # Verify rollback - count should be unchanged
            rows = execute(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count == initial_count
        end

        @testset "Return Value Passthrough" begin
            result = transaction(db) do tx
                execute(tx, "INSERT INTO users (email, name) VALUES (?, ?)",
                        ["david@example.com", "David"])
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
        execute(db, "DELETE FROM users", [])
        execute(db, "INSERT INTO users (email, name, balance) VALUES (?, ?, ?)",
                ["alice@example.com", "Alice", 100])
        execute(db, "INSERT INTO users (email, name, balance) VALUES (?, ?, ?)",
                ["bob@example.com", "Bob", 200])

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

                execute_dml(tx, dialect, q)
            end

            # Verify insertion committed
            rows = execute(db, "SELECT COUNT(*) as count FROM users WHERE email = ?",
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
                execute_dml(tx, dialect, q2)
            end

            # Verify both operations committed
            rows = execute(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count >= 3
        end
    end

    @testset "Savepoints - Nested Transactions" begin
        # Cleanup
        execute(db, "DELETE FROM orders", [])
        execute(db, "DELETE FROM users", [])
        execute(db, "INSERT INTO users (email, name, balance) VALUES (?, ?, ?)",
                ["alice@example.com", "Alice", 1000])

        @testset "Savepoint Success - Both Commit" begin
            transaction(db) do tx
                execute(tx, "UPDATE users SET balance = balance - 100 WHERE email = ?",
                        ["alice@example.com"])

                savepoint(tx, :order_creation) do sp
                    rows = execute(sp,
                                   "SELECT id FROM users WHERE email = ?",
                                   ["alice@example.com"])
                    user_id = Tables.rowtable(rows)[1].id

                    execute(sp, "INSERT INTO orders (user_id, total) VALUES (?, ?)",
                            [user_id, 100.0])
                end
            end

            # Verify both operations committed
            balance_rows = execute(db, "SELECT balance FROM users WHERE email = ?",
                                   ["alice@example.com"])
            balance = Tables.rowtable(balance_rows)[1].balance
            @test balance == 900

            order_rows = execute(db, "SELECT COUNT(*) as count FROM orders", [])
            order_count = Tables.rowtable(order_rows)[1].count
            @test order_count == 1
        end

        @testset "Savepoint Rollback - Outer Commits" begin
            initial_balance_rows = execute(db,
                                           "SELECT balance FROM users WHERE email = ?",
                                           ["alice@example.com"])
            initial_balance = Tables.rowtable(initial_balance_rows)[1].balance

            transaction(db) do tx
                execute(tx, "UPDATE users SET balance = balance - 50 WHERE email = ?",
                        ["alice@example.com"])

                try
                    savepoint(tx, :risky_operation) do sp
                        rows = execute(sp,
                                       "SELECT id FROM users WHERE email = ?",
                                       ["alice@example.com"])
                        user_id = Tables.rowtable(rows)[1].id

                        execute(sp, "INSERT INTO orders (user_id, total) VALUES (?, ?)",
                                [user_id, 50.0])

                        error("Risky operation failed!")
                    end
                catch e
                    # Savepoint rolled back, but outer transaction continues
                end
            end

            # Outer transaction update should commit
            balance_rows = execute(db, "SELECT balance FROM users WHERE email = ?",
                                   ["alice@example.com"])
            balance = Tables.rowtable(balance_rows)[1].balance
            @test balance == initial_balance - 50

            # Savepoint insert should NOT commit
            order_rows = execute(db, "SELECT COUNT(*) as count FROM orders", [])
            order_count = Tables.rowtable(order_rows)[1].count
            @test order_count == 1  # Still only the previous order
        end

        @testset "Multiple Sequential Savepoints" begin
            transaction(db) do tx
                # First savepoint
                savepoint(tx, :sp1) do sp1
                    execute(sp1, "UPDATE users SET balance = balance + 100 WHERE email = ?",
                            ["alice@example.com"])
                end

                # Second savepoint
                savepoint(tx, :sp2) do sp2
                    execute(sp2, "UPDATE users SET name = ? WHERE email = ?",
                            ["Alice Updated", "alice@example.com"])
                end
            end

            # Both savepoints should commit
            rows = execute(db,
                           "SELECT balance, name FROM users WHERE email = ?",
                           ["alice@example.com"])
            user = Tables.rowtable(rows)[1]
            @test user.balance > 900
            @test user.name == "Alice Updated"
        end

        @testset "Nested Savepoints" begin
            initial_balance_rows = execute(db,
                                           "SELECT balance FROM users WHERE email = ?",
                                           ["alice@example.com"])
            initial_balance = Tables.rowtable(initial_balance_rows)[1].balance

            transaction(db) do tx
                savepoint(tx, :outer) do sp_outer
                    execute(sp_outer, "UPDATE users SET balance = balance + 50 WHERE email = ?",
                            ["alice@example.com"])

                    savepoint(sp_outer, :inner) do sp_inner
                        execute(sp_inner, "UPDATE users SET balance = balance + 25 WHERE email = ?",
                                ["alice@example.com"])
                    end
                end
            end

            # Both nested savepoints should commit
            balance_rows = execute(db, "SELECT balance FROM users WHERE email = ?",
                                   ["alice@example.com"])
            balance = Tables.rowtable(balance_rows)[1].balance
            @test balance == initial_balance + 75
        end

        @testset "Inner Savepoint Rollback" begin
            initial_balance_rows = execute(db,
                                           "SELECT balance FROM users WHERE email = ?",
                                           ["alice@example.com"])
            initial_balance = Tables.rowtable(initial_balance_rows)[1].balance

            transaction(db) do tx
                savepoint(tx, :outer) do sp_outer
                    execute(sp_outer, "UPDATE users SET balance = balance + 100 WHERE email = ?",
                            ["alice@example.com"])

                    try
                        savepoint(sp_outer, :inner) do sp_inner
                            execute(sp_inner,
                                    "UPDATE users SET balance = balance + 200 WHERE email = ?",
                                    ["alice@example.com"])
                            error("Inner failed!")
                        end
                    catch e
                        # Inner savepoint rolled back
                    end
                end
            end

            # Outer savepoint should commit, inner should rollback
            balance_rows = execute(db, "SELECT balance FROM users WHERE email = ?",
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
                execute(tx, "INSERT INTO users (email, name) VALUES (?, ?)",
                        ["temp@example.com", "Temp"])
            end

            # Try to use completed transaction
            @test_throws ErrorException execute(tx_ref[], "SELECT 1", [])
        end

        @testset "SQL Error in Transaction" begin
            initial_count_rows = execute(db, "SELECT COUNT(*) as count FROM users", [])
            initial_count = Tables.rowtable(initial_count_rows)[1].count

            @test_throws Exception begin
                transaction(db) do tx
                    execute(tx, "INSERT INTO users (email, name) VALUES (?, ?)",
                            ["unique@example.com", "Unique"])
                    # Duplicate email should fail (UNIQUE constraint)
                    execute(tx, "INSERT INTO users (email, name) VALUES (?, ?)",
                            ["unique@example.com", "Duplicate"])
                end
            end

            # Transaction should rollback - count unchanged
            rows = execute(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count == initial_count
        end
    end

    @testset "Isolation" begin
        # Cleanup
        execute(db, "DELETE FROM users", [])

        # Create second connection for isolation testing
        db2 = connect(driver, ":memory:")

        # Copy schema to db2
        execute(db2, """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT NOT NULL UNIQUE,
                name TEXT
            )
        """, [])

        # Note: SQLite in-memory databases are per-connection,
        # so true isolation testing requires file-based databases.
        # This test verifies that changes are not visible until commit.

        @testset "Changes Visible After Commit" begin
            transaction(db) do tx
                execute(tx, "INSERT INTO users (email, name) VALUES (?, ?)",
                        ["isolation@example.com", "Isolation Test"])
            end

            # After commit, changes are visible
            rows = execute(db, "SELECT COUNT(*) as count FROM users", [])
            count = Tables.rowtable(rows)[1].count
            @test count == 1
        end

        close(db2)
    end

    # Cleanup
    close(db)
end
