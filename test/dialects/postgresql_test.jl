using Test
using SQLSketch.Core: Dialect, Capability, CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW,
                      CAP_LATERAL, CAP_BULK_COPY, CAP_SAVEPOINT, CAP_ADVISORY_LOCK
using SQLSketch.Core: Query, From, Where, Select, Join, OrderBy, Limit, Offset, Distinct,
                      GroupBy, Having, CTE, With, Returning
using SQLSketch.Core: InsertInto, InsertValues, Update, UpdateSet, UpdateWhere,
                      DeleteFrom, DeleteWhere
using SQLSketch.Core: from, where, select, inner_join, left_join, right_join, full_join,
                      order_by, limit, offset, distinct, group_by, having, cte, with, returning
using SQLSketch.Core: insert_into, insert_values, update, set_values, delete_from
using SQLSketch.Core: SQLExpr, col, literal, param, func, is_null, is_not_null
using SQLSketch.Extras: p_
using SQLSketch.Core: like, not_like, ilike, not_ilike, between, not_between
using SQLSketch.Core: in_list, not_in_list
using SQLSketch.Core: compile, compile_expr, quote_identifier, placeholder, supports
using SQLSketch.Core: union_all, union_distinct, intersect_query, except_query
using SQLSketch.Core: on_conflict_do_nothing, on_conflict_do_update
using SQLSketch: PostgreSQLDialect

@testset "PostgreSQL Dialect - Helpers" begin
    dialect = PostgreSQLDialect()

    @testset "quote_identifier" begin
        @test quote_identifier(dialect, :users) == "\"users\""
        @test quote_identifier(dialect, :email) == "\"email\""
        @test quote_identifier(dialect, :user_id) == "\"user_id\""

        # Test escaping of double quotes
        @test quote_identifier(dialect, Symbol("table\"name")) == "\"table\"\"name\""
    end

    @testset "placeholder" begin
        @test placeholder(dialect, 1) == "\$1"
        @test placeholder(dialect, 2) == "\$2"
        @test placeholder(dialect, 100) == "\$100"
    end

    @testset "supports - capabilities" begin
        @test supports(dialect, CAP_CTE) == true
        @test supports(dialect, CAP_RETURNING) == true
        @test supports(dialect, CAP_UPSERT) == true
        @test supports(dialect, CAP_WINDOW) == true
        @test supports(dialect, CAP_LATERAL) == true  # PostgreSQL supports LATERAL
        @test supports(dialect, CAP_BULK_COPY) == true  # PostgreSQL COPY command
        @test supports(dialect, CAP_SAVEPOINT) == true
        @test supports(dialect, CAP_ADVISORY_LOCK) == true
    end
end

