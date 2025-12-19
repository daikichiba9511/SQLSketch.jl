using Test
using SQLSketch.Core: Dialect, Capability, CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW,
                      CAP_LATERAL
using SQLSketch.Core: Query, From, Where, Select, Join, OrderBy, Limit, Offset, Distinct,
                      GroupBy, Having, CTE, With
using SQLSketch.Core: InsertInto, InsertValues, Update, UpdateSet, UpdateWhere,
                      DeleteFrom, DeleteWhere
using SQLSketch.Core: from, where, select, join, order_by, limit, offset, distinct,
                      group_by, having, cte, with
using SQLSketch.Core: insert_into, values, update, set, delete_from
using SQLSketch.Core: SQLExpr, col, literal, param, func, is_null, is_not_null
using SQLSketch.Core: like, not_like, ilike, not_ilike, between, not_between
using SQLSketch.Core: in_list, not_in_list
using SQLSketch.Core: compile, compile_expr, quote_identifier, placeholder, supports
using SQLSketch: SQLiteDialect

@testset "SQLite Dialect - Helpers" begin
    dialect = SQLiteDialect()

    @testset "quote_identifier" begin
        @test quote_identifier(dialect, :users) == "`users`"
        @test quote_identifier(dialect, :email) == "`email`"
        @test quote_identifier(dialect, :user_id) == "`user_id`"

        # Test escaping of backticks
        @test quote_identifier(dialect, Symbol("table`name")) == "`table``name`"
    end

    @testset "placeholder" begin
        @test placeholder(dialect, 1) == "?"
        @test placeholder(dialect, 2) == "?"
        @test placeholder(dialect, 100) == "?"
    end

    @testset "supports - capabilities" begin
        @test supports(dialect, CAP_CTE) == true
        @test supports(dialect, CAP_RETURNING) == true  # SQLite 3.35+
        @test supports(dialect, CAP_UPSERT) == true
        @test supports(dialect, CAP_WINDOW) == true
        @test supports(dialect, CAP_LATERAL) == false
    end

    @testset "supports - version-dependent" begin
        old_dialect = SQLiteDialect(v"3.34.0")
        @test supports(old_dialect, CAP_RETURNING) == false

        new_dialect = SQLiteDialect(v"3.35.0")
        @test supports(new_dialect, CAP_RETURNING) == true
    end
end

