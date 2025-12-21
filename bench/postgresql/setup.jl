# PostgreSQL Benchmark Setup
# Provides common utilities and data for PostgreSQL benchmarks

using SQLSketch
using SQLSketch: raw_expr, execute
using BenchmarkTools
using Dates
using UUIDs

"""
    get_postgresql_connstring() -> String

Returns PostgreSQL connection string from environment variable or default.

**Security Note:** Default credentials are for local development/testing only.
Never use these credentials in production.

Set SQLSKETCH_PG_CONN environment variable to customize:

```bash
export SQLSKETCH_PG_CONN="host=localhost port=5432 dbname=mydb user=myuser password=mypass"
```

Default (safe for local development):

  - host=localhost (not accessible externally)
  - database=sqlsketch_bench (test database only)
  - user/password=postgres (Docker default)
"""
function get_postgresql_connstring()::String
    # Default credentials for local development/testing only
    # Override with SQLSKETCH_PG_CONN environment variable for custom setups
    default = "host=localhost port=5432 dbname=sqlsketch_bench user=postgres password=postgres"
    return get(ENV, "SQLSKETCH_PG_CONN", default)
end

"""
    setup_postgresql_db() -> Connection

Creates a PostgreSQL connection and sets up test schema.

Note: This requires a running PostgreSQL server. Use Docker:

```bash
docker run --name sqlsketch-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=sqlsketch_bench -p 5432:5432 -d postgres:15
```
"""
function setup_postgresql_db()
    driver = SQLSketch.PostgreSQLDriver()
    connstring = get_postgresql_connstring()

    println("Connecting to PostgreSQL...")
    println("  Connection: $connstring")

    try
        conn = connect(driver, connstring)
        println("✓ Connected to PostgreSQL")
        return conn
    catch e
        println("❌ Failed to connect to PostgreSQL")
        println("Error: $e")
        println()
        println("To run PostgreSQL benchmarks, start a PostgreSQL server:")
        println("  docker run --name sqlsketch-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=sqlsketch_bench -p 5432:5432 -d postgres:15")
        println()
        println("Or set SQLSKETCH_PG_CONN environment variable:")
        println("  export SQLSKETCH_PG_CONN=\"host=localhost port=5432 dbname=mydb user=myuser password=mypass\"")
        rethrow(e)
    end
end

"""
    populate_postgresql_db(conn::Connection)::Nothing

Populates PostgreSQL database with sample data for benchmarking.

Creates:

  - users table (1000 rows) with UUID primary keys
  - posts table (5000 rows) with JSONB metadata
"""
function populate_postgresql_db(conn::Connection)::Nothing
    dialect = SQLSketch.PostgreSQLDialect()

    # Drop existing tables
    try
        execute_sql(conn, "DROP TABLE IF EXISTS posts CASCADE")
        execute_sql(conn, "DROP TABLE IF EXISTS users CASCADE")
    catch
        # Ignore errors if tables don't exist
    end

    # Create users table with PostgreSQL-specific types
    execute_sql(conn, """
        CREATE TABLE users (
            id UUID PRIMARY KEY,
            email TEXT NOT NULL,
            name TEXT NOT NULL,
            active BOOLEAN NOT NULL,
            created_at TIMESTAMP NOT NULL
        )
    """)

    # Create posts table with JSONB
    execute_sql(conn, """
        CREATE TABLE posts (
            id SERIAL PRIMARY KEY,
            user_id UUID NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            metadata JSONB,
            tags TEXT[],
            published BOOLEAN NOT NULL,
            created_at TIMESTAMP NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """)

    println("Inserting sample data...")

    # Insert 1000 users
    user_uuids = [uuid4() for _ in 1:1000]
    for (i, user_id) in enumerate(user_uuids)
        q = insert_into(:users, [:id, :email, :name, :active, :created_at]) |>
            insert_values([[literal(user_id),
                            literal("user$i@example.com"),
                            literal("User $i"),
                            literal(i % 2 == 0),
                            literal(DateTime(2024, 1, 1) + Day(i))]])

        execute(conn, dialect, q)
    end

    # Insert 5000 posts with JSONB metadata
    for i in 1:5000
        user_id = user_uuids[(i % 1000) + 1]
        metadata = Dict("views" => i * 10, "likes" => i % 100, "category" => "cat_$(i % 5)")
        tags = ["tag_$(i % 10)", "tag_$(i % 20)"]

        q = insert_into(:posts,
                        [:user_id, :title, :content, :metadata, :tags, :published,
                         :created_at]) |>
            insert_values([[literal(user_id),
                            literal("Post $i"),
                            literal("Content for post $i"),
                            literal(metadata),  # JSONB
                            literal(tags),      # TEXT[]
                            literal(i % 3 == 0),
                            literal(DateTime(2024, 1, 1) + Day(i))]])

        execute(conn, dialect, q)
    end

    println("✓ Sample data inserted (1000 users, 5000 posts)")

    return nothing
end

"""
    get_postgresql_queries()::Dict{Symbol, Function}

Returns PostgreSQL-specific sample queries for benchmarking.
"""
function get_postgresql_queries()::Dict{Symbol, Function}
    return Dict(:simple_select => () -> begin
                    from(:users) |>
                    where(col(:users, :active) == literal(true)) |>
                    select(NamedTuple, col(:users, :id), col(:users, :email))
                end,
                :join_query => () -> begin
                    from(:users) |>
                    inner_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
                    where(col(:posts, :published) == literal(true)) |>
                    select(NamedTuple,
                           col(:users, :name),
                           col(:posts, :title),
                           col(:posts, :created_at))
                end,
                :filter_and_project => () -> begin
                    from(:posts) |>
                    where(col(:posts, :published) == literal(true)) |>
                    select(NamedTuple,
                           col(:posts, :user_id),
                           col(:posts, :title))
                end,
                :complex_query => () -> begin
                    from(:users) |>
                    left_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
                    where((col(:users, :active) == literal(true)) &
                          (col(:posts, :published) == literal(true))) |>
                    order_by(col(:posts, :created_at); desc = true) |>
                    limit(100) |>
                    select(NamedTuple,
                           col(:users, :id),
                           col(:users, :name),
                           col(:users, :email),
                           col(:posts, :title),
                           col(:posts, :created_at))
                end,
                :order_and_limit => () -> begin
                    from(:posts) |>
                    where(col(:posts, :published) == literal(true)) |>
                    order_by(col(:posts, :created_at); desc = true) |>
                    limit(10) |>
                    select(NamedTuple, col(:posts, :id), col(:posts, :title))
                end,

                # PostgreSQL-specific: JSONB query
                :jsonb_query => () -> begin
                    from(:posts) |>
                    where(raw_expr("metadata->>'category' = 'cat_1'")) |>
                    select(NamedTuple,
                           col(:posts, :title),
                           col(:posts, :metadata))
                end,

                # PostgreSQL-specific: Array query
                :array_query => () -> begin
                    from(:posts) |>
                    where(raw_expr("'tag_5' = ANY(tags)")) |>
                    select(NamedTuple,
                           col(:posts, :title),
                           col(:posts, :tags))
                end)
end

"""
    cleanup_postgresql_db(conn::Connection)::Nothing

Drops all test tables.
"""
function cleanup_postgresql_db(conn::Connection)::Nothing
    try
        execute_sql(conn, "DROP TABLE IF EXISTS posts CASCADE")
        execute_sql(conn, "DROP TABLE IF EXISTS users CASCADE")
        println("✓ Test tables cleaned up")
    catch e
        @warn "Failed to cleanup tables" exception=e
    end
    return nothing
end
