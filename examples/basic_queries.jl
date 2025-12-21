"""
# Basic Queries Examples

This file demonstrates basic query patterns in SQLSketch.jl, including:
- Simple WHERE and ORDER BY
- JOIN queries
- INSERT with parameters
- Transactions
- Migrations
- DDL operations
"""

using SQLSketch          # Core query building functions
using SQLSketch.Drivers  # Database drivers

println("="^80)
println("Basic Query Examples")
println("="^80)

# Setup: Create an in-memory SQLite database
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
registry = CodecRegistry()

# Create tables using DDL API
println("\n[1] Creating tables with DDL API...")
users_table = create_table(:users) |>
              add_column(:id, :integer; primary_key = true) |>
              add_column(:name, :text; nullable = false) |>
              add_column(:email, :text; nullable = false) |>
              add_column(:age, :integer) |>
              add_column(:status, :text; default = literal("active"))

execute(db, dialect, users_table)

orders_table = create_table(:orders) |>
               add_column(:id, :integer; primary_key = true) |>
               add_column(:user_id, :integer) |>
               add_column(:total, :real) |>
               add_column(:created_at, :text) |>
               add_foreign_key([:user_id], :users, [:id])

execute(db, dialect, orders_table)
println("✓ Tables created")

# Example 1: Basic Query with WHERE and ORDER BY
println("\n[2] Example 1: Basic Query with WHERE and ORDER BY")
println("-"^80)

# Insert test data
execute(db, dialect,
        insert_into(:users, [:name, :email, :age, :status]) |>
        insert_values([[literal("Alice"), literal("alice@example.com"), literal(30),
                        literal("active")],
                       [literal("Bob"), literal("bob@example.com"), literal(17),
                        literal("active")],
                       [literal("Charlie"), literal("charlie@example.com"), literal(25),
                        literal("inactive")],
                       [literal("Diana"), literal("diana@example.com"), literal(35),
                        literal("active")]]))

q1 = from(:users) |>
     where(col(:users, :age) > literal(18)) |>
     select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :age)) |>
     order_by(col(:users, :name))

sql1, _ = compile(dialect, q1)
println("SQL: ", sql1)
println("\nResults:")
for row in fetch_all(db, dialect, registry, q1)
    println("  $row")
end

# Example 2: JOIN Query
println("\n[3] Example 2: JOIN Query")
println("-"^80)

# Insert orders
execute(db, dialect,
        insert_into(:orders, [:user_id, :total, :created_at]) |>
        insert_values([[literal(1), literal(99.99), literal("2025-01-01")],
                       [literal(1), literal(149.99), literal("2025-01-02")],
                       [literal(4), literal(59.99), literal("2025-01-03")]]))

q2 = from(:users) |>
     inner_join(:orders, col(:orders, :user_id) == col(:users, :id)) |>
     where(col(:users, :status) == literal("active")) |>
     select(NamedTuple, col(:users, :name), col(:orders, :total), col(:orders, :created_at))

sql2, _ = compile(dialect, q2)
println("SQL: ", sql2)
println("\nResults:")
for row in fetch_all(db, dialect, registry, q2)
    println("  $row")
end

# Example 3: INSERT with Parameters
println("\n[4] Example 3: INSERT with Parameters")
println("-"^80)

insert_q = insert_into(:users, [:name, :email, :age, :status]) |>
           insert_values([[param(String, :name), param(String, :email), param(Int, :age),
                           param(String, :status)]])

sql3, _ = compile(dialect, insert_q)
println("SQL: ", sql3)

result = execute(db, dialect, insert_q,
                 (name = "Eve", email = "eve@example.com", age = 28, status = "active"))
println("✓ Inserted 1 row with parameters")

# Verify insert
verify_q = from(:users) |>
           where(col(:users, :name) == literal("Eve")) |>
           select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email))

println("Verification:")
for row in fetch_all(db, dialect, registry, verify_q)
    println("  $row")
end

# Example 4: Transaction with Multiple Operations
println("\n[5] Example 4: Transaction with Multiple Operations")
println("-"^80)

transaction(db) do tx
    # Insert user
    execute(tx, dialect,
            insert_into(:users, [:name, :email, :age]) |>
            insert_values([[literal("Frank"), literal("frank@example.com"), literal(42)]]))

    println("  ✓ Inserted user in transaction")

    # Insert order for the user (id will be 6)
    execute(tx, dialect,
            insert_into(:orders, [:user_id, :total]) |>
            insert_values([[literal(6), literal(299.99)]]))

    println("  ✓ Inserted order in transaction")
    println("  ✓ Transaction will commit automatically")
end

println("Transaction completed successfully")

# Example 5: UPDATE and DELETE
println("\n[6] Example 5: UPDATE and DELETE operations")
println("-"^80)

# UPDATE
update_q = update(:users) |>
           set(:status => literal("inactive")) |>
           where(col(:users, :age) < literal(20))

sql_update, _ = compile(dialect, update_q)
println("UPDATE SQL: ", sql_update)
execute(db, dialect, update_q)
println("✓ Updated users with age < 20")

# DELETE
delete_q = delete_from(:users) |>
           where(col(:users, :status) == literal("inactive"))

sql_delete, _ = compile(dialect, delete_q)
println("DELETE SQL: ", sql_delete)
execute(db, dialect, delete_q)
println("✓ Deleted inactive users")

# Final count
count_q = from(:users) |>
          select(NamedTuple, func(:COUNT, [col(:users, :id)]))

println("\nFinal user count:")
for row in fetch_all(db, dialect, registry, count_q)
    println("  Total users: ", row[1])
end

# Cleanup
close(db)

println("\n" * "="^80)
println("✅ All basic query examples completed successfully!")
println("="^80)