@testset "SQLite Dialect - Expression Compilation" begin
    dialect = SQLiteDialect()

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

    @testset "Param" begin
        params = Symbol[]
        expr = param(Int, :user_id)
        sql = compile_expr(dialect, expr, params)

        @test sql == "?"
        @test params == [:user_id]
    end

    @testset "Param - Multiple" begin
        params = Symbol[]
        expr1 = param(Int, :id)
        expr2 = param(String, :email)

        sql1 = compile_expr(dialect, expr1, params)
        sql2 = compile_expr(dialect, expr2, params)

        @test sql1 == "?"
        @test sql2 == "?"
        @test params == [:id, :email]
    end

    @testset "BinaryOp - Comparison" begin
        params = Symbol[]

        expr = col(:users, :age) > 18
        sql = compile_expr(dialect, expr, params)
        @test sql == "(`users`.`age` > 18)"

        expr2 = col(:users, :id) == param(Int, :user_id)
        sql2 = compile_expr(dialect, expr2, params)
        @test sql2 == "(`users`.`id` = ?)"
        @test params == [:user_id]
    end

    @testset "BinaryOp - Logical" begin
        params = Symbol[]

        expr = (col(:users, :active) == true) & (col(:users, :verified) == true)
        sql = compile_expr(dialect, expr, params)
        @test sql == "((`users`.`active` = 1) AND (`users`.`verified` = 1))"
    end

    @testset "BinaryOp - Arithmetic" begin
        params = Symbol[]

        expr = col(:products, :price) * 1.1
        sql = compile_expr(dialect, expr, params)
        @test sql == "(`products`.`price` * 1.1)"
    end

    @testset "UnaryOp - NOT" begin
        params = Symbol[]

        expr = !col(:users, :active)
        sql = compile_expr(dialect, expr, params)
        @test sql == "(NOT `users`.`active`)"
    end

    @testset "UnaryOp - IS NULL" begin
        params = Symbol[]

        expr = is_null(col(:users, :deleted_at))
        sql = compile_expr(dialect, expr, params)
        @test sql == "(`users`.`deleted_at` IS NULL)"
    end

    @testset "UnaryOp - IS NOT NULL" begin
        params = Symbol[]

        expr = is_not_null(col(:users, :email))
        sql = compile_expr(dialect, expr, params)
        @test sql == "(`users`.`email` IS NOT NULL)"
    end

    @testset "FuncCall - No arguments" begin
        params = Symbol[]

        expr = func(:NOW, SQLExpr[])
        sql = compile_expr(dialect, expr, params)
        @test sql == "NOW()"
    end

    @testset "FuncCall - Single argument" begin
        params = Symbol[]

        expr = func(:COUNT, [col(:users, :id)])
        sql = compile_expr(dialect, expr, params)
        @test sql == "COUNT(`users`.`id`)"
    end

    @testset "FuncCall - Multiple arguments" begin
        params = Symbol[]

        expr = func(:COALESCE, [col(:users, :name), literal("Anonymous")])
        sql = compile_expr(dialect, expr, params)
        @test sql == "COALESCE(`users`.`name`, 'Anonymous')"
    end

    @testset "Complex Expression" begin
        params = Symbol[]

        # (age > 18 AND active = 1) OR admin = 1
        expr = ((col(:users, :age) > 18) & (col(:users, :active) == true)) |
               (col(:users, :admin) == true)
        sql = compile_expr(dialect, expr, params)
        @test sql ==
              "(((`users`.`age` > 18) AND (`users`.`active` = 1)) OR (`users`.`admin` = 1))"
    end
end

