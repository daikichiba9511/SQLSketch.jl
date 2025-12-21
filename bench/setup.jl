# Benchmark Setup
# Provides common utilities and data for all benchmarks

using SQLSketch
using BenchmarkTools
using SQLite
using Dates
using UUIDs

"""
    populate_db(db::SQLite.DB)::Nothing

Populates a SQLite database with sample data for benchmarking.
"""
function populate_db(db::SQLite.DB)::Nothing

    # Create users table
    SQLite.execute(db, """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            email TEXT NOT NULL,
            name TEXT NOT NULL,
            active INTEGER NOT NULL,
            created_at TEXT NOT NULL
        )
    """)

    # Create posts table
    SQLite.execute(db, """
        CREATE TABLE posts (
            id INTEGER PRIMARY KEY,
            user_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            published INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """)

    # Insert sample data - 1000 users
    stmt = SQLite.Stmt(db, """
        INSERT INTO users (email, name, active, created_at)
        VALUES (?, ?, ?, ?)
    """)

    for i in 1:1000
        SQLite.execute(stmt,
                       ["user$i@example.com",
                        "User $i",
                        i % 2,
                        string(DateTime(2024, 1, 1) + Day(i))])
    end

    # Insert sample data - 5000 posts
    stmt = SQLite.Stmt(db, """
        INSERT INTO posts (user_id, title, content, published, created_at)
        VALUES (?, ?, ?, ?, ?)
    """)

    for i in 1:5000
        user_id = (i % 1000) + 1
        SQLite.execute(stmt,
                       [user_id,
                        "Post $i",
                        "Content for post $i",
                        i % 3 == 0 ? 1 : 0,
                        string(DateTime(2024, 1, 1) + Day(i))])
    end

    return nothing
end

"""
    setup_sqlite_db()::SQLite.DB

Creates an in-memory SQLite database with sample data for benchmarking.
"""
function setup_sqlite_db()::SQLite.DB
    db = SQLite.DB(":memory:")
    populate_db(db)
    return db
end

"""
    get_sample_queries()::Dict{Symbol, Function}

Returns a collection of sample query builders for benchmarking.
Each function takes no arguments and returns a Query AST.
"""
function get_sample_queries()::Dict{Symbol, Function}
    return Dict(:simple_select => () -> begin
                    from(:users) |>
                    where(col(:users, :active) == literal(1)) |>
                    select(NamedTuple, col(:users, :id), col(:users, :email))
                end,
                :join_query => () -> begin
                    from(:users) |>
                    inner_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
                    where(col(:posts, :published) == literal(1)) |>
                    select(NamedTuple,
                           col(:users, :name),
                           col(:posts, :title),
                           col(:posts, :created_at))
                end,
                :filter_and_project => () -> begin
                    from(:posts) |>
                    where(col(:posts, :published) == literal(1)) |>
                    select(NamedTuple,
                           col(:posts, :user_id),
                           col(:posts, :title))
                end,
                :complex_query => () -> begin
                    from(:users) |>
                    left_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
                    where((col(:users, :active) == literal(1)) &
                          (col(:posts, :published) == literal(1))) |>
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
                    where(col(:posts, :published) == literal(1)) |>
                    order_by(col(:posts, :created_at); desc = true) |>
                    limit(10) |>
                    select(NamedTuple, col(:posts, :id), col(:posts, :title))
                end)
end

"""
    get_raw_sql_queries()::Dict{Symbol, String}

Returns equivalent raw SQL queries for comparison benchmarks.
"""
function get_raw_sql_queries()::Dict{Symbol, String}
    return Dict(:simple_select => """
                    SELECT users.id, users.email
                    FROM users
                    WHERE users.active = 1
                """, :join_query => """
                         SELECT users.name, posts.title, posts.created_at
                         FROM users
                         INNER JOIN posts ON users.id = posts.user_id
                         WHERE posts.published = 1
                     """, :filter_and_project => """
                              SELECT posts.user_id, posts.title
                              FROM posts
                              WHERE posts.published = 1
                          """, :complex_query => """
                                   SELECT users.id, users.name, users.email,
                                          posts.title, posts.created_at
                                   FROM users
                                   LEFT JOIN posts ON users.id = posts.user_id
                                   WHERE users.active = 1 AND posts.published = 1
                                   ORDER BY posts.created_at DESC
                                   LIMIT 100
                               """, :order_and_limit => """
                                        SELECT posts.id, posts.title
                                        FROM posts
                                        WHERE posts.published = 1
                                        ORDER BY posts.created_at DESC
                                        LIMIT 10
                                    """)
end
