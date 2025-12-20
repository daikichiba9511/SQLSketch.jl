"""
# PostgreSQL Example

This file demonstrates PostgreSQL-specific features in SQLSketch.jl:
- PostgreSQL connection
- Native UUID, JSONB, ARRAY types
- PostgreSQL-specific SQL generation
- Transactions and savepoints

Prerequisites:
- PostgreSQL server running
- Set environment variables:
  export PGHOST=localhost
  export PGPORT=5432
  export PGDATABASE=sqlsketch_test
  export PGUSER=postgres
  export PGPASSWORD=your_password

Or modify the connection string below.
"""

using SQLSketch          # Core query building functions
using SQLSketch.Drivers  # Database drivers
using UUIDs
using JSON3

println("="^80)
println("PostgreSQL Example")
println("="^80)

# Connection string (modify as needed)
conn_string = get(ENV, "DATABASE_URL", "postgresql://localhost/sqlsketch_test")

println("\n[1] Connecting to PostgreSQL...")
println("Connection string: $conn_string")

driver = PostgreSQLDriver()
db = try
    connect(driver, conn_string)
catch e
    println("❌ Failed to connect to PostgreSQL:")
    println("  Error: ", sprint(showerror, e))
    println("\nPlease ensure:")
    println("  1. PostgreSQL is running")
    println("  2. Database 'sqlsketch_test' exists")
    println("  3. Connection credentials are correct")
    println("\nYou can create the database with:")
    println("  psql -c 'CREATE DATABASE sqlsketch_test;'")
    exit(1)
end

println("✓ Connected to PostgreSQL")

dialect = PostgreSQLDialect()
registry = CodecRegistry()

# Clean up existing tables
println("\n[2] Cleaning up existing tables...")
try
    execute(db, "DROP TABLE IF EXISTS posts CASCADE")
    execute(db, "DROP TABLE IF EXISTS users CASCADE")
    println("✓ Dropped existing tables")
catch e
    println("Note: Tables may not have existed")
end

# Create tables with PostgreSQL-specific types
println("\n[3] Creating tables with PostgreSQL-specific types...")

users_table = create_table(:users) |>
              add_column(:id, :uuid; primary_key = true) |>
              add_column(:email, :text; nullable = false) |>
              add_column(:name, :text; nullable = false) |>
              add_column(:metadata, :jsonb) |>
              add_column(:tags, :text_array) |>
              add_column(:created_at, :timestamp_with_timezone)

execute(db, dialect, users_table)

posts_table = create_table(:posts) |>
              add_column(:id, :serial; primary_key = true) |>
              add_column(:user_id, :uuid; nullable = false) |>
              add_column(:title, :text; nullable = false) |>
              add_column(:content, :text) |>
              add_foreign_key([:user_id], :users, [:id])

execute(db, dialect, posts_table)
println("✓ Tables created with UUID, JSONB, and ARRAY types")

# Insert data with PostgreSQL-specific types
println("\n[4] Inserting data with PostgreSQL-specific types...")

user_id = uuid4()
metadata = Dict("age" => 30, "city" => "Tokyo", "verified" => true)
tags = ["developer", "julia", "postgres"]

insert_user = insert_into(:users, [:id, :email, :name, :metadata, :tags, :created_at]) |>
              insert_values([[param(UUID, :id),
                              param(String, :email),
                              param(String, :name),
                              param(Dict, :metadata),
                              param(Vector{String}, :tags),
                              param(String, :created_at)]])

execute(db, dialect, insert_user,
        (id = user_id,
         email = "alice@example.com",
         name = "Alice",
         metadata = metadata,
         tags = tags,
         created_at = "2025-01-01 10:00:00+00"))

println("✓ Inserted user with UUID: $user_id")

# Query with JSONB operators
println("\n[5] Querying with JSONB operators...")

# Note: For advanced JSONB queries, you may need to use raw SQL or extend the expression system
q = from(:users) |>
    where(col(:users, :email) == literal("alice@example.com")) |>
    select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :metadata),
           col(:users, :tags))

sql_str, _ = compile(dialect, q)
println("SQL: ", sql_str)

println("\nResults:")
for row in fetch_all(db, dialect, registry, q)
    println("  ID: ", row.id)
    println("  Name: ", row.name)
    println("  Metadata: ", row.metadata)
    println("  Tags: ", row.tags)
end

# Transaction with savepoint
println("\n[6] Demonstrating transaction with savepoint...")

transaction(db) do tx
    # Insert a post
    execute(tx, dialect,
            insert_into(:posts, [:user_id, :title, :content]) |>
            insert_values([[literal(user_id), literal("First Post"),
                            literal("Hello PostgreSQL!")]]))

    println("  ✓ Inserted post in transaction")

    # Create savepoint
    savepoint(tx, :sp1) do sp
        # Insert another post
        execute(sp, dialect,
                insert_into(:posts, [:user_id, :title, :content]) |>
                insert_values([[literal(user_id), literal("Second Post"),
                                literal("Testing savepoints")]]))

        println("  ✓ Inserted post in savepoint")
        # This will commit the savepoint
    end

    println("  ✓ Savepoint committed")
    # This will commit the transaction
end

println("✓ Transaction completed")

# Verify posts
println("\n[7] Verifying posts...")
posts_q = from(:posts) |>
          select(NamedTuple, col(:posts, :id), col(:posts, :title), col(:posts, :content))

println("Posts:")
for row in fetch_all(db, dialect, registry, posts_q)
    println("  $row")
end

# RETURNING clause (PostgreSQL-specific)
println("\n[8] Using RETURNING clause...")

insert_with_returning = insert_into(:posts, [:user_id, :title, :content]) |>
                        insert_values([[param(UUID, :user_id),
                                        param(String, :title),
                                        param(String, :content)]]) |>
                        returning(col(:posts, :id), col(:posts, :title))

result = fetch_all(db, dialect, registry, insert_with_returning,
                   (user_id = user_id, title = "Third Post", content = "Using RETURNING"))

println("✓ Inserted and returned:")
for row in result
    println("  ID: $(row.id), Title: $(row.title)")
end

# Cleanup
close(db)

println("\n" * "="^80)
println("✅ PostgreSQL example completed successfully!")
println("="^80)

println("\nPostgreSQL-specific features demonstrated:")
println("  - UUID primary keys")
println("  - JSONB for structured data")
println("  - ARRAY types (text[])")
println("  - TIMESTAMP WITH TIME ZONE")
println("  - RETURNING clause")
println("  - Savepoints (nested transactions)")