@testset "SQLite Dialect - Query Compilation" begin
    dialect = SQLiteDialect()

    @testset "From" begin
        q = from(:users)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users`"
        @test isempty(params)
    end

    @testset "Where" begin
        q = from(:users) |> where(col(:users, :active) == true)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` WHERE (`users`.`active` = 1)"
        @test isempty(params)
    end

    @testset "Where with Param" begin
        q = from(:users) |> where(col(:users, :id) == param(Int, :user_id))
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` WHERE (`users`.`id` = ?)"
        @test params == [:user_id]
    end

    @testset "Select" begin
        q = from(:users) |> select(NamedTuple, col(:users, :id), col(:users, :email))
        sql, params = compile(dialect, q)

        @test sql == "SELECT `users`.`id`, `users`.`email` FROM `users`"
        @test isempty(params)
    end

    @testset "Select with Where" begin
        q = from(:users) |>
            where(col(:users, :active) == true) |>
            select(NamedTuple, col(:users, :id), col(:users, :email))

        sql, params = compile(dialect, q)
        @test sql ==
              "SELECT `users`.`id`, `users`.`email` FROM `users` WHERE (`users`.`active` = 1)"
        @test isempty(params)
    end

    @testset "OrderBy - Single field ASC" begin
        q = from(:users) |> order_by(col(:users, :created_at), desc = false)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` ORDER BY `users`.`created_at` ASC"
        @test isempty(params)
    end

    @testset "OrderBy - Single field DESC" begin
        q = from(:users) |> order_by(col(:users, :created_at), desc = true)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` ORDER BY `users`.`created_at` DESC"
        @test isempty(params)
    end

    @testset "OrderBy - Multiple fields" begin
        q = from(:users) |>
            order_by(col(:users, :name), desc = false) |>
            order_by(col(:users, :created_at), desc = true)

        sql, params = compile(dialect, q)
        @test sql ==
              "SELECT * FROM `users` ORDER BY `users`.`name` ASC, `users`.`created_at` DESC"
        @test isempty(params)
    end

    @testset "Limit" begin
        q = from(:users) |> limit(10)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` LIMIT 10"
        @test isempty(params)
    end

    @testset "Offset" begin
        q = from(:users) |> offset(20)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` OFFSET 20"
        @test isempty(params)
    end

    @testset "Limit with Offset" begin
        q = from(:users) |> limit(10) |> offset(20)
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `users` LIMIT 10 OFFSET 20"
        @test isempty(params)
    end

    @testset "Distinct" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :email)) |>
            distinct

        sql, params = compile(dialect, q)
        @test sql == "SELECT DISTINCT `users`.`email` FROM `users`"
        @test isempty(params)
    end

    @testset "GroupBy" begin
        q = from(:orders) |> group_by(col(:orders, :user_id))
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `orders` GROUP BY `orders`.`user_id`"
        @test isempty(params)
    end

    @testset "GroupBy with multiple fields" begin
        q = from(:orders) |> group_by(col(:orders, :user_id), col(:orders, :status))
        sql, params = compile(dialect, q)

        @test sql == "SELECT * FROM `orders` GROUP BY `orders`.`user_id`, `orders`.`status`"
        @test isempty(params)
    end

    @testset "Having" begin
        q = from(:orders) |>
            group_by(col(:orders, :user_id)) |>
            having(func(:COUNT, [col(:orders, :id)]) > 5)

        sql, params = compile(dialect, q)
        @test sql ==
              "SELECT * FROM `orders` GROUP BY `orders`.`user_id` HAVING (COUNT(`orders`.`id`) > 5)"
        @test isempty(params)
    end

    @testset "Join - Inner" begin
        q = from(:users) |> join(:orders, col(:users, :id) == col(:orders, :user_id))
        sql, params = compile(dialect, q)

        @test sql ==
              "SELECT * FROM `users` INNER JOIN `orders` ON (`users`.`id` = `orders`.`user_id`)"
        @test isempty(params)
    end

    @testset "Join - Left" begin
        q = from(:users) |>
            join(:orders, col(:users, :id) == col(:orders, :user_id), kind = :left)
        sql, params = compile(dialect, q)

        @test sql ==
              "SELECT * FROM `users` LEFT JOIN `orders` ON (`users`.`id` = `orders`.`user_id`)"
        @test isempty(params)
    end
end

@testset "SQLite Dialect - Complex Queries" begin
    dialect = SQLiteDialect()

    @testset "Example 1: Active users with pagination" begin
        q = from(:users) |>
            where(col(:users, :active) == true) |>
            select(NamedTuple, col(:users, :id), col(:users, :email), col(:users, :name)) |>
            order_by(col(:users, :created_at), desc = true) |>
            limit(20) |>
            offset(0)

        sql, params = compile(dialect, q)
        expected = "SELECT `users`.`id`, `users`.`email`, `users`.`name` FROM `users` WHERE (`users`.`active` = 1) ORDER BY `users`.`created_at` DESC LIMIT 20 OFFSET 0"
        @test sql == expected
        @test isempty(params)
    end

    @testset "Example 2: Aggregation query" begin
        q = from(:orders) |>
            where(col(:orders, :status) == literal("completed")) |>
            group_by(col(:orders, :user_id)) |>
            having(func(:COUNT, [col(:orders, :id)]) > 5) |>
            select(NamedTuple,
                   col(:orders, :user_id),
                   func(:COUNT, [col(:orders, :id)]),
                   func(:SUM, [col(:orders, :total)]))

        sql, params = compile(dialect, q)
        # This is a complex rewrite - the SELECT fields override the previous SELECT *
        @test occursin("GROUP BY", sql)
        @test occursin("HAVING", sql)
        @test occursin("COUNT", sql)
        @test occursin("SUM", sql)
    end

    @testset "Example 3: Join query with parameters" begin
        q = from(:users) |>
            join(:orders, col(:users, :id) == col(:orders, :user_id), kind = :left) |>
            where(col(:users, :active) == param(Bool, :active)) |>
            select(NamedTuple,
                   col(:users, :email),
                   col(:orders, :id),
                   col(:orders, :total)) |>
            order_by(col(:orders, :created_at), desc = true)

        sql, params = compile(dialect, q)
        @test occursin("LEFT JOIN", sql)
        @test occursin("WHERE", sql)
        @test occursin("ORDER BY", sql)
        @test params == [:active]
    end

    @testset "Example 4: Multiple parameters" begin
        q = from(:users) |>
            where((col(:users, :age) > param(Int, :min_age)) &
                  (col(:users, :email) == param(String, :email)))

        sql, params = compile(dialect, q)
        @test occursin("?", sql)
        @test params == [:min_age, :email]
    end

    @testset "Example 5: Complex expression with functions" begin
        q = from(:users) |>
            where(func(:LOWER, [col(:users, :email)]) == param(String, :email_lower)) |>
            select(NamedTuple, col(:users, :id), func(:UPPER, [col(:users, :name)]))

        sql, params = compile(dialect, q)
        @test occursin("LOWER", sql)
        @test occursin("UPPER", sql)
        @test params == [:email_lower]
    end
end

@testset "SQLite Dialect - Edge Cases" begin
    dialect = SQLiteDialect()

    @testset "Empty SELECT fields" begin
        q = from(:users) |> select(NamedTuple)
        sql, params = compile(dialect, q)

        # Empty SELECT keeps SELECT *
        @test sql == "SELECT * FROM `users`"
        @test isempty(params)
    end

    @testset "Empty GROUP BY fields" begin
        q = from(:users) |> group_by()
        sql, params = compile(dialect, q)

        # Empty GROUP BY is omitted
        @test sql == "SELECT * FROM `users`"
        @test isempty(params)
    end

    @testset "NULL literal in comparison" begin
        q = from(:users) |> where(col(:users, :deleted_at) == nothing)
        sql, params = compile(dialect, q)

        @test occursin("NULL", sql)
        @test isempty(params)
    end

    @testset "Special characters in string literals" begin
        q = from(:users) |> where(col(:users, :name) == literal("O'Brien"))
        sql, params = compile(dialect, q)

        # Single quote should be escaped
        @test occursin("'O''Brien'", sql)
        @test isempty(params)
    end

    # DML (INSERT, UPDATE, DELETE) Tests
    @testset "DML Operations" begin
        @testset "INSERT INTO basic" begin
            q = insert_into(:users, [:name, :email])
            sql, params = compile(dialect, q)

            @test sql == "INSERT INTO `users` (`name`, `email`)"
            @test isempty(params)
        end

        @testset "INSERT...VALUES with literals" begin
            q = insert_into(:users, [:name, :email]) |>
                values([[literal("Alice"), literal("alice@example.com")]])
            sql, params = compile(dialect, q)

            @test sql == "INSERT INTO `users` (`name`, `email`) VALUES ('Alice', 'alice@example.com')"
            @test isempty(params)
        end

        @testset "INSERT...VALUES with parameters" begin
            q = insert_into(:users, [:name, :email]) |>
                values([[param(String, :name), param(String, :email)]])
            sql, params = compile(dialect, q)

            @test sql == "INSERT INTO `users` (`name`, `email`) VALUES (?, ?)"
            @test params == [:name, :email]
        end

        @testset "INSERT...VALUES multiple rows" begin
            q = insert_into(:users, [:name, :email]) |>
                values([
                    [literal("Alice"), literal("alice@example.com")],
                    [literal("Bob"), literal("bob@example.com")]
                ])
            sql, params = compile(dialect, q)

            @test sql == "INSERT INTO `users` (`name`, `email`) VALUES ('Alice', 'alice@example.com'), ('Bob', 'bob@example.com')"
            @test isempty(params)
        end

        @testset "UPDATE basic" begin
            q = update(:users)
            sql, params = compile(dialect, q)

            @test sql == "UPDATE `users`"
            @test isempty(params)
        end

        @testset "UPDATE...SET with literals" begin
            q = update(:users) |>
                set(:name => literal("Alice"), :email => literal("alice@example.com"))
            sql, params = compile(dialect, q)

            @test sql == "UPDATE `users` SET `name` = 'Alice', `email` = 'alice@example.com'"
            @test isempty(params)
        end

        @testset "UPDATE...SET with parameters" begin
            q = update(:users) |>
                set(:name => param(String, :name), :email => param(String, :email))
            sql, params = compile(dialect, q)

            @test sql == "UPDATE `users` SET `name` = ?, `email` = ?"
            @test params == [:name, :email]
        end

        @testset "UPDATE...SET...WHERE" begin
            q = update(:users) |>
                set(:name => param(String, :name)) |>
                where(col(:users, :id) == param(Int, :id))
            sql, params = compile(dialect, q)

            @test sql == "UPDATE `users` SET `name` = ? WHERE (`users`.`id` = ?)"
            @test params == [:name, :id]
        end

        @testset "DELETE FROM basic" begin
            q = delete_from(:users)
            sql, params = compile(dialect, q)

            @test sql == "DELETE FROM `users`"
            @test isempty(params)
        end

        @testset "DELETE FROM...WHERE with parameter" begin
            q = delete_from(:users) |>
                where(col(:users, :id) == param(Int, :id))
            sql, params = compile(dialect, q)

            @test sql == "DELETE FROM `users` WHERE (`users`.`id` = ?)"
            @test params == [:id]
        end

        @testset "DELETE FROM...WHERE with literal" begin
            q = delete_from(:users) |>
                where(col(:users, :active) == literal(false))
            sql, params = compile(dialect, q)

            @test sql == "DELETE FROM `users` WHERE (`users`.`active` = 0)"
            @test isempty(params)
        end

        @testset "DELETE FROM...WHERE with complex condition" begin
            q = delete_from(:users) |>
                where((col(:users, :created_at) < param(String, :date)) & (col(:users, :active) == literal(false)))
            sql, params = compile(dialect, q)

            @test occursin("DELETE FROM `users` WHERE", sql)
            @test occursin("`created_at`", sql)
            @test occursin("`active`", sql)
            @test occursin("AND", sql)
            @test params == [:date]
        end
    end

    # Pattern Matching and Range Operators Tests
    @testset "LIKE/ILIKE Operators" begin
        dialect = SQLiteDialect()

        @testset "LIKE operator" begin
            q = from(:users) |>
                where(like(col(:users, :email), literal("%@gmail.com")))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`users`.`email` LIKE '%@gmail.com'", sql)
            @test isempty(params)
        end

        @testset "NOT LIKE operator" begin
            q = from(:users) |>
                where(not_like(col(:users, :email), literal("%@spam.com")))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`users`.`email` NOT LIKE '%@spam.com'", sql)
            @test isempty(params)
        end

        @testset "LIKE with parameters" begin
            q = from(:users) |>
                where(like(col(:users, :name), param(String, :pattern)))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`users`.`name` LIKE ?", sql)
            @test params == [:pattern]
        end

        @testset "ILIKE operator (case-insensitive)" begin
            q = from(:users) |>
                where(ilike(col(:users, :email), literal("%@GMAIL.COM")))
            sql, params = compile(dialect, q)

            # SQLite emulates ILIKE with UPPER
            @test occursin("WHERE", sql)
            @test occursin("UPPER(`users`.`email`) LIKE UPPER('%@GMAIL.COM')", sql)
            @test isempty(params)
        end

        @testset "NOT ILIKE operator" begin
            q = from(:users) |>
                where(not_ilike(col(:users, :email), literal("%@SPAM.COM")))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("UPPER(`users`.`email`) NOT LIKE UPPER('%@SPAM.COM')", sql)
            @test isempty(params)
        end

        @testset "LIKE with wildcards" begin
            q = from(:users) |>
                where(like(col(:users, :name), literal("A_ice")))  # _ matches single char
            sql, params = compile(dialect, q)

            @test occursin("`users`.`name` LIKE 'A_ice'", sql)
        end
    end

    @testset "BETWEEN Operator" begin
        dialect = SQLiteDialect()

        @testset "BETWEEN with literals" begin
            q = from(:users) |>
                where(between(col(:users, :age), literal(18), literal(65)))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`users`.`age` BETWEEN 18 AND 65", sql)
            @test isempty(params)
        end

        @testset "BETWEEN with auto-wrapping" begin
            q = from(:users) |>
                where(between(col(:users, :age), 18, 65))
            sql, params = compile(dialect, q)

            @test occursin("`users`.`age` BETWEEN 18 AND 65", sql)
            @test isempty(params)
        end

        @testset "NOT BETWEEN" begin
            q = from(:users) |>
                where(not_between(col(:users, :age), 0, 17))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`users`.`age` NOT BETWEEN 0 AND 17", sql)
            @test isempty(params)
        end

        @testset "BETWEEN with parameters" begin
            q = from(:products) |>
                where(between(col(:products, :price), param(Float64, :min), param(Float64, :max)))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`products`.`price` BETWEEN ? AND ?", sql)
            @test params == [:min, :max]
        end

        @testset "BETWEEN with floating point" begin
            q = from(:products) |>
                where(between(col(:products, :price), 9.99, 99.99))
            sql, params = compile(dialect, q)

            @test occursin("`products`.`price` BETWEEN 9.99 AND 99.99", sql)
        end

        @testset "BETWEEN with dates (as strings)" begin
            q = from(:orders) |>
                where(between(col(:orders, :created_at), literal("2024-01-01"), literal("2024-12-31")))
            sql, params = compile(dialect, q)

            @test occursin("`orders`.`created_at` BETWEEN '2024-01-01' AND '2024-12-31'", sql)
        end
    end

    @testset "IN Operator" begin
        dialect = SQLiteDialect()

        @testset "IN with auto-wrapped literals (strings)" begin
            q = from(:users) |>
                where(in_list(col(:users, :status), ["active", "pending", "verified"]))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`users`.`status` IN ('active', 'pending', 'verified')", sql)
            @test isempty(params)
        end

        @testset "IN with auto-wrapped literals (integers)" begin
            q = from(:users) |>
                where(in_list(col(:users, :id), [1, 2, 3, 4, 5]))
            sql, params = compile(dialect, q)

            @test occursin("`users`.`id` IN (1, 2, 3, 4, 5)", sql)
            @test isempty(params)
        end

        @testset "IN with explicit literals" begin
            q = from(:users) |>
                where(in_list(col(:users, :role), [literal("admin"), literal("moderator")]))
            sql, params = compile(dialect, q)

            @test occursin("`users`.`role` IN ('admin', 'moderator')", sql)
            @test isempty(params)
        end

        @testset "NOT IN" begin
            q = from(:users) |>
                where(not_in_list(col(:users, :status), ["banned", "deleted"]))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`users`.`status` NOT IN ('banned', 'deleted')", sql)
            @test isempty(params)
        end

        @testset "IN with parameters" begin
            q = from(:users) |>
                where(in_list(col(:users, :id), [param(Int, :id1), param(Int, :id2), param(Int, :id3)]))
            sql, params = compile(dialect, q)

            @test occursin("WHERE", sql)
            @test occursin("`users`.`id` IN (?, ?, ?)", sql)
            @test params == [:id1, :id2, :id3]
        end

        @testset "IN with single value" begin
            q = from(:users) |>
                where(in_list(col(:users, :status), ["active"]))
            sql, params = compile(dialect, q)

            @test occursin("`users`.`status` IN ('active')", sql)
        end

        @testset "IN in complex query" begin
            q = from(:users) |>
                where(in_list(col(:users, :role), ["admin", "moderator"]) &
                      (col(:users, :active) == true)) |>
                select(NamedTuple, col(:users, :id), col(:users, :email))
            sql, params = compile(dialect, q)

            @test occursin("`users`.`role` IN ('admin', 'moderator')", sql)
            @test occursin("AND", sql)
            @test occursin("`users`.`active` = 1", sql)
        end

        @testset "IN with mixed types (floats)" begin
            q = from(:products) |>
                where(in_list(col(:products, :discount), [0.1, 0.2, 0.5]))
            sql, params = compile(dialect, q)

            @test occursin("`products`.`discount` IN (0.1, 0.2, 0.5)", sql)
        end
    end

    @testset "CTE Compilation" begin
        dialect = SQLiteDialect()

        @testset "Single CTE without column aliases" begin
            cte_query = from(:users) |> where(col(:users, :active) == literal(true))
            c = cte(:active_users, cte_query)
            main_query = from(:active_users) |>
                         select(NamedTuple, col(:active_users, :id),
                                col(:active_users, :email))
            q = with(c, main_query)

            sql, params = compile(dialect, q)

            @test occursin("WITH `active_users` AS (", sql)
            @test occursin("SELECT * FROM `users`", sql)
            @test occursin("WHERE (`users`.`active` = 1)", sql)
            @test occursin(
                          ") SELECT `active_users`.`id`, `active_users`.`email` FROM `active_users`",
                          sql)
            @test isempty(params)
        end

        @testset "Single CTE with column aliases" begin
            cte_query = from(:users) |> select(NamedTuple, col(:users, :id), col(:users, :email))
            main_query = from(:user_summary) |> select(NamedTuple, col(:user_summary, :user_id))
            q = with(:user_summary, cte_query, main_query, columns = [:user_id, :user_email])

            sql, params = compile(dialect, q)

            @test occursin("WITH `user_summary` (`user_id`, `user_email`) AS (", sql)
            @test occursin("SELECT `users`.`id`, `users`.`email` FROM `users`", sql)
            @test occursin(") SELECT `user_summary`.`user_id` FROM `user_summary`", sql)
            @test isempty(params)
        end

        @testset "Multiple CTEs" begin
            cte1_query = from(:users) |> where(col(:users, :active) == literal(true))
            cte2_query = from(:orders) |> where(col(:orders, :status) == literal("completed"))

            c1 = cte(:active_users, cte1_query)
            c2 = cte(:completed_orders, cte2_query)

            main_query = from(:active_users) |>
                         join(:completed_orders,
                              col(:active_users, :id) == col(:completed_orders, :user_id)) |>
                         select(NamedTuple, col(:active_users, :id),
                                col(:completed_orders, :total))

            q = with([c1, c2], main_query)
            sql, params = compile(dialect, q)

            # Check both CTEs are present
            @test occursin("WITH `active_users` AS (", sql)
            @test occursin("), `completed_orders` AS (", sql)
            @test occursin("WHERE (`users`.`active` = 1)", sql)
            @test occursin("WHERE (`orders`.`status` = 'completed')", sql)
            @test occursin("FROM `active_users`", sql)
            @test occursin("INNER JOIN `completed_orders`", sql)
            @test isempty(params)
        end

        @testset "CTE with parameters" begin
            cte_query = from(:users) |> where(col(:users, :active) == param(Bool, :is_active))
            c = cte(:active_users, cte_query)
            main_query = from(:active_users) |>
                         where(col(:active_users, :created_at) >
                               param(String, :min_date)) |>
                         select(NamedTuple, col(:active_users, :id))

            q = with(c, main_query)
            sql, params = compile(dialect, q)

            @test occursin("WITH `active_users` AS (", sql)
            @test occursin("WHERE (`users`.`active` = ?)", sql)
            @test occursin(
                          ") SELECT `active_users`.`id` FROM `active_users` WHERE (`active_users`.`created_at` > ?)",
                          sql)
            @test params == [:is_active, :min_date]
        end

        @testset "CTE with complex main query" begin
            cte_query = from(:users) |> where(col(:users, :active) == literal(true))
            c = cte(:active_users, cte_query)

            main_query = from(:active_users) |>
                         join(:orders, col(:active_users, :id) == col(:orders, :user_id)) |>
                         where(col(:orders, :total) > literal(100)) |>
                         group_by(col(:active_users, :id)) |>
                         having(func(:COUNT, [col(:orders, :id)]) > literal(5)) |>
                         select(NamedTuple, col(:active_users, :id),
                                func(:SUM, [col(:orders, :total)])) |>
                         order_by(col(:active_users, :id))

            q = with(c, main_query)
            sql, params = compile(dialect, q)

            @test occursin("WITH `active_users` AS (", sql)
            @test occursin("FROM `active_users`", sql)
            @test occursin("INNER JOIN `orders`", sql)
            @test occursin("WHERE (`orders`.`total` > 100)", sql)
            @test occursin("GROUP BY `active_users`.`id`", sql)
            @test occursin("HAVING (COUNT(`orders`.`id`) > 5)", sql)
            @test occursin("ORDER BY `active_users`.`id`", sql)
        end

        @testset "CTE with DISTINCT and LIMIT" begin
            cte_query = from(:users) |>
                        select(NamedTuple, col(:users, :email)) |>
                        distinct
            c = cte(:unique_emails, cte_query)

            main_query = from(:unique_emails) |>
                         select(NamedTuple, col(:unique_emails, :email)) |>
                         order_by(col(:unique_emails, :email)) |>
                         limit(10)

            q = with(c, main_query)
            sql, params = compile(dialect, q)

            @test occursin("WITH `unique_emails` AS (", sql)
            @test occursin("SELECT DISTINCT `users`.`email` FROM `users`", sql)
            @test occursin(
                          ") SELECT `unique_emails`.`email` FROM `unique_emails` ORDER BY `unique_emails`.`email` ASC LIMIT 10",
                          sql)
        end

        @testset "Nested CTE references" begin
            # CTE1: active users
            cte1_query = from(:users) |> where(col(:users, :active) == literal(true))
            c1 = cte(:active_users, cte1_query)

            # CTE2: orders from active users (references active_users)
            cte2_query = from(:orders) |>
                         join(:active_users,
                              col(:orders, :user_id) == col(:active_users, :id)) |>
                         select(NamedTuple, col(:orders, :id), col(:orders, :user_id),
                                col(:orders, :total))
            c2 = cte(:active_orders, cte2_query)

            # Main query: use active_orders
            main_query = from(:active_orders) |>
                         select(NamedTuple, col(:active_orders, :id), col(:active_orders, :total))

            q = with([c1, c2], main_query)
            sql, params = compile(dialect, q)

            @test occursin("WITH `active_users` AS (", sql)
            @test occursin("), `active_orders` AS (", sql)
            @test occursin("FROM `orders`", sql)
            @test occursin("INNER JOIN `active_users`", sql)
            @test occursin("FROM `active_orders`", sql)
        end

        @testset "CTE with aggregation" begin
            cte_query = from(:orders) |>
                        group_by(col(:orders, :user_id)) |>
                        select(NamedTuple, col(:orders, :user_id),
                               func(:SUM, [col(:orders, :total)]))

            c = cte(:user_totals, cte_query, columns = [:user_id, :total_spent])

            main_query = from(:user_totals) |>
                         where(col(:user_totals, :total_spent) > literal(1000)) |>
                         select(NamedTuple, col(:user_totals, :user_id),
                                col(:user_totals, :total_spent))

            q = with(c, main_query)
            sql, params = compile(dialect, q)

            @test occursin("WITH `user_totals` (`user_id`, `total_spent`) AS (", sql)
            @test occursin("GROUP BY `orders`.`user_id`", sql)
            @test occursin("SELECT `orders`.`user_id`, SUM(`orders`.`total`) FROM `orders`",
                           sql)
            @test occursin("WHERE (`user_totals`.`total_spent` > 1000)", sql)
        end
    end
end
