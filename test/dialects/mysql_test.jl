using Test
using SQLSketch.Core: Dialect, Capability, CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW,
                      CAP_LATERAL, CAP_BULK_COPY, CAP_SAVEPOINT, CAP_ADVISORY_LOCK
using SQLSketch.Core: Query, From, Where, Select, Join, OrderBy, Limit, Offset, Distinct,
                      GroupBy, Having, CTE, With, Returning
using SQLSketch.Core: InsertInto, InsertValues, Update, UpdateSet, UpdateWhere,
                      DeleteFrom, DeleteWhere
using SQLSketch.Core: from, where, select, join, order_by, limit, offset, distinct,
                      group_by, having, cte, with, returning
using SQLSketch.Core: insert_into, values, update, set, delete_from
using SQLSketch.Core: SQLExpr, col, literal, param, func, is_null, is_not_null
using SQLSketch.Extras: p_
using SQLSketch.Core: like, not_like, ilike, not_ilike, between, not_between
using SQLSketch.Core: in_list, not_in_list
using SQLSketch.Core: compile, compile_expr, quote_identifier, placeholder, supports
using SQLSketch.Core: union, intersect, except
using SQLSketch.Core: on_conflict_do_nothing, on_conflict_do_update
using SQLSketch: MySQLDialect

@testset "MySQL Dialect - Helpers" begin
    dialect = MySQLDialect()

    @testset "quote_identifier" begin
        @test quote_identifier(dialect, :users) == "`users`"
        @test quote_identifier(dialect, :email) == "`email`"
        @test quote_identifier(dialect, :user_id) == "`user_id`"

        # Test escaping of backticks
        @test quote_identifier(dialect, Symbol("table`name")) == "`table``name`"
    end

    @testset "placeholder" begin
        # MySQL uses ? for all placeholders
        @test placeholder(dialect, 1) == "?"
        @test placeholder(dialect, 2) == "?"
        @test placeholder(dialect, 100) == "?"
    end

    @testset "supports - capabilities" begin
        # MySQL 8.0 capabilities
        @test supports(dialect, CAP_CTE) == true
        @test supports(dialect, CAP_RETURNING) == false  # MySQL doesn't support RETURNING
        @test supports(dialect, CAP_UPSERT) == true  # ON DUPLICATE KEY UPDATE
        @test supports(dialect, CAP_WINDOW) == true  # MySQL 8.0+
        @test supports(dialect, CAP_LATERAL) == false  # MySQL doesn't support LATERAL
        @test supports(dialect, CAP_BULK_COPY) == false  # LOAD DATA INFILE is different
        @test supports(dialect, CAP_SAVEPOINT) == true
        @test supports(dialect, CAP_ADVISORY_LOCK) == true  # GET_LOCK/RELEASE_LOCK
    end

    @testset "supports - version-specific" begin
        # MySQL 5.7 (no CTE, no window functions)
        dialect_57 = MySQLDialect(v"5.7.0")
        @test supports(dialect_57, CAP_CTE) == false
        @test supports(dialect_57, CAP_WINDOW) == false
        @test supports(dialect_57, CAP_UPSERT) == true  # Still has ON DUPLICATE KEY

        # MySQL 8.0 (has CTE and window functions)
        dialect_80 = MySQLDialect(v"8.0.0")
        @test supports(dialect_80, CAP_CTE) == true
        @test supports(dialect_80, CAP_WINDOW) == true
    end
end