@testset "PostgreSQL Dialect - Expression Compilation" begin
    dialect = PostgreSQLDialect()

    @testset "ColRef" begin
        params = Symbol[]
        expr = col(:users, :email)
        sql = compile_expr(dialect, expr, params)

        @test sql == "\"users\".\"email\""
        @test isempty(params)
    end

    @testset "Literal - Numbers" begin
        params = Symbol[]

        sql1 = compile_expr(dialect, literal(42), params)
        @test sql1 == "42"

        sql2 = compile_expr(dialect, literal(3.14), params)
        @test sql2 == "3.14"

        @test isempty(params)
    end

    @testset "Literal - Strings" begin
        params = Symbol[]

        sql1 = compile_expr(dialect, literal("hello"), params)
        @test sql1 == "'hello'"

        # Test string escaping
        sql2 = compile_expr(dialect, literal("it's"), params)
        @test sql2 == "'it''s'"

        @test isempty(params)
    end

    @testset "Literal - Booleans" begin
        params = Symbol[]

        # PostgreSQL uses TRUE/FALSE
        sql1 = compile_expr(dialect, literal(true), params)
        @test sql1 == "TRUE"

        sql2 = compile_expr(dialect, literal(false), params)
        @test sql2 == "FALSE"

        @test isempty(params)
    end

    @testset "Literal - NULL" begin
        params = Symbol[]

        sql1 = compile_expr(dialect, literal(nothing), params)
        @test sql1 == "NULL"

        sql2 = compile_expr(dialect, literal(missing), params)
        @test sql2 == "NULL"

        @test isempty(params)
    end

    @testset "Param" begin
        params = Symbol[]

        sql1 = compile_expr(dialect, param(Int, :user_id), params)
        @test sql1 == "\$1"
        @test params == [:user_id]

        sql2 = compile_expr(dialect, param(String, :email), params)
        @test sql2 == "\$2"
        @test params == [:user_id, :email]
    end

    @testset "BinaryOp - Comparison" begin
        params = Symbol[]

        expr = col(:users, :id) == literal(42)
        sql = compile_expr(dialect, expr, params)
        @test sql == "(\"users\".\"id\" = 42)"
    end

    @testset "BinaryOp - ILIKE" begin
        params = Symbol[]

        # PostgreSQL has native ILIKE
        expr = ilike(col(:users, :email), literal("%@example.com"))
        sql = compile_expr(dialect, expr, params)
        @test sql == "(\"users\".\"email\" ILIKE '%@example.com')"
    end

    @testset "UnaryOp - NULL checks" begin
        params = Symbol[]

        sql1 = compile_expr(dialect, is_null(col(:users, :deleted_at)), params)
        @test sql1 == "(\"users\".\"deleted_at\" IS NULL)"

        sql2 = compile_expr(dialect, is_not_null(col(:users, :email)), params)
        @test sql2 == "(\"users\".\"email\" IS NOT NULL)"
    end

    @testset "FuncCall" begin
        params = Symbol[]

        sql1 = compile_expr(dialect, func(:COUNT, [col(:users, :id)]), params)
        @test sql1 == "COUNT(\"users\".\"id\")"

        sql2 = compile_expr(dialect, func(:UPPER, [col(:users, :email)]), params)
        @test sql2 == "UPPER(\"users\".\"email\")"
    end

    @testset "BETWEEN" begin
        params = Symbol[]

        expr = between(col(:orders, :total), literal(10), literal(100))
        sql = compile_expr(dialect, expr, params)
        @test sql == "(\"orders\".\"total\" BETWEEN 10 AND 100)"
    end

    @testset "IN" begin
        params = Symbol[]

        expr = in_list(col(:users, :status), [literal("active"), literal("pending")])
        sql = compile_expr(dialect, expr, params)
        @test sql == "(\"users\".\"status\" IN ('active', 'pending'))"
    end
end

@testset "PostgreSQL Dialect - Query Compilation" begin
    dialect = PostgreSQLDialect()

    @testset "FROM" begin
        q = from(:users)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM \"users\""
        @test isempty(params)
    end

    @testset "WHERE" begin
        q = from(:users) |>
            where(col(:users, :active) == literal(true))
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM \"users\" WHERE (\"users\".\"active\" = TRUE)"
        @test isempty(params)
    end

    @testset "WHERE with placeholder" begin
        q = from(:users) |>
            where(p_.active == literal(true))
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM \"users\" WHERE (\"users\".\"active\" = TRUE)"
        @test isempty(params)
    end

    @testset "SELECT" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :id), col(:users, :email))
        sql, params = compile(dialect, q)

        @test sql == "SELECT \"users\".\"id\", \"users\".\"email\" FROM \"users\""
        @test isempty(params)
    end

    @testset "JOIN" begin
        q = from(:users) |>
            left_join(:orders, col(:users, :id) == col(:orders, :user_id))
        sql, params = compile(dialect, q)

        @test sql ==
              "SELECT * FROM \"users\" LEFT JOIN \"orders\" ON (\"users\".\"id\" = \"orders\".\"user_id\")"
        @test isempty(params)
    end

    @testset "ORDER BY" begin
        q = from(:users) |>
            order_by(col(:users, :created_at); desc = true)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM \"users\" ORDER BY \"users\".\"created_at\" DESC"
        @test isempty(params)
    end

    @testset "LIMIT and OFFSET" begin
        q = from(:users) |>
            limit(10) |>
            offset(20)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM \"users\" LIMIT 10 OFFSET 20"
        @test isempty(params)
    end

    @testset "DISTINCT" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :email)) |>
            distinct
        sql, params = compile(dialect, q)

        @test sql == "SELECT DISTINCT \"users\".\"email\" FROM \"users\""
        @test isempty(params)
    end

    @testset "GROUP BY" begin
        q = from(:orders) |>
            select(NamedTuple, col(:orders, :user_id), func(:COUNT, [col(:orders, :id)])) |>
            group_by(col(:orders, :user_id))
        sql, params = compile(dialect, q)

        @test sql ==
              "SELECT \"orders\".\"user_id\", COUNT(\"orders\".\"id\") FROM \"orders\" GROUP BY \"orders\".\"user_id\""
        @test isempty(params)
    end

    @testset "HAVING" begin
        q = from(:orders) |>
            select(NamedTuple, col(:orders, :user_id), func(:COUNT, [col(:orders, :id)])) |>
            group_by(col(:orders, :user_id)) |>
            having(func(:COUNT, [col(:orders, :id)]) > literal(5))
        sql, params = compile(dialect, q)

        @test sql ==
              "SELECT \"orders\".\"user_id\", COUNT(\"orders\".\"id\") FROM \"orders\" GROUP BY \"orders\".\"user_id\" HAVING (COUNT(\"orders\".\"id\") > 5)"
        @test isempty(params)
    end
