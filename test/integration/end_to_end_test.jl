"""
End-to-End Integration Tests

This test suite verifies the complete query execution pipeline:
  Query AST → Dialect → SQL → Driver → Execution → CodecRegistry → Results

Tests cover:
- Basic query execution (all, one, maybeone)
- Parameter binding
- Type conversion
- Error handling
- Observability (sql, explain)
"""

using Test
using SQLSketch.Drivers
using Dates
using UUIDs

# Import from SQLSketch, avoiding Base name conflicts
import SQLSketch
import SQLSketch.Core
import SQLSketch.Core: fetch_all, fetch_one, fetch_maybe, sql, explain
import SQLSketch.Core: from, where, select, order_by, limit, offset, distinct, group_by,
                       having
import SQLSketch.Core: col, literal, param, func
import SQLSketch.Core: insert_into, update, set_values, delete_from
import SQLSketch.Core: cte
import SQLSketch.Core: connect, execute_sql, execute, close
import SQLSketch.Core: ExecResult
import SQLSketch.Core: create_table, add_column, add_foreign_key
import SQLSketch: SQLiteDialect, CodecRegistry
# Use aliases to avoid Base conflicts
import SQLSketch.Core: inner_join, insert_values, with

@testset "End-to-End Integration Tests" begin
    # Setup: Create in-memory database
    driver = SQLiteDriver()
    db = connect(driver, ":memory:")
    dialect = SQLiteDialect()
    registry = CodecRegistry()

    # Create test tables
    users_ddl = create_table(:users) |>
                add_column(:id, :integer, primary_key = true) |>
                add_column(:name, :text, nullable = false) |>
                add_column(:email, :text, unique = true, nullable = false) |>
                add_column(:age, :integer) |>
                add_column(:is_active, :integer, default = literal(1)) |>
                add_column(:created_at, :text)
    execute(db, dialect, users_ddl)

    posts_ddl = create_table(:posts) |>
                add_column(:id, :integer, primary_key = true) |>
                add_column(:user_id, :integer, nullable = false) |>
                add_column(:title, :text, nullable = false) |>
                add_column(:content, :text) |>
                add_column(:published, :integer, default = literal(0)) |>
                add_foreign_key([:user_id], :users, [:id])
    execute(db, dialect, posts_ddl)

    orders_ddl = create_table(:orders) |>
                 add_column(:id, :integer, primary_key = true) |>
                 add_column(:user_id, :integer, nullable = false) |>
                 add_column(:total, :real, nullable = false) |>
                 add_column(:status, :text, nullable = false) |>
                 add_foreign_key([:user_id], :users, [:id])
    execute(db, dialect, orders_ddl)

    # Insert test data
    q1 = insert_into(:users, [:name, :email, :age, :is_active]) |>
         insert_values([[literal("Alice"), literal("alice@example.com"), literal(30),
                         literal(1)]])
    execute(db, dialect, q1)

    q2 = insert_into(:users, [:name, :email, :age, :is_active]) |>
         insert_values([[literal("Bob"), literal("bob@example.com"), literal(25),
                         literal(1)]])
    execute(db, dialect, q2)

    q3 = insert_into(:users, [:name, :email, :age, :is_active]) |>
         insert_values([[literal("Charlie"), literal("charlie@example.com"), literal(35),
                         literal(0)]])
    execute(db, dialect, q3)

    q4 = insert_into(:posts, [:user_id, :title, :content, :published]) |>
         insert_values([[literal(1), literal("First Post"), literal("Hello World"),
                         literal(1)]])
    execute(db, dialect, q4)

    q5 = insert_into(:posts, [:user_id, :title, :content, :published]) |>
         insert_values([[literal(1), literal("Second Post"), literal("More content"),
                         literal(0)]])
    execute(db, dialect, q5)

    q6 = insert_into(:posts, [:user_id, :title, :content, :published]) |>
         insert_values([[literal(2), literal("Bob's Post"), literal("Bob's content"),
                         literal(1)]])
    execute(db, dialect, q6)

    @testset "Basic Query Execution - fetch_all()" begin
        # Simple SELECT all users
        q = from(:users) |>
            select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email))

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 3
        @test results[1].name == "Alice"
        @test results[1].email == "alice@example.com"
        @test results[2].name == "Bob"
        @test results[3].name == "Charlie"
    end

    @testset "Query with WHERE clause" begin
        # Filter by age
        q = from(:users) |>
            where(col(:users, :age) > literal(26)) |>
            select(NamedTuple, col(:users, :name), col(:users, :age))

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 2  # Alice (30), Charlie (35)
        @test Base.all(r -> r.age > 26, results)
    end

    @testset "Query with ORDER BY" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :name), col(:users, :age)) |>
            order_by(col(:users, :age); desc = true)

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 3
        @test results[1].name == "Charlie"  # age 35
        @test results[2].name == "Alice"    # age 30
        @test results[3].name == "Bob"      # age 25
    end

    @testset "Query with LIMIT" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :name)) |>
            order_by(col(:users, :id)) |>
            limit(2)

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 2
        @test results[1].name == "Alice"
        @test results[2].name == "Bob"
    end

    @testset "Query with OFFSET" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :name)) |>
            order_by(col(:users, :id)) |>
            limit(2) |>
            offset(1)

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 2
        @test results[1].name == "Bob"
        @test results[2].name == "Charlie"
    end

    @testset "Query with DISTINCT" begin
        # All users have different ages, so DISTINCT should not change count
        q = from(:users) |>
            select(NamedTuple, col(:users, :age)) |>
            distinct

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 3
    end

    @testset "Query with JOIN" begin
        q = from(:users) |>
            inner_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
            select(NamedTuple,
                   col(:users, :name),
                   col(:posts, :title))

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 3  # Alice has 2 posts, Bob has 1 post
        # Note: Charlie has no posts, so won't appear in inner join
    end

    @testset "fetch_one() - Success" begin
        # Get exactly one user by email
        q = from(:users) |>
            where(col(:users, :email) == param(String, :email)) |>
            select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email))

        user = fetch_one(db, dialect, registry, q, (email = "alice@example.com",))

        @test user.name == "Alice"
        @test user.email == "alice@example.com"
    end

    @testset "fetch_one() - Error on zero rows" begin
        q = from(:users) |>
            where(col(:users, :email) == param(String, :email)) |>
            select(NamedTuple, col(:users, :id), col(:users, :name))

        @test_throws ErrorException fetch_one(db, dialect, registry, q,
                                              (email = "nonexistent@example.com",))
    end

    @testset "fetch_one() - Error on multiple rows" begin
        # Query that returns multiple users
        q = from(:users) |>
            where(col(:users, :age) > literal(20)) |>
            select(NamedTuple, col(:users, :name))

        @test_throws ErrorException fetch_one(db, dialect, registry, q)
    end

    @testset "fetch_maybe() - Returns value" begin
        q = from(:users) |>
            where(col(:users, :email) == param(String, :email)) |>
            select(NamedTuple, col(:users, :name), col(:users, :email))

        user = fetch_maybe(db, dialect, registry, q, (email = "bob@example.com",))

        @test user !== nothing
        @test user.name == "Bob"
    end

    @testset "fetch_maybe() - Returns nothing" begin
        q = from(:users) |>
            where(col(:users, :email) == param(String, :email)) |>
            select(NamedTuple, col(:users, :name))

        user = fetch_maybe(db, dialect, registry, q, (email = "nonexistent@example.com",))

        @test user === nothing
    end

    @testset "fetch_maybe() - Error on multiple rows" begin
        # Query that returns multiple users
        q = from(:users) |>
            where(col(:users, :age) > literal(20)) |>
            select(NamedTuple, col(:users, :name))

        @test_throws ErrorException fetch_maybe(db, dialect, registry, q)
    end

    @testset "Parameter Binding - Single parameter" begin
        q = from(:users) |>
            where(col(:users, :age) == param(Int, :min_age)) |>
            select(NamedTuple, col(:users, :name), col(:users, :age))

        results = fetch_all(db, dialect, registry, q, (min_age = 30,))

        @test length(results) == 1  # Alice (30)
        @test Base.all(r -> r.age == 30, results)
    end

    @testset "Parameter Binding - Multiple parameters" begin
        q = from(:users) |>
            where((col(:users, :age) >= param(Int, :min_age)) &
                  (col(:users, :age) <= param(Int, :max_age))) |>
            select(NamedTuple, col(:users, :name), col(:users, :age))

        results = fetch_all(db, dialect, registry, q, (min_age = 25, max_age = 30))

        @test length(results) == 2  # Bob (25), Alice (30)
    end

    @testset "Parameter Binding - Missing parameter error" begin
        q = from(:users) |>
            where(col(:users, :age) == param(Int, :min_age)) |>
            select(NamedTuple, col(:users, :name))

        # Missing required parameter
        @test_throws ErrorException fetch_all(db, dialect, registry, q, NamedTuple())
    end

    @testset "Type Conversion - Integers" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :id), col(:users, :age))

        results = fetch_all(db, dialect, registry, q)

        @test Base.all(r -> r.id isa Integer, results)
        @test Base.all(r -> r.age isa Integer, results)
    end

    @testset "Type Conversion - Strings" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :name), col(:users, :email))

        results = fetch_all(db, dialect, registry, q)

        @test Base.all(r -> r.name isa String, results)
        @test Base.all(r -> r.email isa String, results)
    end

    @testset "Type Conversion - Booleans (SQLite integers)" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :is_active))

        results = fetch_all(db, dialect, registry, q)

        # SQLite stores booleans as integers (0 or 1)
        @test Base.all(r -> r.is_active in [0, 1], results)
    end

    @testset "Type Conversion to Struct" begin
        struct User
            id::Int
            name::String
            email::String
        end

        q = from(:users) |>
            where(col(:users, :id) == param(Int, :id)) |>
            select(User, col(:users, :id), col(:users, :name), col(:users, :email))

        user = fetch_one(db, dialect, registry, q, (id = 1,))

        @test user isa User
        @test user.id == 1
        @test user.name == "Alice"
        @test user.email == "alice@example.com"
    end

    @testset "sql() - SQL inspection" begin
        q = from(:users) |>
            where(col(:users, :age) > param(Int, :min_age)) |>
            select(NamedTuple, col(:users, :name), col(:users, :email))

        sql_str = sql(dialect, q)

        @test occursin("SELECT", sql_str)
        @test occursin("FROM", sql_str)
        @test occursin("WHERE", sql_str)
        @test occursin("`users`", sql_str)
        @test occursin("`name`", sql_str)
        @test occursin("`email`", sql_str)
        @test occursin("`age`", sql_str)
        @test occursin("?", sql_str)  # Parameter placeholder
    end

    @testset "explain() - Query plan" begin
        q = from(:users) |>
            where(col(:users, :age) > literal(25)) |>
            select(NamedTuple, col(:users, :name))

        plan = explain(db, dialect, q)

        @test plan isa String
        @test !isempty(plan)
        # EXPLAIN output should contain query plan information
    end

    @testset "Complex Query - Multiple operations" begin
        # Complex query: JOIN, WHERE, ORDER BY, LIMIT
        q = from(:users) |>
            inner_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
            where(col(:posts, :published) == literal(1)) |>
            select(NamedTuple,
                   col(:users, :name),
                   col(:posts, :title)) |>
            order_by(col(:posts, :id)) |>
            limit(2)

        results = fetch_all(db, dialect, registry, q)

        @test length(results) <= 2
        @test Base.all(r -> haskey(r, :name) && haskey(r, :title), results)
    end

    @testset "Empty Result Set" begin
        q = from(:users) |>
            where(col(:users, :age) > literal(100)) |>
            select(NamedTuple, col(:users, :name))

        results = fetch_all(db, dialect, registry, q)

        @test length(results) == 0
        @test results isa Vector
    end

    # DML Operations Tests
    @testset "DML Operations" begin
        # Setup: Create a test table for DML operations
        execute_sql(db,
                    "CREATE TABLE dml_test (id INTEGER PRIMARY KEY, name TEXT, value INTEGER)",
                    [])

        @testset "INSERT with literals" begin
            q = insert_into(:dml_test, [:name, :value]) |>
                insert_values([[literal("test1"), literal(100)]])

            execute(db, dialect, q)

            # Verify insertion
            verify_q = from(:dml_test) |>
                       where(col(:dml_test, :name) == literal("test1")) |>
                       select(NamedTuple, col(:dml_test, :name), col(:dml_test, :value))

            results = fetch_all(db, dialect, registry, verify_q)
            @test length(results) == 1
            @test results[1][:name] == "test1"
            @test results[1][:value] == 100
        end

        @testset "INSERT with parameters" begin
            q = insert_into(:dml_test, [:name, :value]) |>
                insert_values([[param(String, :name), param(Int, :value)]])

            execute(db, dialect, q, (name = "test2", value = 200))

            # Verify insertion
            verify_q = from(:dml_test) |>
                       where(col(:dml_test, :name) == param(String, :name)) |>
                       select(NamedTuple, col(:dml_test, :name), col(:dml_test, :value))

            results = fetch_all(db, dialect, registry, verify_q, (name = "test2",))
            @test length(results) == 1
            @test results[1][:value] == 200
        end

        @testset "INSERT multiple rows" begin
            q = insert_into(:dml_test, [:name, :value]) |>
                insert_values([[literal("test3"), literal(300)],
                               [literal("test4"), literal(400)]])

            execute(db, dialect, q)

            # Verify insertions
            verify_q = from(:dml_test) |>
                       where(col(:dml_test, :value) >= literal(300)) |>
                       select(NamedTuple, col(:dml_test, :name), col(:dml_test, :value))

            results = fetch_all(db, dialect, registry, verify_q)
            @test length(results) == 2
        end

        @testset "UPDATE with WHERE" begin
            q = update(:dml_test) |>
                set_values(:value => param(Int, :new_value)) |>
                where(col(:dml_test, :name) == param(String, :name))

            execute(db, dialect, q, (new_value = 999, name = "test1"))

            # Verify update
            verify_q = from(:dml_test) |>
                       where(col(:dml_test, :name) == literal("test1")) |>
                       select(NamedTuple, col(:dml_test, :value))

            results = fetch_all(db, dialect, registry, verify_q)
            @test length(results) == 1
            @test results[1][:value] == 999
        end

        @testset "DELETE with WHERE" begin
            q = delete_from(:dml_test) |>
                where(col(:dml_test, :name) == param(String, :name))

            execute(db, dialect, q, (name = "test2",))

            # Verify deletion
            verify_q = from(:dml_test) |>
                       where(col(:dml_test, :name) == literal("test2")) |>
                       select(NamedTuple, col(:dml_test, :name))

            results = fetch_all(db, dialect, registry, verify_q)
            @test length(results) == 0
        end

        @testset "DELETE with complex WHERE" begin
            q = delete_from(:dml_test) |>
                where(col(:dml_test, :value) < literal(500))

            execute(db, dialect, q)

            # Verify remaining rows
            verify_q = from(:dml_test) |> select(NamedTuple, col(:dml_test, :name))
            results = fetch_all(db, dialect, registry, verify_q)

            # Only test1 (999) should remain
            @test length(results) == 1
            @test results[1][:name] == "test1"
        end

        # Cleanup DML test table
        execute_sql(db, "DROP TABLE dml_test", [])
    end

    @testset "CTE End-to-End Execution" begin
        # Setup fresh test data for CTE tests
        execute_sql(db, "DROP TABLE IF EXISTS orders", [])
        execute_sql(db, "DROP TABLE IF EXISTS posts", [])
        execute_sql(db, "DROP TABLE IF EXISTS users", [])

        execute_sql(db, """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                email TEXT UNIQUE NOT NULL,
                age INTEGER,
                is_active INTEGER DEFAULT 1,
                created_at TEXT
            )
        """, [])

        execute_sql(db, """
            CREATE TABLE posts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                content TEXT,
                published INTEGER DEFAULT 0,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """, [])

        execute_sql(db, """
            CREATE TABLE orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                total REAL NOT NULL,
                status TEXT NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """, [])

        execute_sql(db,
                    "INSERT INTO users (name, email, age, is_active) VALUES ('Alice', 'alice@example.com', 30, 1)",
                    [])
        execute_sql(db,
                    "INSERT INTO users (name, email, age, is_active) VALUES ('Bob', 'bob@example.com', 25, 0)",
                    [])
        execute_sql(db,
                    "INSERT INTO users (name, email, age, is_active) VALUES ('Charlie', 'charlie@example.com', 35, 1)",
                    [])

        @testset "Simple CTE execution" begin

            # CTE: filter active users
            cte_query = from(:users) |> where(col(:users, :is_active) == literal(1))
            c = cte(:active_users, cte_query)

            # Main query: select from CTE
            main_query = from(:active_users) |>
                         select(NamedTuple, col(:active_users, :name),
                                col(:active_users, :age)) |>
                         order_by(col(:active_users, :age))

            q = with(c, main_query)

            # Execute
            results = fetch_all(db, dialect, registry, q)

            @test length(results) == 2
            @test results[1][:name] == "Alice"
            @test results[1][:age] == 30
            @test results[2][:name] == "Charlie"
            @test results[2][:age] == 35
        end

        @testset "CTE with parameter binding" begin
            # CTE with parameter
            cte_query = from(:users) |>
                        where(col(:users, :age) > param(Int, :min_age))
            c = cte(:filtered_users, cte_query)

            main_query = from(:filtered_users) |>
                         select(NamedTuple, col(:filtered_users, :name)) |>
                         order_by(col(:filtered_users, :name))

            q = with(c, main_query)

            # Execute with parameters
            results = fetch_all(db, dialect, registry, q, (min_age = 28,))

            @test length(results) == 2
            @test results[1][:name] == "Alice"
            @test results[2][:name] == "Charlie"
        end

        @testset "Multiple CTEs with JOIN" begin
            # Ensure fresh test data
            q_delete = delete_from(:orders)
            execute(db, dialect, q_delete)

            q_insert1 = insert_into(:orders, [:user_id, :total, :status]) |>
                        insert_values([[literal(1), literal(150.0), literal("completed")]])
            execute(db, dialect, q_insert1)

            q_insert2 = insert_into(:orders, [:user_id, :total, :status]) |>
                        insert_values([[literal(1), literal(200.0), literal("pending")]])
            execute(db, dialect, q_insert2)

            q_insert3 = insert_into(:orders, [:user_id, :total, :status]) |>
                        insert_values([[literal(3), literal(300.0), literal("completed")]])
            execute(db, dialect, q_insert3)

            # CTE1: active users
            cte1_query = from(:users) |> where(col(:users, :is_active) == literal(1))
            c1 = cte(:active_users, cte1_query)

            # CTE2: completed orders
            cte2_query = from(:orders) |>
                         where(col(:orders, :status) == literal("completed"))
            c2 = cte(:completed_orders, cte2_query)

            # Main query: JOIN both CTEs
            main_query = from(:active_users) |>
                         inner_join(:completed_orders,
                                   col(:active_users, :id) ==
                                   col(:completed_orders, :user_id)) |>
                         select(NamedTuple, col(:active_users, :name),
                                col(:completed_orders, :total)) |>
                         order_by(col(:active_users, :name))

            q = with([c1, c2], main_query)

            # Execute
            results = fetch_all(db, dialect, registry, q)

            @test length(results) == 2
            @test results[1][:name] == "Alice"
            @test results[1][:total] == 150.0
            @test results[2][:name] == "Charlie"
            @test results[2][:total] == 300.0
        end

        @testset "CTE with aggregation" begin
            # CTE: aggregate orders by user
            cte_query = from(:orders) |>
                        group_by(col(:orders, :user_id)) |>
                        select(NamedTuple, col(:orders, :user_id),
                               func(:SUM, [col(:orders, :total)]),
                               func(:COUNT, [col(:orders, :id)]))

            c = cte(:user_stats, cte_query,
                    columns = [:user_id, :total_spent, :order_count])

            # Main query: filter and order
            main_query = from(:user_stats) |>
                         where(col(:user_stats, :order_count) > literal(1)) |>
                         select(NamedTuple, col(:user_stats, :user_id),
                                col(:user_stats, :total_spent),
                                col(:user_stats, :order_count))

            q = with(c, main_query)

            # Execute
            results = fetch_all(db, dialect, registry, q)

            @test length(results) == 1
            @test results[1][:user_id] == 1
            @test results[1][:total_spent] == 350.0  # 150 + 200
            @test results[1][:order_count] == 2
        end

        @testset "CTE with DISTINCT" begin
            # CTE: unique emails
            cte_query = from(:users) |>
                        select(NamedTuple, col(:users, :email)) |>
                        distinct

            c = cte(:unique_emails, cte_query)

            # Main query: count
            main_query = from(:unique_emails) |>
                         select(NamedTuple, func(:COUNT, [col(:unique_emails, :email)]))

            q = with(c, main_query)

            # Execute
            result = fetch_one(db, dialect, registry, q)

            @test result[Symbol("COUNT(`unique_emails`.`email`)")] == 3
        end

        @testset "Nested CTE references" begin
            # CTE1: active users
            cte1_query = from(:users) |> where(col(:users, :is_active) == literal(1))
            c1 = cte(:active_users, cte1_query)

            # CTE2: orders from active users
            cte2_query = from(:orders) |>
                         inner_join(:active_users,
                                   col(:orders, :user_id) == col(:active_users, :id)) |>
                         select(NamedTuple, col(:orders, :id), col(:orders, :user_id),
                                col(:orders, :total), col(:active_users, :name))

            c2 = cte(:active_orders, cte2_query)

            # Main query: select from CTE2
            main_query = from(:active_orders) |>
                         select(NamedTuple, col(:active_orders, :name),
                                col(:active_orders, :total)) |>
                         order_by(col(:active_orders, :total))

            q = with([c1, c2], main_query)

            # Execute
            results = fetch_all(db, dialect, registry, q)

            @test length(results) == 3
            @test results[1][:total] == 150.0
            @test results[2][:total] == 200.0
            @test results[3][:total] == 300.0
        end

        @testset "CTE with column aliases" begin
            # CTE with explicit column aliases
            cte_query = from(:users) |>
                        select(NamedTuple, col(:users, :id), col(:users, :name))

            c = cte(:user_summary, cte_query, columns = [:user_id, :user_name])

            # Main query: use aliased columns
            main_query = from(:user_summary) |>
                         select(NamedTuple, col(:user_summary, :user_id),
                                col(:user_summary, :user_name)) |>
                         order_by(col(:user_summary, :user_name))

            q = with(c, main_query)

            # Execute
            results = fetch_all(db, dialect, registry, q)

            @test length(results) == 3
            @test results[1][:user_name] == "Alice"
            @test results[2][:user_name] == "Bob"
            @test results[3][:user_name] == "Charlie"
        end

        @testset "CTE observability - sql() function" begin
            cte_query = from(:users) |> where(col(:users, :is_active) == literal(1))
            c = cte(:active_users, cte_query)
            main_query = from(:active_users) |>
                         select(NamedTuple, col(:active_users, :name))
            q = with(c, main_query)

            sql_str = sql(dialect, q)

            @test occursin("WITH `active_users` AS", sql_str)
            @test occursin("SELECT * FROM `users`", sql_str)
            @test occursin("WHERE (`users`.`is_active` = 1)", sql_str)
            @test occursin("SELECT `active_users`.`name` FROM `active_users`", sql_str)
        end
    end

    # Cleanup
    close(db)
end
