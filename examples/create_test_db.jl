"""
Create a persistent SQLite database for manual inspection

This script creates a file-based SQLite database that you can inspect
using the sqlite3 command-line tool.

After running this script, you can inspect the database with:
    sqlite3 examples/test.db
    sqlite> .tables
    sqlite> .schema users
    sqlite> SELECT * FROM users;
"""

using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers
using Dates

println("Creating persistent SQLite database...")
println("=" ^ 60)

# Create file-based database
db_path = joinpath(@__DIR__, "test.db")
println("Database path: $db_path")

# Remove existing database if it exists
if isfile(db_path)
    rm(db_path)
    println("✓ Removed existing database")
end

driver = SQLiteDriver()
db = connect(driver, db_path)
println("✓ Connected to database")

# Create users table
println("\nCreating 'users' table...")
execute(db, """
    CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        age INTEGER,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL
    )
""")
println("✓ Table 'users' created")

# Insert test data
println("\nInserting test data...")
users_data = [
    ("Alice", "alice@example.com", 30, 1, "2025-01-01 10:00:00"),
    ("Bob", "bob@example.com", 25, 1, "2025-01-02 11:00:00"),
    ("Charlie", "charlie@example.com", 35, 0, "2025-01-03 12:00:00"),
    ("Diana", "diana@example.com", 28, 1, "2025-01-04 13:00:00"),
    ("Eve", "eve@example.com", 32, 1, "2025-01-05 14:00:00"),
]

for (name, email, age, is_active, created_at) in users_data
    execute(db, """
        INSERT INTO users (name, email, age, is_active, created_at)
        VALUES (?, ?, ?, ?, ?)
    """, [name, email, age, is_active, created_at])
    println("  ✓ Inserted: $name")
end

# Create posts table (to demonstrate JOIN capability)
println("\nCreating 'posts' table...")
execute(db, """
    CREATE TABLE posts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        content TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
    )
""")
println("✓ Table 'posts' created")

# Insert posts data
println("\nInserting posts data...")
posts_data = [
    (1, "First Post", "Hello, World!", "2025-01-06 09:00:00"),
    (1, "Second Post", "Julia is awesome", "2025-01-07 10:00:00"),
    (2, "Bob's Post", "Testing SQLSketch", "2025-01-08 11:00:00"),
    (4, "Diana's Thoughts", "Loving this framework", "2025-01-09 12:00:00"),
    (5, "Eve's Update", "Working on new features", "2025-01-10 13:00:00"),
]

for (user_id, title, content, created_at) in posts_data
    execute(db, """
        INSERT INTO posts (user_id, title, content, created_at)
        VALUES (?, ?, ?, ?)
    """, [user_id, title, content, created_at])
    println("  ✓ Inserted: $title")
end

# Verify data
println("\nVerifying data...")
result = execute(db, "SELECT COUNT(*) as count FROM users", [])
for row in result
    println("  Users count: $(row.count)")
end

result = execute(db, "SELECT COUNT(*) as count FROM posts", [])
for row in result
    println("  Posts count: $(row.count)")
end

# Close connection
SQLSketch.Core.close(db)
println("\n✓ Database connection closed")

println("\n" * "=" ^ 60)
println("✅ Database created successfully!")
println("=" ^ 60)

println("\nYou can now inspect the database with:")
println("  cd examples/")
println("  sqlite3 test.db")
println("\nUseful SQLite commands:")
println("  .tables              # List all tables")
println("  .schema users        # Show users table schema")
println("  .schema posts        # Show posts table schema")
println("  SELECT * FROM users; # Show all users")
println("  SELECT * FROM posts; # Show all posts")
println("  .mode column         # Better column formatting")
println("  .headers on          # Show column headers")
println("  .quit                # Exit sqlite3")

println("\nOr run a JOIN query:")
println("  SELECT u.name, p.title, p.created_at")
println("  FROM users u")
println("  JOIN posts p ON u.id = p.user_id")
println("  ORDER BY p.created_at;")