end

@testset "PostgreSQL Dialect - DML Compilation" begin
    dialect = PostgreSQLDialect()

    @testset "INSERT INTO" begin
        q = insert_into(:users, [:email, :name]) |>
            insert_values([[literal("test@example.com"), literal("Test User")]])
        sql, params = compile(dialect, q)

        @test sql ==
              "INSERT INTO \"users\" (\"email\", \"name\") VALUES ('test@example.com', 'Test User')"
        @test isempty(params)
    end

    @testset "INSERT with parameters" begin
        q = insert_into(:users, [:email, :name]) |>
            insert_values([[param(String, :email), param(String, :name)]])
        sql, params = compile(dialect, q)

        @test sql == "INSERT INTO \"users\" (\"email\", \"name\") VALUES (\$1, \$2)"
        @test params == [:email, :name]
    end

    @testset "UPDATE" begin
        q = update(:users) |>
            set_values(:email => param(String, :email)) |>
            where(col(:users, :id) == param(Int, :id))
        sql, params = compile(dialect, q)

        @test sql == "UPDATE \"users\" SET \"email\" = \$1 WHERE (\"users\".\"id\" = \$2)"
        @test params == [:email, :id]
    end

    @testset "DELETE" begin
        q = delete_from(:users) |>
            where(col(:users, :id) == param(Int, :id))
        sql, params = compile(dialect, q)

        @test sql == "DELETE FROM \"users\" WHERE (\"users\".\"id\" = \$1)"
        @test params == [:id]
    end

    @testset "RETURNING" begin
        q = insert_into(:users, [:email]) |>
            insert_values([[literal("test@example.com")]]) |>
            returning(NamedTuple, p_.id, p_.email)
        sql, params = compile(dialect, q)

        @test sql ==
              "INSERT INTO \"users\" (\"email\") VALUES ('test@example.com') RETURNING \"users\".\"id\", \"users\".\"email\""
        @test isempty(params)
    end
end

@testset "PostgreSQL Dialect - ON CONFLICT (UPSERT)" begin
    dialect = PostgreSQLDialect()

    @testset "ON CONFLICT DO NOTHING" begin
        q = insert_into(:users, [:email, :name]) |>
            insert_values([[literal("test@example.com"), literal("Test")]]) |>
            on_conflict_do_nothing()
        sql, params = compile(dialect, q)

        @test sql ==
              "INSERT INTO \"users\" (\"email\", \"name\") VALUES ('test@example.com', 'Test') ON CONFLICT DO NOTHING"
        @test isempty(params)
    end

    @testset "ON CONFLICT DO UPDATE" begin
        q = insert_into(:users, [:email, :name]) |>
            insert_values([[literal("test@example.com"), literal("Test")]]) |>
            on_conflict_do_update([:email], :name => col(:excluded, :name))
        sql, params = compile(dialect, q)

        @test sql ==
              "INSERT INTO \"users\" (\"email\", \"name\") VALUES ('test@example.com', 'Test') ON CONFLICT (\"email\") DO UPDATE SET \"name\" = \"excluded\".\"name\""
        @test isempty(params)
    end
end

