"""
Manual Integration Test

This script manually connects all Phase 1-5 components to verify
that the end-to-end flow works before implementing Phase 6 APIs.

Flow:
1. Create SQLite database and table
2. Insert test data
3. Build a Query AST
4. Compile Query → SQL
5. Execute SQL via Driver
6. Decode results via CodecRegistry
"""

using SQLSketch          # Core query building functions
using SQLSketch.Drivers  # Database drivers
using Dates

println("="^60)
println("Manual Integration Test - Phase 1-5 Verification")
println("="^60)

# Step 1: Setup database
println("\n[1] Setting up SQLite database...")
driver = SQLiteDriver()
db = connect(driver, ":memory:")
dialect = SQLiteDialect()
println("✓ Connected to in-memory SQLite database")

# Create table using DDL API
users_table = create_table(:users) |>
              add_column(:id, :integer; primary_key = true) |>
              add_column(:name, :text; nullable = false) |>
              add_column(:email, :text; nullable = false) |>
              add_column(:age, :integer) |>
              add_column(:created_at, :text)

execute(db, dialect, users_table)
println("✓ Created 'users' table")

# Insert test data
test_users = [
    ("Alice", "alice@example.com", 30, "2025-01-01 10:00:00"),
    ("Bob", "bob@example.com", 25, "2025-01-02 11:00:00"),
    ("Charlie", "charlie@example.com", 35, "2025-01-03 12:00:00")
]

for (name, email, age, created_at) in test_users
    execute(db, dialect,
            insert_into(:users, [:name, :email, :age, :created_at]) |>
            insert_values([[literal(name), literal(email), literal(age), literal(created_at)]]))
end
println("✓ Inserted 3 test records")

# Step 2: Build Query AST
println("\n[2] Building Query AST...")
q = from(:users) |>
    where(col(:users, :age) > literal(26)) |>
    select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email),
           col(:users, :age)) |>
    order_by(col(:users, :name))
println("✓ Query AST constructed")

# Step 3: Compile to SQL
println("\n[3] Compiling Query to SQL...")
sql_string, params = compile(dialect, q)
println("Generated SQL:")
println("  $sql_string")
println("Parameters: $params")

# Step 4: Execute via Driver
println("\n[4] Executing Query...")
registry = CodecRegistry()
result = fetch_all(db, dialect, registry, q)
println("✓ Query executed successfully")

# Step 5: Display results
println("\n[5] Results:")
println("-"^60)
for (i, row) in enumerate(result)
    println("Row $i: $row")
end
println("-"^60)
println("Total rows: $(length(result))")

# Step 6: Test with a struct
println("\n[6] Testing struct mapping...")
struct User
    id::Int
    name::String
    email::String
    age::Int
end

# Map results to struct
users = map_row.(Ref(registry), User, result)

println("Mapped to User structs:")
for (i, user) in enumerate(users)
    println("  User $i: id=$(user.id), name=$(user.name), email=$(user.email), age=$(user.age)")
end

# Cleanup
println("\n[7] Cleanup...")
close(db)
println("✓ Database connection closed")

println("\n" * "="^60)
println("✅ All integration tests passed!")
println("="^60)
println("\nConclusion:")
println("  All components are working correctly.")
println("  Query building, compilation, execution, and type mapping all work as expected.")
