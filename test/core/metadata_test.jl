# Tests for Database Metadata API

using Test
using SQLSketch

@testset "Metadata API - SQLite" begin
    # Setup test database
    driver = SQLiteDriver()
    conn = connect(driver, ":memory:")

    # Create some test tables
    execute_sql(conn,
                """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY,
                    email TEXT NOT NULL,
                    name TEXT,
                    age INTEGER DEFAULT 18,
                    created_at TIMESTAMP
                )
                """,
                [])

    execute_sql(conn,
                """
                CREATE TABLE posts (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    content TEXT,
                    published INTEGER DEFAULT 0,
                    FOREIGN KEY (user_id) REFERENCES users(id)
                )
                """,
                [])

    execute_sql(conn, "CREATE TABLE comments (id INTEGER PRIMARY KEY)", [])

    @testset "list_tables" begin
        tables = list_tables(conn)
        @test tables isa Vector{String}
        @test length(tables) == 3
        @test "users" in tables
        @test "posts" in tables
        @test "comments" in tables
        # Should be sorted
        @test tables == ["comments", "posts", "users"]
    end

    @testset "describe_table - users" begin
        columns = describe_table(conn, :users)
        @test columns isa Vector{ColumnInfo}
        @test length(columns) == 5

        # Check id column
        id_col = columns[1]
        @test id_col.name == "id"
        @test id_col.type == "INTEGER"
        @test id_col.nullable == false
        @test id_col.primary_key == true

        # Check email column
        email_col = columns[2]
        @test email_col.name == "email"
        @test email_col.type == "TEXT"
        @test email_col.nullable == false
        @test email_col.primary_key == false

        # Check name column (nullable)
        name_col = columns[3]
        @test name_col.name == "name"
        @test name_col.type == "TEXT"
        @test name_col.nullable == true

        # Check age column (with default)
        age_col = columns[4]
        @test age_col.name == "age"
        @test age_col.type == "INTEGER"
        @test age_col.default == "18"
    end

    @testset "describe_table - posts" begin
        columns = describe_table(conn, :posts)
        @test length(columns) == 5

        # Check foreign key column
        user_id_col = columns[2]
        @test user_id_col.name == "user_id"
        @test user_id_col.type == "INTEGER"
        @test user_id_col.nullable == false
    end

    @testset "list_schemas" begin
        schemas = list_schemas(conn)
        @test schemas isa Vector{String}
        @test schemas == ["main"]  # SQLite default
    end

    @testset "ColumnInfo pretty printing" begin
        col = ColumnInfo("id", "INTEGER", false, nothing, true)
        output = sprint(show, col)
        @test contains(output, "id")
        @test contains(output, "INTEGER")
        @test contains(output, "[PK]")
        @test contains(output, "NOT NULL")
    end

    close(conn)
end

# PostgreSQL tests require a running PostgreSQL instance
# Skip unless PGTEST environment variable is set
if haskey(ENV, "PGTEST")
    @testset "Metadata API - PostgreSQL" begin
        driver = PostgreSQLDriver()
        conn = connect(driver, ENV["PGTEST"])

        @testset "list_tables" begin
            tables = list_tables(conn)
            @test tables isa Vector{String}
            # Cannot assert specific tables without knowing DB state
        end

        @testset "list_schemas" begin
            schemas = list_schemas(conn)
            @test schemas isa Vector{String}
            @test "public" in schemas
        end

        close(conn)
    end
else
    @testset "Metadata API - PostgreSQL" begin
        @test_skip "PostgreSQL tests require PGTEST env var"
    end
end