@testset "MySQL Dialect - Expression Compilation" begin
    dialect = MySQLDialect()

    @testset "ColRef" begin
        params = Symbol[]
        expr = col(:users, :email)
        sql = compile_expr(dialect, expr, params)

        @test sql == "`users`.`email`"
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

        # MySQL uses 1/0 for booleans
        sql1 = compile_expr(dialect, literal(true), params)
        @test sql1 == "1"

        sql2 = compile_expr(dialect, literal(false), params)
        @test sql2 == "0"

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

    @testset "Literal - Dates" begin
        params = Symbol[]
        using Dates

        # Date literal
        date_val = Date(2024, 1, 15)
        sql1 = compile_expr(dialect, literal(date_val), params)
        @test sql1 == "'2024-01-15'"

        # DateTime literal
        datetime_val = DateTime(2024, 1, 15, 10, 30, 45)
        sql2 = compile_expr(dialect, literal(datetime_val), params)
        @test sql2 == "'2024-01-15 10:30:45'"

        @test isempty(params)
    end

    @testset "Literal - JSON (Dict)" begin
        params = Symbol[]

        dict_val = Dict("name" => "Alice", "age" => 30)
        sql = compile_expr(dialect, literal(dict_val), params)

        # MySQL JSON is just a string literal (no ::jsonb cast like PostgreSQL)
        @test contains(sql, "'")
        @test contains(sql, "name")
        @test contains(sql, "Alice")

        @test isempty(params)
    end

    @testset "Param" begin
        params = Symbol[]

        expr1 = param(String, :email)
        sql1 = compile_expr(dialect, expr1, params)
        @test sql1 == "?"
        @test params == [:email]

        expr2 = param(Int, :age)
        sql2 = compile_expr(dialect, expr2, params)
        @test sql2 == "?"
        @test params == [:email, :age]
    end

    @testset "BinaryOp - Comparison" begin
        params = Symbol[]

        # Equality
        expr = col(:users, :age) == literal(30)
        sql = compile_expr(dialect, expr, params)
        @test sql == "(`users`.`age` = 30)"

        # Inequality
        expr2 = col(:users, :age) != literal(30)
        sql2 = compile_expr(dialect, expr2, Symbol[])
        @test sql2 == "(`users`.`age` != 30)"
    end

    @testset "BinaryOp - Logical" begin
        params = Symbol[]

        # AND
        expr = (col(:users, :active) == literal(true)) & (col(:users, :age) > literal(18))
        sql = compile_expr(dialect, expr, params)
        @test contains(sql, "AND")
        @test contains(sql, "`users`.`active`")
        @test contains(sql, "`users`.`age`")
    end

    @testset "BinaryOp - ILIKE emulation" begin
        params = Symbol[]

        # MySQL doesn't have ILIKE, should emulate with UPPER
        expr = ilike(col(:users, :email), literal("%@example.com"))
        sql = compile_expr(dialect, expr, params)
        @test contains(sql, "UPPER")
        @test contains(sql, "LIKE")
        @test contains(sql, "`users`.`email`")
    end

    @testset "UnaryOp" begin
        params = Symbol[]

        # IS NULL
        expr1 = is_null(col(:users, :deleted_at))
        sql1 = compile_expr(dialect, expr1, params)
        @test sql1 == "(`users`.`deleted_at` IS NULL)"

        # IS NOT NULL
        expr2 = is_not_null(col(:users, :email))
        sql2 = compile_expr(dialect, expr2, params)
        @test sql2 == "(`users`.`email` IS NOT NULL)"
    end

    @testset "FuncCall" begin
        params = Symbol[]

        expr = func(:COUNT, [col(:users, :id)])
        sql = compile_expr(dialect, expr, params)
        @test sql == "COUNT(`users`.`id`)"
    end

    @testset "BETWEEN" begin
        params = Symbol[]

        expr = between(col(:users, :age), literal(18), literal(65))
        sql = compile_expr(dialect, expr, params)
        @test sql == "(`users`.`age` BETWEEN 18 AND 65)"
    end

    @testset "IN" begin
        params = Symbol[]

        expr = in_list(col(:users, :role), [literal("admin"), literal("moderator")])
        sql = compile_expr(dialect, expr, params)
        @test sql == "(`users`.`role` IN ('admin', 'moderator'))"
    end
end

