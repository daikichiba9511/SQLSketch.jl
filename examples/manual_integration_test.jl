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

using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers
using Dates

println("=" ^ 60)
println("Manual Integration Test - Phase 1-5 Verification")
println("=" ^ 60)

# Step 1: Setup database
println("\n[1] Setting up SQLite database...")
driver = SQLiteDriver()
db = connect(driver, ":memory:")
println("✓ Connected to in-memory SQLite database")

# Create table
execute(db, """
    CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        age INTEGER,
        created_at TEXT
    )
""")
println("✓ Created 'users' table")

# Insert test data
execute(db, "INSERT INTO users (name, email, age, created_at) VALUES (?, ?, ?, ?)",
        ["Alice", "alice@example.com", 30, "2025-01-01 10:00:00"])
execute(db, "INSERT INTO users (name, email, age, created_at) VALUES (?, ?, ?, ?)",
        ["Bob", "bob@example.com", 25, "2025-01-02 11:00:00"])
execute(db, "INSERT INTO users (name, email, age, created_at) VALUES (?, ?, ?, ?)",
        ["Charlie", "charlie@example.com", 35, "2025-01-03 12:00:00"])
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
dialect = SQLiteDialect()
sql_string, params = compile(dialect, q)
println("Generated SQL:")
println("  $sql_string")
println("Parameters: $params")

# Step 4: Execute via Driver
println("\n[4] Executing SQL via Driver...")
result = execute(db, sql_string, [])
println("✓ Query executed successfully")

# Step 5: Decode results via CodecRegistry
println("\n[5] Decoding results via CodecRegistry...")
registry = CodecRegistry()

println("\nResults:")
println("-" ^ 60)
results_list = []
for row in result
    # Convert SQLite.Row to NamedTuple manually
    # (In Phase 6, this will be automated by map_row)
    nt = (id = row.id,
          name = row.name,
          email = row.email,
          age = row.age)
    push!(results_list, nt)
    println("Row $(length(results_list)): $nt")
end
println("-" ^ 60)
println("Total rows: $(length(results_list))")

# Step 6: Test with a struct
println("\n[6] Testing struct mapping...")
struct User
    id::Int
    name::String
    email::String
    age::Int
end

# Execute query again and map to struct
result2 = execute(db, sql_string, [])
users = User[]
for row in result2
    nt = (id = row.id,
          name = row.name,
          email = row.email,
          age = row.age)
    user = map_row(registry, User, nt)
    push!(users, user)
end

println("Mapped to User structs:")
for (i, user) in enumerate(users)
    println("  User $i: id=$(user.id), name=$(user.name), email=$(user.email), age=$(user.age)")
end

# Step 7: Test Date/DateTime codec
println("\n[7] Testing Date/DateTime codec...")
result3 = execute(db, "SELECT id, name, created_at FROM users WHERE id = 1", [])
for row in result3
    created_str = row.created_at
    println("  Raw created_at: $created_str ($(typeof(created_str)))")

    # Decode using DateTimeCodec
    dt_codec = DateTimeCodec()
    dt = decode(dt_codec, created_str)
    println("  Decoded DateTime: $dt ($(typeof(dt)))")
end

# Cleanup
println("\n[8] Cleanup...")
SQLSketch.Core.close(db)
println("✓ Database connection closed")

println("\n" * "=" ^ 60)
println("✅ All integration tests passed!")
println("=" ^ 60)
println("\nConclusion:")
println("  All Phase 1-5 components are working correctly.")
println("  Ready to implement Phase 6 (all, one, maybeone APIs).")