@testset "PostgreSQL Dialect - CTE" begin
    dialect = PostgreSQLDialect()

    @testset "WITH clause" begin
        active_users = from(:users) |>
                       where(col(:users, :active) == literal(true))
        cte1 = cte(:active_users, active_users)

        main_query = from(:active_users) |>
                     select(NamedTuple, col(:active_users, :email))

        q = with([cte1], main_query)
        sql, params = compile(dialect, q)

        @test sql ==
              "WITH \"active_users\" AS (SELECT * FROM \"users\" WHERE (\"users\".\"active\" = TRUE)) SELECT \"active_users\".\"email\" FROM \"active_users\""
        @test isempty(params)
    end
end

@testset "PostgreSQL Dialect - Set Operations" begin
    dialect = PostgreSQLDialect()

    @testset "UNION" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))
        q = union_distinct(q1, q2)
        sql, params = compile(dialect, q)

        @test sql ==
              "(SELECT \"users\".\"email\" FROM \"users\") UNION (SELECT \"admins\".\"email\" FROM \"admins\")"
        @test isempty(params)
    end

    @testset "INTERSECT" begin
        q1 = from(:customers) |> select(NamedTuple, col(:customers, :id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :customer_id))
        q = intersect_query(q1, q2)
        sql, params = compile(dialect, q)

        @test sql ==
              "(SELECT \"customers\".\"id\" FROM \"customers\") INTERSECT (SELECT \"orders\".\"customer_id\" FROM \"orders\")"
        @test isempty(params)
    end

    @testset "EXCEPT" begin
        q1 = from(:all_users) |> select(NamedTuple, col(:all_users, :id))
        q2 = from(:banned_users) |> select(NamedTuple, col(:banned_users, :user_id))
        q = except_query(q1, q2)
        sql, params = compile(dialect, q)

        @test sql ==
              "(SELECT \"all_users\".\"id\" FROM \"all_users\") EXCEPT (SELECT \"banned_users\".\"user_id\" FROM \"banned_users\")"
        @test isempty(params)
    end
end