@testset "MySQL Dialect - Query Compilation" begin
    dialect = MySQLDialect()

    @testset "FROM" begin
        q = from(:users)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users`"
        @test isempty(params)
    end

    @testset "WHERE" begin
        q = from(:users) |>
            where(col(:users, :active) == literal(true))
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` WHERE (`users`.`active` = 1)"
        @test isempty(params)
    end

    @testset "WHERE with placeholder syntax" begin
        q = from(:users) |>
            where(p_.active == literal(true))
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` WHERE (`users`.`active` = 1)"
        @test isempty(params)
    end

    @testset "SELECT" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :id), col(:users, :email))
        sql, params = compile(dialect, q)

        @test sql == "SELECT `users`.`id`, `users`.`email` FROM `users`"
        @test isempty(params)
    end

    @testset "JOIN - INNER" begin
        q = from(:users) |>
            join(:orders, col(:users, :id) == col(:orders, :user_id))
        sql, params = compile(dialect, q)

        @test sql ==
              "SELECT * FROM `users` INNER JOIN `orders` ON (`users`.`id` = `orders`.`user_id`)"
        @test isempty(params)
    end

    @testset "JOIN - LEFT" begin
        q = from(:users) |>
            join(:orders, col(:users, :id) == col(:orders, :user_id); kind = :left)
        sql, params = compile(dialect, q)

        @test sql ==
              "SELECT * FROM `users` LEFT JOIN `orders` ON (`users`.`id` = `orders`.`user_id`)"
        @test isempty(params)
    end

    @testset "JOIN - FULL (error)" begin
        q = from(:users) |>
            join(:orders, col(:users, :id) == col(:orders, :user_id); kind = :full)

        @test_throws ErrorException compile(dialect, q)
    end

    @testset "ORDER BY" begin
        q = from(:users) |>
            order_by(col(:users, :created_at); desc = true)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` ORDER BY `users`.`created_at` DESC"
        @test isempty(params)
    end

    @testset "LIMIT" begin
        q = from(:users) |>
            limit(10)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` LIMIT 10"
        @test isempty(params)
    end

    @testset "OFFSET" begin
        q = from(:users) |>
            offset(20)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` OFFSET 20"
        @test isempty(params)
    end

    @testset "DISTINCT" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :email)) |>
            distinct
        sql, params = compile(dialect, q)

        @test sql == "SELECT DISTINCT `users`.`email` FROM `users`"
        @test isempty(params)
    end

    @testset "GROUP BY" begin
        q = from(:orders) |>
            select(NamedTuple, col(:orders, :user_id), func(:COUNT, [col(:orders, :id)])) |>
            group_by(col(:orders, :user_id))
        sql, params = compile(dialect, q)

        @test contains(sql, "GROUP BY `orders`.`user_id`")
    end

    @testset "HAVING" begin
        q = from(:orders) |>
            group_by(col(:orders, :user_id)) |>
            having(func(:COUNT, [col(:orders, :id)]) > literal(5))
        sql, params = compile(dialect, q)

        @test contains(sql, "HAVING")
        @test contains(sql, "COUNT")
    end
end

@testset "MySQL Dialect - DML Compilation" begin
    dialect = MySQLDialect()

    @testset "INSERT INTO" begin
        q = insert_into(:users, [:email, :name]) |>
            values([[literal("alice@example.com"), literal("Alice")]])
        sql, params = compile(dialect, q)

        @test sql ==
              "INSERT INTO `users` (`email`, `name`) VALUES ('alice@example.com', 'Alice')"
        @test isempty(params)
    end

    @testset "INSERT with parameters" begin
        q = insert_into(:users, [:email, :name]) |>
            values([[param(String, :email), param(String, :name)]])
        sql, params = compile(dialect, q)

        @test sql == "INSERT INTO `users` (`email`, `name`) VALUES (?, ?)"
        @test params == [:email, :name]
    end

    @testset "UPDATE" begin
        q = update(:users) |>
            set(:email => param(String, :email)) |>
            where(col(:users, :id) == param(Int, :id))
        sql, params = compile(dialect, q)

        @test sql == "UPDATE `users` SET `email` = ? WHERE (`users`.`id` = ?)"
        @test params == [:email, :id]
    end

    @testset "DELETE" begin
        q = delete_from(:users) |>
            where(col(:users, :id) == param(Int, :id))
        sql, params = compile(dialect, q)

        @test sql == "DELETE FROM `users` WHERE (`users`.`id` = ?)"
        @test params == [:id]
    end
end

