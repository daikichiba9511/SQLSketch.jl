"""
# Batch Operations Tests

Test suite for batch INSERT operations (Phase 13.4).

Tests both standard multi-row INSERT and PostgreSQL COPY optimizations.
"""

using Test
using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers
using Dates
using UUIDs

@testset "Batch Operations" begin
    @testset "insert_batch - SQLite" begin
        # Setup
        driver = SQLiteDriver()
        conn = connect(driver, ":memory:")
        dialect = SQLiteDialect()
        registry = CodecRegistry()

        # Create test table
        execute_sql(conn,
                    """
                    CREATE TABLE users (
                        id INTEGER PRIMARY KEY,
                        email TEXT NOT NULL,
                        active INTEGER NOT NULL
                    )
                    """,
                    [])

        @testset "Empty rows" begin
            result = insert_batch(conn, dialect, registry, :users, [:id, :email, :active],
                                  NamedTuple[])
            @test result.rowcount == 0
        end

        @testset "Single row" begin
            rows = [(id = 1, email = "alice@example.com", active = 1)]
            result = insert_batch(conn, dialect, registry, :users, [:id, :email, :active],
                                  rows)
            @test result.rowcount == 1

            # Verify data
            res = execute_sql(conn, "SELECT * FROM users WHERE id = 1", [])
            @test length(collect(res)) == 1
        end

        @testset "Small batch (10 rows)" begin
            rows = [(id = i + 10, email = "user$(i)@example.com", active = 1) for i in 1:10]
            result = insert_batch(conn, dialect, registry, :users, [:id, :email, :active],
                                  rows)
            @test result.rowcount == 10

            # Verify count
            res = execute_sql(conn, "SELECT COUNT(*) as cnt FROM users", [])
            count = first(res).cnt
            @test count == 11  # 1 + 10
        end

        @testset "Medium batch (1000 rows)" begin
            # Clear table
            execute_sql(conn, "DELETE FROM users", [])

            rows = [(id = i, email = "user$(i)@example.com", active = 1) for i in 1:1000]
            result = insert_batch(conn, dialect, registry, :users, [:id, :email, :active],
                                  rows; chunk_size = 500)
            @test result.rowcount == 1000

            # Verify count
            res = execute_sql(conn, "SELECT COUNT(*) as cnt FROM users", [])
            count = first(res).cnt
            @test count == 1000
        end

        @testset "Large batch (10K rows)" begin
            # Clear table
            execute_sql(conn, "DELETE FROM users", [])

            rows = [(id = i, email = "user$(i)@example.com", active = 1) for i in 1:10_000]
            result = insert_batch(conn, dialect, registry, :users,
                                  [:id, :email, :active],
                                  rows; chunk_size = 1000)
            @test result.rowcount == 10_000

            # Verify count
            res = execute_sql(conn, "SELECT COUNT(*) as cnt FROM users", [])
            count = first(res).cnt
            @test count == 10_000
        end

        @testset "Mismatched columns error" begin
            rows = [
                (id = 1, email = "alice@example.com", active = 1),
                (id = 2, email = "bob@example.com"),  # Missing 'active'
            ]
            @test_throws ErrorException insert_batch(conn, dialect, registry, :users,
                                                      [:id, :email, :active], rows)
        end

        @testset "Empty columns error" begin
            rows = [(id = 1, email = "alice@example.com", active = 1)]
            @test_throws ErrorException insert_batch(conn, dialect, registry, :users,
                                                      Symbol[], rows)
        end

        @testset "Missing values (NULL)" begin
            # Clear table
            execute_sql(conn, "DELETE FROM users", [])

            # Create table with nullable column
            execute_sql(conn,
                        """
                        CREATE TABLE posts (
                            id INTEGER PRIMARY KEY,
                            title TEXT NOT NULL,
                            body TEXT
                        )
                        """,
                        [])

            rows = [
                (id = 1, title = "Post 1", body = "Content 1"),
                (id = 2, title = "Post 2", body = missing),
                (id = 3, title = "Post 3", body = "Content 3"),
            ]

            result = insert_batch(conn, dialect, registry, :posts, [:id, :title, :body],
                                  rows)
            @test result.rowcount == 3

            # Verify NULL was inserted
            res = execute_sql(conn, "SELECT body FROM posts WHERE id = 2", [])
            @test first(res).body === missing
        end

        @testset "Special characters in strings" begin
            execute_sql(conn, "DELETE FROM users", [])

            rows = [
                (id = 1, email = "test'quote@example.com", active = 1),
                (id = 2, email = "test\"double@example.com", active = 1),
                (id = 3, email = "test,comma@example.com", active = 1),
            ]

            result = insert_batch(conn, dialect, registry, :users, [:id, :email, :active],
                                  rows)
            @test result.rowcount == 3

            # Verify special characters preserved
            res = execute_sql(conn, "SELECT email FROM users WHERE id = 1", [])
            email = first(res).email  # SQLite.Query iterator
            @test email == "test'quote@example.com"
        end

        # Cleanup
        close(conn)
    end

    @testset "insert_batch - PostgreSQL COPY" begin
        # Skip if PostgreSQL not available
        pg_conninfo = get(ENV, "SQLSKETCH_PG_CONN", nothing)
        if pg_conninfo === nothing
            @warn "Skipping PostgreSQL COPY tests (set SQLSKETCH_PG_CONN environment variable)"
            return
        end

        # Setup
        driver = PostgreSQLDriver()
        conn = connect(driver, pg_conninfo)
        dialect = PostgreSQLDialect()

        # Use PostgreSQL-specific codec registry
        using SQLSketch.Codecs.PostgreSQL: PostgreSQLCodecRegistry
        registry = PostgreSQLCodecRegistry()

        # Create test table
        execute_sql(conn, "DROP TABLE IF EXISTS batch_test_users", [])
        execute_sql(conn,
                    """
                    CREATE TABLE batch_test_users (
                        id INTEGER PRIMARY KEY,
                        email TEXT NOT NULL,
                        active BOOLEAN NOT NULL
                    )
                    """,
                    [])

        @testset "PostgreSQL - Small batch (10 rows)" begin
            rows = [(id = i, email = "user$(i)@example.com", active = true) for i in 1:10]
            result = insert_batch(conn, dialect, registry, :batch_test_users,
                                  [:id, :email, :active], rows)
            @test result.rowcount == 10

            # Verify count
            res = execute_sql(conn, "SELECT COUNT(*) FROM batch_test_users", [])
            count = res[1][1]
            @test count == 10
        end

        @testset "PostgreSQL - Medium batch (1000 rows)" begin
            execute_sql(conn, "DELETE FROM batch_test_users", [])

            rows = [(id = i, email = "user$(i)@example.com", active = true) for i in 1:1000]
            result = insert_batch(conn, dialect, registry, :batch_test_users,
                                  [:id, :email, :active], rows)
            @test result.rowcount == 1000

            # Verify count
            res = execute_sql(conn, "SELECT COUNT(*) FROM batch_test_users", [])
            count = res[1][1]
            @test count == 1000
        end

        @testset "PostgreSQL - Large batch (10K rows)" begin
            execute_sql(conn, "DELETE FROM batch_test_users", [])

            rows = [(id = i, email = "user$(i)@example.com", active = true) for i in 1:10_000]
            result = insert_batch(conn, dialect, registry, :batch_test_users,
                                  [:id, :email, :active], rows)
            @test result.rowcount == 10_000

            # Verify count
            res = execute_sql(conn, "SELECT COUNT(*) FROM batch_test_users", [])
            count = res[1][1]
            @test count == 10_000
        end

        @testset "PostgreSQL - Very large batch (100K rows)" begin
            execute_sql(conn, "DELETE FROM batch_test_users", [])

            rows = [(id = i, email = "user$(i)@example.com", active = true)
                    for i in 1:100_000]
            result = insert_batch(conn, dialect, registry, :batch_test_users,
                                  [:id, :email, :active], rows)
            @test result.rowcount == 100_000

            # Verify count
            res = execute_sql(conn, "SELECT COUNT(*) FROM batch_test_users", [])
            count = res[1][1]
            @test count == 100_000
        end

        @testset "PostgreSQL - NULL values" begin
            execute_sql(conn, "DROP TABLE IF EXISTS batch_test_posts", [])
            execute_sql(conn,
                        """
                        CREATE TABLE batch_test_posts (
                            id INTEGER PRIMARY KEY,
                            title TEXT NOT NULL,
                            body TEXT
                        )
                        """,
                        [])

            rows = [
                (id = 1, title = "Post 1", body = "Content 1"),
                (id = 2, title = "Post 2", body = missing),
                (id = 3, title = "Post 3", body = "Content 3"),
            ]

            result = insert_batch(conn, dialect, registry, :batch_test_posts,
                                  [:id, :title, :body], rows)
            @test result.rowcount == 3

            # Verify NULL
            res = execute_sql(conn, "SELECT body FROM batch_test_posts WHERE id = 2", [])
            @test res[1][1] === missing
        end

        @testset "PostgreSQL - Special characters" begin
            execute_sql(conn, "DELETE FROM batch_test_users", [])

            rows = [
                (id = 1, email = "test'quote@example.com", active = true),
                (id = 2, email = "test\"double@example.com", active = true),
                (id = 3, email = "test,comma@example.com", active = true),
                (id = 4, email = "test\nnewline@example.com", active = true),
            ]

            result = insert_batch(conn, dialect, registry, :batch_test_users,
                                  [:id, :email, :active], rows)
            @test result.rowcount == 4

            # Verify special characters preserved
            res = execute_sql(conn, "SELECT email FROM batch_test_users WHERE id = 1", [])
            @test res[1][1] == "test'quote@example.com"
        end

        @testset "PostgreSQL - Rich types (UUID, Date, etc.)" begin
            execute_sql(conn, "DROP TABLE IF EXISTS batch_test_events", [])
            execute_sql(conn,
                        """
                        CREATE TABLE batch_test_events (
                            id UUID PRIMARY KEY,
                            created_at TIMESTAMP NOT NULL,
                            event_date DATE NOT NULL
                        )
                        """,
                        [])

            rows = [
                (id = uuid4(), created_at = DateTime(2025, 1, 20, 10, 30, 0),
                 event_date = Date(2025, 1, 20)),
                (id = uuid4(), created_at = DateTime(2025, 1, 21, 11, 30, 0),
                 event_date = Date(2025, 1, 21)),
            ]

            result = insert_batch(conn, dialect, registry, :batch_test_events,
                                  [:id, :created_at, :event_date], rows)
            @test result.rowcount == 2

            # Verify data
            res = execute_sql(conn, "SELECT COUNT(*) FROM batch_test_events", [])
            @test res[1][1] == 2
        end

        # Cleanup
        execute_sql(conn, "DROP TABLE IF EXISTS batch_test_users", [])
        execute_sql(conn, "DROP TABLE IF EXISTS batch_test_posts", [])
        execute_sql(conn, "DROP TABLE IF EXISTS batch_test_events", [])
        close(conn)
    end

    @testset "CSV encoding helpers" begin
        @testset "_encode_rows_to_csv - Basic types" begin
            registry = CodecRegistry()
            columns = [:id, :name, :active]
            rows = [
                (id = 1, name = "Alice", active = true),
                (id = 2, name = "Bob", active = false),
            ]

            csv = SQLSketch.Core._encode_rows_to_csv(registry, columns, rows)

            # Should contain 2 rows
            lines = split(strip(csv), '\n')
            @test length(lines) == 2

            # Check first row
            @test occursin("1", lines[1])
            @test occursin("Alice", lines[1])
            @test occursin("true", lines[1])
        end

        @testset "_encode_rows_to_csv - Special characters" begin
            registry = CodecRegistry()
            columns = [:id, :email]
            rows = [
                (id = 1, email = "test,comma@example.com"),
                (id = 2, email = "test\"quote@example.com"),
            ]

            csv = SQLSketch.Core._encode_rows_to_csv(registry, columns, rows)

            # Quotes should be escaped
            @test occursin("\"test,comma@example.com\"", csv)
            @test occursin("\"\"", csv)  # Double quotes
        end

        @testset "_encode_rows_to_csv - NULL/missing" begin
            registry = CodecRegistry()
            columns = [:id, :body]
            rows = [
                (id = 1, body = "Content"),
                (id = 2, body = missing),
            ]

            csv = SQLSketch.Core._encode_rows_to_csv(registry, columns, rows)

            lines = split(strip(csv), '\n')
            @test length(lines) == 2

            # Missing should be empty (NULL in CSV)
            @test occursin("2,", lines[2])  # id=2, empty body
        end
    end

    @testset "Multi-row INSERT SQL generation" begin
        @testset "_build_multirow_insert - Basic" begin
            registry = CodecRegistry()
            dialect = SQLiteDialect()
            table_name = "users"
            column_list = "id, email"
            columns = [:id, :email]
            rows = [
                (id = 1, email = "alice@example.com"),
                (id = 2, email = "bob@example.com"),
            ]

            sql = SQLSketch.Core._build_multirow_insert(dialect, registry, table_name,
                                                         column_list, columns, rows)

            @test occursin("INSERT INTO users (id, email) VALUES", sql)
            @test occursin("(1, 'alice@example.com')", sql)
            @test occursin("(2, 'bob@example.com')", sql)
        end

        @testset "_build_multirow_insert - Special characters" begin
            registry = CodecRegistry()
            dialect = SQLiteDialect()
            table_name = "users"
            column_list = "id, email"
            columns = [:id, :email]
            rows = [(id = 1, email = "test'quote@example.com")]

            sql = SQLSketch.Core._build_multirow_insert(dialect, registry, table_name,
                                                         column_list, columns, rows)

            # Single quotes should be escaped
            @test occursin("test''quote", sql)
        end

        @testset "_build_multirow_insert - NULL" begin
            registry = CodecRegistry()
            dialect = SQLiteDialect()
            table_name = "posts"
            column_list = "id, body"
            columns = [:id, :body]
            rows = [
                (id = 1, body = "Content"),
                (id = 2, body = missing),
            ]

            sql = SQLSketch.Core._build_multirow_insert(dialect, registry, table_name,
                                                         column_list, columns, rows)

            @test occursin("(2, NULL)", sql)
        end
    end
end