@testset "PostgreSQL Dialect - DDL" begin
    using SQLSketch.Core: create_table, add_column, drop_table, create_index, drop_index
    using SQLSketch.Core: alter_table, add_alter_column, drop_alter_column

    dialect = PostgreSQLDialect()

    @testset "CREATE TABLE" begin
        ddl = create_table(:users) |>
              add_column(:id, :integer; primary_key = true) |>
              add_column(:email, :text; nullable = false, unique = true) |>
              add_column(:created_at, :timestamp)

        sql, params = compile(dialect, ddl)

        @test occursin("CREATE TABLE \"users\"", sql)
        @test occursin("\"id\" INTEGER PRIMARY KEY", sql)
        @test occursin("\"email\" TEXT NOT NULL UNIQUE", sql)
        @test occursin("\"created_at\" TIMESTAMP", sql)
        @test isempty(params)
    end

    @testset "CREATE TABLE with IF NOT EXISTS" begin
        ddl = create_table(:users; if_not_exists = true) |>
              add_column(:id, :integer; primary_key = true)

        sql, params = compile(dialect, ddl)

        @test occursin("CREATE TABLE IF NOT EXISTS \"users\"", sql)
        @test isempty(params)
    end

    @testset "DROP TABLE" begin
        ddl = drop_table(:users; if_exists = true)
        sql, params = compile(dialect, ddl)

        @test sql == "DROP TABLE IF EXISTS \"users\""
        @test isempty(params)
    end

    @testset "DROP TABLE CASCADE" begin
        ddl = drop_table(:users; cascade = true)
        sql, params = compile(dialect, ddl)

        @test sql == "DROP TABLE \"users\" CASCADE"
        @test isempty(params)
    end

    @testset "CREATE INDEX" begin
        ddl = create_index(:idx_users_email, :users, [:email]; unique = true)
        sql, params = compile(dialect, ddl)

        @test sql == "CREATE UNIQUE INDEX \"idx_users_email\" ON \"users\" (\"email\")"
        @test isempty(params)
    end

    @testset "DROP INDEX" begin
        ddl = drop_index(:idx_users_email; if_exists = true)
        sql, params = compile(dialect, ddl)

        @test sql == "DROP INDEX IF EXISTS \"idx_users_email\""
        @test isempty(params)
    end

    @testset "ALTER TABLE - Multiple operations" begin
        using SQLSketch.Core: AddColumn, ColumnDef, NotNullConstraint

        ddl = alter_table(:users) |>
              add_alter_column(:age, :integer) |>
              drop_alter_column(:deprecated_field)

        sql, params = compile(dialect, ddl)

        # PostgreSQL supports multiple operations in one ALTER TABLE
        @test occursin("ALTER TABLE \"users\"", sql)
        @test occursin("ADD COLUMN \"age\" INTEGER", sql)
        @test occursin("DROP COLUMN \"deprecated_field\"", sql)
        @test isempty(params)
    end

    @testset "Extended Column Constraints - PostgreSQL" begin
        using SQLSketch.Core: col, literal

        # Column-level CHECK constraint
        ddl = create_table(:users) |>
              add_column(:age, :integer; check = col(:users, :age) >= literal(18))
        sql, _ = compile(dialect, ddl)
        @test occursin("CHECK ((\"users\".\"age\" >= 18))", sql)

        # AUTO_INCREMENT -> SERIAL
        ddl2 = create_table(:users) |>
               add_column(:id, :integer; primary_key = true, auto_increment = true)
        sql2, _ = compile(dialect, ddl2)
        @test occursin("\"id\" SERIAL PRIMARY KEY", sql2)

        # AUTO_INCREMENT with BIGINT -> BIGSERIAL
        ddl3 = create_table(:users) |>
               add_column(:id, :bigint; primary_key = true, auto_increment = true)
        sql3, _ = compile(dialect, ddl3)
        @test occursin("\"id\" BIGSERIAL PRIMARY KEY", sql3)

        # GENERATED column (STORED)
        ddl4 = create_table(:users) |>
               add_column(:id, :integer) |>
               add_column(:double_id, :integer;
                          generated = col(:users, :id) * literal(2))
        sql4, _ = compile(dialect, ddl4)
        @test occursin("GENERATED ALWAYS AS ((\"users\".\"id\" * 2)) STORED", sql4)

        # GENERATED column (VIRTUAL - no STORED keyword in PostgreSQL)
        ddl5 = create_table(:users) |>
               add_column(:id, :integer) |>
               add_column(:double_id, :integer;
                          generated = col(:users, :id) * literal(2), stored = false)
        sql5, _ = compile(dialect, ddl5)
        @test occursin("GENERATED ALWAYS AS ((\"users\".\"id\" * 2))", sql5)
        @test !occursin("STORED", sql5)

        # COLLATION constraint
        ddl6 = create_table(:users) |>
               add_column(:email, :text; collation = :en_US)
        sql6, _ = compile(dialect, ddl6)
        @test occursin("TEXT COLLATE \"en_US\"", sql6)

        # IDENTITY constraint (BY DEFAULT)
        ddl7 = create_table(:users) |>
               add_column(:id, :integer; identity = true)
        sql7, _ = compile(dialect, ddl7)
        @test occursin("GENERATED BY DEFAULT AS IDENTITY", sql7)

        # IDENTITY constraint (ALWAYS)
        ddl8 = create_table(:users) |>
               add_column(:id, :integer; identity = true, identity_always = true)
        sql8, _ = compile(dialect, ddl8)
        @test occursin("GENERATED ALWAYS AS IDENTITY", sql8)

        # IDENTITY with START and INCREMENT
        ddl9 = create_table(:users) |>
               add_column(:id, :integer; identity = true, identity_start = 100,
                          identity_increment = 2)
        sql9, _ = compile(dialect, ddl9)
        @test occursin("GENERATED BY DEFAULT AS IDENTITY (START WITH 100 INCREMENT BY 2)",
                       sql9)

        # Multiple constraints combined
        ddl10 = create_table(:users) |>
                add_column(:id, :integer; primary_key = true, auto_increment = true) |>
                add_column(:age, :integer; nullable = false,
                           check = col(:users, :age) >= literal(0))
        sql10, _ = compile(dialect, ddl10)
        @test occursin("\"id\" SERIAL PRIMARY KEY", sql10)
        @test occursin("\"age\" INTEGER NOT NULL CHECK", sql10)
    end

    @testset "CREATE INDEX - Expression Indexes (PostgreSQL)" begin
        # Single expression index
        ddl = create_index(:idx_users_lower_email, :users, Symbol[],
                           expr = [func(:lower, [col(:users, :email)])])
        sql, params = compile(dialect, ddl)
        @test sql ==
              "CREATE INDEX \"idx_users_lower_email\" ON \"users\" (lower(\"users\".\"email\"))"
        @test isempty(params)

        # Multiple expression index
        ddl2 = create_index(:idx_users_name, :users, Symbol[],
                            expr = [func(:lower, [col(:users, :first_name)]),
                                    func(:lower, [col(:users, :last_name)])])
        sql2, _ = compile(dialect, ddl2)
        @test occursin("lower(\"users\".\"first_name\"), lower(\"users\".\"last_name\")",
                       sql2)

        # Expression index with WHERE clause
        ddl3 = create_index(:idx_active_emails, :users, Symbol[],
                            expr = [func(:lower, [col(:users, :email)])],
                            where = col(:users, :active) == literal(true))
        sql3, _ = compile(dialect, ddl3)
        @test occursin("lower(\"users\".\"email\")", sql3)
        @test occursin("WHERE (\"users\".\"active\" = TRUE)", sql3)

        # Unique expression index
        ddl4 = create_index(:idx_users_lower_email_unique, :users, Symbol[],
                            expr = [func(:lower, [col(:users, :email)])],
                            unique = true)
        sql4, _ = compile(dialect, ddl4)
        @test occursin("CREATE UNIQUE INDEX", sql4)
        @test occursin("lower(\"users\".\"email\")", sql4)
    end

    @testset "CREATE INDEX - Index Methods (PostgreSQL)" begin
        # BTREE (default method, but can be explicit)
        ddl = create_index(:idx_users_email, :users, [:email], method = :btree)
        sql, _ = compile(dialect, ddl)
        @test occursin("USING BTREE", sql)
        @test sql ==
              "CREATE INDEX \"idx_users_email\" ON \"users\" USING BTREE (\"email\")"

        # HASH index
        ddl2 = create_index(:idx_users_id, :users, [:id], method = :hash)
        sql2, _ = compile(dialect, ddl2)
        @test occursin("USING HASH", sql2)

        # GIN index (for JSONB, arrays, full-text search)
        ddl3 = create_index(:idx_users_tags, :users, [:tags], method = :gin)
        sql3, _ = compile(dialect, ddl3)
        @test occursin("USING GIN", sql3)
        @test sql3 ==
              "CREATE INDEX \"idx_users_tags\" ON \"users\" USING GIN (\"tags\")"

        # GIST index (for geometric data, full-text search)
        ddl4 = create_index(:idx_locations_geom, :locations, [:geom], method = :gist)
        sql4, _ = compile(dialect, ddl4)
        @test occursin("USING GIST", sql4)

        # BRIN index (for large tables with natural ordering)
        ddl5 = create_index(:idx_events_created_at, :events, [:created_at], method = :brin)
        sql5, _ = compile(dialect, ddl5)
        @test occursin("USING BRIN", sql5)

        # SP-GIST index
        ddl6 = create_index(:idx_points, :points, [:location], method = :spgist)
        sql6, _ = compile(dialect, ddl6)
        @test occursin("USING SPGIST", sql6)
    end

    @testset "CREATE INDEX - Expression + Method (PostgreSQL)" begin
        # Expression index with BTREE
        ddl = create_index(:idx_lower_email_btree, :users, Symbol[],
                           expr = [func(:lower, [col(:users, :email)])],
                           method = :btree)
        sql, _ = compile(dialect, ddl)
        @test occursin("USING BTREE", sql)
        @test occursin("lower(\"users\".\"email\")", sql)

        # Expression index with GIN (useful for text search)
        ddl2 = create_index(:idx_search_name, :users, Symbol[],
                            expr = [func(:to_tsvector,
                                         [literal("english"),
                                          col(:users, :name)])],
                            method = :gin)
        sql2, _ = compile(dialect, ddl2)
        @test occursin("USING GIN", sql2)
        @test occursin("to_tsvector", sql2)

        # Unique expression index with method
        ddl3 = create_index(:idx_lower_email_unique, :users, Symbol[],
                            expr = [func(:lower, [col(:users, :email)])],
                            method = :btree,
                            unique = true)
        sql3, _ = compile(dialect, ddl3)
        @test occursin("CREATE UNIQUE INDEX", sql3)
        @test occursin("USING BTREE", sql3)
        @test occursin("lower(\"users\".\"email\")", sql3)
    end

    @testset "CREATE INDEX - Complete Examples (PostgreSQL)" begin
        # Partial expression index with method
        ddl = create_index(:idx_active_lower_emails, :users, Symbol[],
                           expr = [func(:lower, [col(:users, :email)])],
                           where = col(:users, :active) == literal(true),
                           method = :btree,
                           unique = true,
                           if_not_exists = true)
        sql, _ = compile(dialect, ddl)
        @test occursin("CREATE UNIQUE INDEX IF NOT EXISTS", sql)
        @test occursin("USING BTREE", sql)
        @test occursin("lower(\"users\".\"email\")", sql)
        @test occursin("WHERE (\"users\".\"active\" = TRUE)", sql)
    end

    @testset "ALTER COLUMN - SET/DROP DEFAULT (PostgreSQL)" begin
        # SET DEFAULT
        ddl = alter_table(:users) |>
              set_column_default(:status, literal("active"))
        sql, _ = compile(dialect, ddl)
        @test sql == "ALTER TABLE \"users\" ALTER COLUMN \"status\" SET DEFAULT 'active'"

        # DROP DEFAULT
        ddl2 = alter_table(:users) |>
               drop_column_default(:status)
        sql2, _ = compile(dialect, ddl2)
        @test sql2 == "ALTER TABLE \"users\" ALTER COLUMN \"status\" DROP DEFAULT"
    end

    @testset "ALTER COLUMN - SET/DROP NOT NULL (PostgreSQL)" begin
        # SET NOT NULL
        ddl = alter_table(:users) |>
              set_column_not_null(:email)
        sql, _ = compile(dialect, ddl)
        @test sql == "ALTER TABLE \"users\" ALTER COLUMN \"email\" SET NOT NULL"

        # DROP NOT NULL
        ddl2 = alter_table(:users) |>
               drop_column_not_null(:phone)
        sql2, _ = compile(dialect, ddl2)
        @test sql2 == "ALTER TABLE \"users\" ALTER COLUMN \"phone\" DROP NOT NULL"
    end

    @testset "ALTER COLUMN - SET TYPE (PostgreSQL)" begin
        # Without USING clause
        ddl = alter_table(:users) |>
              set_column_type(:age, :bigint)
        sql, _ = compile(dialect, ddl)
        @test sql == "ALTER TABLE \"users\" ALTER COLUMN \"age\" TYPE BIGINT"

        # With USING clause
        ddl2 = alter_table(:products) |>
               set_column_type(:price, :integer;
                               using_expr = cast(col(:products, :price), :integer))
        sql2, _ = compile(dialect, ddl2)
        @test occursin("ALTER COLUMN \"price\" TYPE INTEGER", sql2)
        @test occursin("USING CAST(\"products\".\"price\" AS INTEGER)", sql2)
    end

    @testset "ALTER COLUMN - SET STATISTICS (PostgreSQL)" begin
        ddl = alter_table(:users) |>
              set_column_statistics(:email, 1000)
        sql, _ = compile(dialect, ddl)
        @test sql == "ALTER TABLE \"users\" ALTER COLUMN \"email\" SET STATISTICS 1000"
    end

    @testset "ALTER COLUMN - SET STORAGE (PostgreSQL)" begin
        ddl = alter_table(:users) |>
              set_column_storage(:bio, :external)
        sql, _ = compile(dialect, ddl)
        @test sql == "ALTER TABLE \"users\" ALTER COLUMN \"bio\" SET STORAGE EXTERNAL"

        # Test other storage modes
        ddl2 = alter_table(:users) |>
               set_column_storage(:data, :plain)
        sql2, _ = compile(dialect, ddl2)
        @test occursin("SET STORAGE PLAIN", sql2)
    end

    @testset "ALTER COLUMN - Multiple operations (PostgreSQL)" begin
        # PostgreSQL supports multiple ALTER COLUMN operations in one statement
        ddl = alter_table(:users) |>
              set_column_default(:status, literal("active")) |>
              set_column_not_null(:email) |>
              set_column_type(:age, :bigint)

        sql, _ = compile(dialect, ddl)
        @test occursin("ALTER TABLE \"users\"", sql)
        @test occursin("ALTER COLUMN \"status\" SET DEFAULT", sql)
        @test occursin("ALTER COLUMN \"email\" SET NOT NULL", sql)
        @test occursin("ALTER COLUMN \"age\" TYPE BIGINT", sql)
        # Check that operations are comma-separated
        @test occursin(",", sql)
    end
end