@testset "MySQL Dialect - UPSERT (ON DUPLICATE KEY UPDATE)" begin
    dialect = MySQLDialect()

    @testset "INSERT IGNORE (DO NOTHING emulation)" begin
        q = insert_into(:users, [:email]) |>
            values([[literal("alice@example.com")]]) |>
            on_conflict_do_nothing()
        sql, params = compile(dialect, q)

        @test sql == "INSERT IGNORE INTO `users` (`email`) VALUES ('alice@example.com')"
        @test isempty(params)
    end

    @testset "ON DUPLICATE KEY UPDATE" begin
        q = insert_into(:users, [:email, :name]) |>
            values([[literal("alice@example.com"), literal("Alice")]]) |>
            on_conflict_do_update([:email], :name => literal("Alice Updated"))
        sql, params = compile(dialect, q)

        @test contains(sql, "INSERT INTO `users`")
        @test contains(sql, "ON DUPLICATE KEY UPDATE")
        @test contains(sql, "`name` = 'Alice Updated'")
        @test isempty(params)
    end
end

@testset "MySQL Dialect - CTE (MySQL 8.0+)" begin
    dialect = MySQLDialect(v"8.0.0")

    @testset "Simple CTE" begin
        cte_query = from(:users) |>
                    where(col(:users, :active) == literal(true))

        main_query = from(:active_users) |>
                     select(NamedTuple, col(:active_users, :email))

        q = with([cte(:active_users, cte_query)], main_query)
        sql, params = compile(dialect, q)

        @test contains(sql, "WITH")
        @test contains(sql, "`active_users` AS")
        @test contains(sql, "SELECT `active_users`.`email`")
    end

    @testset "CTE version check (MySQL 5.7 error)" begin
        dialect_57 = MySQLDialect(v"5.7.0")

        cte_query = from(:users)
        main_query = from(:active_users)
        q = with([cte(:active_users, cte_query)], main_query)

        @test_throws ErrorException compile(dialect_57, q)
    end
end

@testset "MySQL Dialect - Set Operations" begin
    dialect = MySQLDialect()

    @testset "UNION" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))
        q = union(q1, q2)

        sql, params = compile(dialect, q)
        @test contains(sql, "UNION")
        @test contains(sql, "`users`")
        @test contains(sql, "`admins`")
    end

    @testset "UNION ALL" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))
        q = union(q1, q2; all = true)

        sql, params = compile(dialect, q)
        @test contains(sql, "UNION ALL")
    end

    @testset "INTERSECT (error)" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :user_id))
        q = intersect(q1, q2)

        @test_throws ErrorException compile(dialect, q)
    end

    @testset "EXCEPT (error)" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :id))
        q2 = from(:banned) |> select(NamedTuple, col(:banned, :user_id))
        q = except(q1, q2)

        @test_throws ErrorException compile(dialect, q)
    end
end

@testset "MySQL Dialect - Window Functions (MySQL 8.0+)" begin
    dialect = MySQLDialect(v"8.0.0")
    using SQLSketch.Core: row_number, rank, Over

    @testset "ROW_NUMBER() OVER ()" begin
        params = Symbol[]
        expr = row_number(Over(SQLExpr[], Tuple{SQLExpr, Bool}[], nothing))
        sql = compile_expr(dialect, expr, params)

        @test sql == "ROW_NUMBER() OVER ()"
        @test isempty(params)
    end

    @testset "RANK() OVER (PARTITION BY ... ORDER BY ...)" begin
        params = Symbol[]
        over_clause = Over([col(:orders, :user_id)],
                           [(col(:orders, :created_at), true)],
                           nothing)
        expr = rank(over_clause)
        sql = compile_expr(dialect, expr, params)

        @test contains(sql, "RANK()")
        @test contains(sql, "PARTITION BY `orders`.`user_id`")
        @test contains(sql, "ORDER BY `orders`.`created_at` DESC")
    end
end

# DDL Tests
using SQLSketch.Core: CreateTable, AlterTable, DropTable, CreateIndex, DropIndex
using SQLSketch.Core: create_table, add_column, add_primary_key, add_foreign_key
using SQLSketch.Core: add_unique, add_check
using SQLSketch.Core: alter_table, add_alter_column, drop_alter_column, rename_alter_column
using SQLSketch.Core: drop_table, create_index, drop_index

@testset "MySQL Dialect - DDL Compilation" begin
    dialect = MySQLDialect()

    @testset "CREATE TABLE - Basic" begin
        # Single column
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true, auto_increment = true)
        sql, params = compile(dialect, ddl)
        @test sql == "CREATE TABLE `users` (`id` INT PRIMARY KEY AUTO_INCREMENT)"
        @test isempty(params)

        # Multiple columns
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true, auto_increment = true) |>
              add_column(:email, :text, nullable = false)
        sql, params = compile(dialect, ddl)
        @test sql ==
              "CREATE TABLE `users` (`id` INT PRIMARY KEY AUTO_INCREMENT, `email` TEXT NOT NULL)"
        @test isempty(params)
    end

    @testset "CREATE TABLE - Column Types" begin
        test_types = [(:integer, "INT"),
                      (:bigint, "BIGINT"),
                      (:real, "DOUBLE"),
                      (:text, "TEXT"),
                      (:blob, "BLOB"),
                      (:boolean, "TINYINT(1)"),
                      (:timestamp, "DATETIME"),
                      (:date, "DATE"),
                      (:uuid, "CHAR(36)"),
                      (:json, "JSON")]

        for (col_type, expected_sql_type) in test_types
            ddl = create_table(:test) |> add_column(:col, col_type)
            sql, params = compile(dialect, ddl)
            @test occursin(expected_sql_type, sql)
        end
    end

    @testset "CREATE TABLE - Column Constraints" begin
        # NOT NULL
        ddl = create_table(:users) |> add_column(:email, :text, nullable = false)
        sql, _ = compile(dialect, ddl)
        @test occursin("NOT NULL", sql)

        # UNIQUE
        ddl = create_table(:users) |> add_column(:email, :text, unique = true)
        sql, _ = compile(dialect, ddl)
        @test occursin("UNIQUE", sql)

        # DEFAULT with literal
        ddl = create_table(:users) |> add_column(:active, :boolean, default = literal(true))
        sql, params = compile(dialect, ddl)
        @test occursin("DEFAULT", sql)
        @test isempty(params)

        # FOREIGN KEY (column-level)
        ddl = create_table(:posts) |>
              add_column(:user_id, :integer, references = (:users, :id))
        sql, _ = compile(dialect, ddl)
        @test occursin("REFERENCES `users`(`id`)", sql)

        # AUTO_INCREMENT
        ddl = create_table(:users) |>
              add_column(:id, :integer, auto_increment = true)
        sql, _ = compile(dialect, ddl)
        @test occursin("AUTO_INCREMENT", sql)

        # Multiple constraints on one column
        ddl = create_table(:users) |>
              add_column(:email, :text, nullable = false, unique = true)
        sql, _ = compile(dialect, ddl)
        @test occursin("NOT NULL", sql)
        @test occursin("UNIQUE", sql)
    end

    @testset "CREATE TABLE - Table Constraints" begin
        # PRIMARY KEY
        ddl = create_table(:users) |>
              add_column(:id, :integer) |>
              add_primary_key([:id])
        sql, _ = compile(dialect, ddl)
        @test occursin("PRIMARY KEY (`id`)", sql)

        # Composite PRIMARY KEY
        ddl = create_table(:user_roles) |>
              add_column(:user_id, :integer) |>
              add_column(:role_id, :integer) |>
              add_primary_key([:user_id, :role_id])
        sql, _ = compile(dialect, ddl)
        @test occursin("PRIMARY KEY (`user_id`, `role_id`)", sql)

        # FOREIGN KEY with CASCADE
        ddl = create_table(:posts) |>
              add_column(:user_id, :integer) |>
              add_foreign_key([:user_id], :users, [:id], on_delete = :cascade)
        sql, _ = compile(dialect, ddl)
        @test occursin("FOREIGN KEY (`user_id`) REFERENCES `users`(`id`)", sql)
        @test occursin("ON DELETE CASCADE", sql)

        # UNIQUE constraint
        ddl = create_table(:users) |>
              add_column(:email, :text) |>
              add_unique([:email])
        sql, _ = compile(dialect, ddl)
        @test occursin("UNIQUE (`email`)", sql)

        # CHECK constraint (MySQL 8.0.16+)
        ddl = create_table(:users) |>
              add_column(:age, :integer) |>
              add_check(col(:users, :age) >= literal(18))
        sql, _ = compile(dialect, ddl)
        @test occursin("CHECK (", sql)
        @test occursin("`users`.`age`", sql)
    end

    @testset "CREATE TABLE - Options" begin
        # IF NOT EXISTS
        ddl = create_table(:users, if_not_exists = true) |>
              add_column(:id, :integer)
        sql, _ = compile(dialect, ddl)
        @test occursin("IF NOT EXISTS", sql)
        @test occursin("CREATE TABLE IF NOT EXISTS `users`", sql)

        # TEMPORARY
        ddl = create_table(:temp_data, temporary = true) |>
              add_column(:id, :integer)
        sql, _ = compile(dialect, ddl)
        @test occursin("TEMPORARY", sql)
        @test occursin("CREATE TEMPORARY TABLE `temp_data`", sql)

        # Both options
        ddl = create_table(:temp_cache, if_not_exists = true, temporary = true) |>
              add_column(:key, :text)
        sql, _ = compile(dialect, ddl)
        @test occursin("TEMPORARY", sql)
        @test occursin("IF NOT EXISTS", sql)
    end

    @testset "ALTER TABLE - Add/Drop Column" begin
        # Add column
        ddl = alter_table(:users) |>
              add_alter_column(:age, :integer)
        sql, _ = compile(dialect, ddl)
        @test sql == "ALTER TABLE `users` ADD COLUMN `age` INT"

        # Drop column
        ddl = alter_table(:users) |>
              drop_alter_column(:age)
        sql, _ = compile(dialect, ddl)
        @test sql == "ALTER TABLE `users` DROP COLUMN `age`"
    end

    @testset "ALTER TABLE - Rename Column" begin
        ddl = alter_table(:users) |>
              rename_alter_column(:old_name, :new_name)
        sql, _ = compile(dialect, ddl)
        @test sql == "ALTER TABLE `users` RENAME COLUMN `old_name` TO `new_name`"
    end

    @testset "DROP TABLE" begin
        # Basic DROP TABLE
        ddl = drop_table(:users)
        sql, _ = compile(dialect, ddl)
        @test sql == "DROP TABLE `users`"

        # IF EXISTS
        ddl = drop_table(:users, if_exists = true)
        sql, _ = compile(dialect, ddl)
        @test sql == "DROP TABLE IF EXISTS `users`"
    end

    @testset "CREATE INDEX" begin
        # Basic index
        ddl = create_index(:idx_users_email, :users, [:email])
        sql, _ = compile(dialect, ddl)
        @test sql == "CREATE INDEX `idx_users_email` ON `users` (`email`)"

        # UNIQUE index
        ddl = create_index(:idx_users_email, :users, [:email]; unique = true)
        sql, _ = compile(dialect, ddl)
        @test sql == "CREATE UNIQUE INDEX `idx_users_email` ON `users` (`email`)"

        # Composite index
        ddl = create_index(:idx_users_name_email, :users, [:name, :email])
        sql, _ = compile(dialect, ddl)
        @test sql == "CREATE INDEX `idx_users_name_email` ON `users` (`name`, `email`)"

        # Index with method (BTREE, HASH)
        ddl = create_index(:idx_users_email, :users, [:email]; method = :btree)
        sql, _ = compile(dialect, ddl)
        @test occursin("USING BTREE", sql)
    end

    @testset "CREATE INDEX - Version-specific" begin
        # IF NOT EXISTS requires MySQL 5.7+
        dialect_57 = MySQLDialect(v"5.7.0")
        ddl = create_index(:idx_users_email, :users, [:email]; if_not_exists = true)
        sql, _ = compile(dialect_57, ddl)
        @test occursin("IF NOT EXISTS", sql)

        # MySQL 5.6 should warn
        dialect_56 = MySQLDialect(v"5.6.0")
        sql, _ = @test_logs (:warn, r"IF NOT EXISTS.*MySQL 5.7\+") compile(dialect_56, ddl)
        @test !occursin("IF NOT EXISTS", sql)
    end

    @testset "DROP INDEX" begin
        ddl = drop_index(:idx_users_email; if_exists = true)
        # MySQL 5.7+ supports IF EXISTS
        dialect_57 = MySQLDialect(v"5.7.0")
        sql, _ = @test_logs (:warn, r"MySQL DROP INDEX requires ON table_name") compile(dialect_57,
                                                                                        ddl)
        @test occursin("IF EXISTS", sql)
        @test occursin("DROP INDEX IF EXISTS `idx_users_email`", sql)
    end
end
