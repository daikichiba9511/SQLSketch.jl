using Test
using SQLSketch.Core: Dialect, Capability, CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW,
                      CAP_LATERAL
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
        q = from(:users) |> inner_join(:orders, col(:users, :id) == col(:orders, :user_id))
        sql, params = compile(dialect, q)

        @test sql ==
              "SELECT * FROM `users` INNER JOIN `orders` ON (`users`.`id` = `orders`.`user_id`)"
        @test isempty(params)
    end

    @testset "Join - Left" begin
        q = from(:users) |>
            left_join(:orders, col(:users, :id) == col(:orders, :user_id))
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
            left_join(:orders, col(:users, :id) == col(:orders, :user_id)) |>
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
                insert_values([[literal("Alice"), literal("alice@example.com")]])
            sql, params = compile(dialect, q)

            @test sql ==
                  "INSERT INTO `users` (`name`, `email`) VALUES ('Alice', 'alice@example.com')"
            @test isempty(params)
        end

        @testset "INSERT...VALUES with parameters" begin
            q = insert_into(:users, [:name, :email]) |>
                insert_values([[param(String, :name), param(String, :email)]])
            sql, params = compile(dialect, q)

            @test sql == "INSERT INTO `users` (`name`, `email`) VALUES (?, ?)"
            @test params == [:name, :email]
        end

        @testset "INSERT...VALUES multiple rows" begin
            q = insert_into(:users, [:name, :email]) |>
                insert_values([[literal("Alice"), literal("alice@example.com")],
                               [literal("Bob"), literal("bob@example.com")]])
            sql, params = compile(dialect, q)

            @test sql ==
                  "INSERT INTO `users` (`name`, `email`) VALUES ('Alice', 'alice@example.com'), ('Bob', 'bob@example.com')"
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
                set_values(:name => literal("Alice"), :email => literal("alice@example.com"))
            sql, params = compile(dialect, q)

            @test sql ==
                  "UPDATE `users` SET `name` = 'Alice', `email` = 'alice@example.com'"
            @test isempty(params)
        end

        @testset "UPDATE...SET with parameters" begin
            q = update(:users) |>
                set_values(:name => param(String, :name), :email => param(String, :email))
            sql, params = compile(dialect, q)

            @test sql == "UPDATE `users` SET `name` = ?, `email` = ?"
            @test params == [:name, :email]
        end

        @testset "UPDATE...SET...WHERE" begin
            q = update(:users) |>
                set_values(:name => param(String, :name)) |>
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
                where((col(:users, :created_at) < param(String, :date)) &
                      (col(:users, :active) == literal(false)))
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
                where(between(col(:products, :price), param(Float64, :min),
                              param(Float64, :max)))
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
                where(between(col(:orders, :created_at), literal("2024-01-01"),
                              literal("2024-12-31")))
            sql, params = compile(dialect, q)

            @test occursin("`orders`.`created_at` BETWEEN '2024-01-01' AND '2024-12-31'",
                           sql)
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
                where(in_list(col(:users, :id),
                              [param(Int, :id1), param(Int, :id2), param(Int, :id3)]))
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
            @test occursin(") SELECT `active_users`.`id`, `active_users`.`email` FROM `active_users`",
                           sql)
            @test isempty(params)
        end

        @testset "Single CTE with column aliases" begin
            cte_query = from(:users) |>
                        select(NamedTuple, col(:users, :id), col(:users, :email))
            main_query = from(:user_summary) |>
                         select(NamedTuple, col(:user_summary, :user_id))
            q = with(:user_summary, cte_query, main_query,
                     columns = [:user_id, :user_email])

            sql, params = compile(dialect, q)

            @test occursin("WITH `user_summary` (`user_id`, `user_email`) AS (", sql)
            @test occursin("SELECT `users`.`id`, `users`.`email` FROM `users`", sql)
            @test occursin(") SELECT `user_summary`.`user_id` FROM `user_summary`", sql)
            @test isempty(params)
        end

        @testset "Multiple CTEs" begin
            cte1_query = from(:users) |> where(col(:users, :active) == literal(true))
            cte2_query = from(:orders) |>
                         where(col(:orders, :status) == literal("completed"))

            c1 = cte(:active_users, cte1_query)
            c2 = cte(:completed_orders, cte2_query)

            main_query = from(:active_users) |>
                         inner_join(:completed_orders,
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
            cte_query = from(:users) |>
                        where(col(:users, :active) == param(Bool, :is_active))
            c = cte(:active_users, cte_query)
            main_query = from(:active_users) |>
                         where(col(:active_users, :created_at) >
                               param(String, :min_date)) |>
                         select(NamedTuple, col(:active_users, :id))

            q = with(c, main_query)
            sql, params = compile(dialect, q)

            @test occursin("WITH `active_users` AS (", sql)
            @test occursin("WHERE (`users`.`active` = ?)", sql)
            @test occursin(") SELECT `active_users`.`id` FROM `active_users` WHERE (`active_users`.`created_at` > ?)",
                           sql)
            @test params == [:is_active, :min_date]
        end

        @testset "CTE with complex main query" begin
            cte_query = from(:users) |> where(col(:users, :active) == literal(true))
            c = cte(:active_users, cte_query)

            main_query = from(:active_users) |>
                         inner_join(:orders, col(:active_users, :id) == col(:orders, :user_id)) |>
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
            @test occursin(") SELECT `unique_emails`.`email` FROM `unique_emails` ORDER BY `unique_emails`.`email` ASC LIMIT 10",
                           sql)
        end

        @testset "Nested CTE references" begin
            # CTE1: active users
            cte1_query = from(:users) |> where(col(:users, :active) == literal(true))
            c1 = cte(:active_users, cte1_query)

            # CTE2: orders from active users (references active_users)
            cte2_query = from(:orders) |>
                         inner_join(:active_users,
                              col(:orders, :user_id) == col(:active_users, :id)) |>
                         select(NamedTuple, col(:orders, :id), col(:orders, :user_id),
                                col(:orders, :total))
            c2 = cte(:active_orders, cte2_query)

            # Main query: use active_orders
            main_query = from(:active_orders) |>
                         select(NamedTuple, col(:active_orders, :id),
                                col(:active_orders, :total))

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

    @testset "RETURNING Clause Compilation" begin
        @testset "INSERT...RETURNING with literals" begin
            q = insert_into(:users, [:email, :name]) |>
                insert_values([[literal("test@example.com"), literal("Test User")]]) |>
                returning(NamedTuple, col(:users, :id), col(:users, :email))

            sql, params = compile(dialect, q)

            @test occursin("INSERT INTO `users` (`email`, `name`)", sql)
            @test occursin("VALUES ('test@example.com', 'Test User')", sql)
            @test occursin("RETURNING `users`.`id`, `users`.`email`", sql)
            @test isempty(params)
        end

        @testset "INSERT...RETURNING with parameters" begin
            q = insert_into(:users, [:email, :name]) |>
                insert_values([[param(String, :email), param(String, :name)]]) |>
                returning(NamedTuple, col(:users, :id), col(:users, :email),
                          col(:users, :name))

            sql, params = compile(dialect, q)

            @test occursin("INSERT INTO `users` (`email`, `name`)", sql)
            @test occursin("VALUES (?, ?)", sql)
            @test occursin("RETURNING `users`.`id`, `users`.`email`, `users`.`name`", sql)
            @test params == [:email, :name]
        end

        @testset "INSERT...RETURNING with placeholder syntax" begin
            q = insert_into(:users, [:email]) |>
                insert_values([[param(String, :email)]]) |>
                returning(NamedTuple, p_.id, p_.email, p_.created_at)

            sql, params = compile(dialect, q)

            @test occursin("INSERT INTO `users` (`email`)", sql)
            @test occursin("VALUES (?)", sql)
            # Placeholders should be resolved to explicit col(:users, ...)
            @test occursin("RETURNING `users`.`id`, `users`.`email`, `users`.`created_at`",
                           sql)
            @test params == [:email]
        end

        @testset "UPDATE...RETURNING with WHERE" begin
            q = update(:users) |>
                set_values(:status => literal("premium"), :updated_at => literal("2025-01-01")) |>
                where(col(:users, :id) == param(Int, :id)) |>
                returning(NamedTuple, col(:users, :id), col(:users, :status),
                          col(:users, :updated_at))

            sql, params = compile(dialect, q)

            @test occursin("UPDATE `users`", sql)
            @test occursin("SET `status` = 'premium', `updated_at` = '2025-01-01'", sql)
            @test occursin("WHERE (`users`.`id` = ?)", sql)
            @test occursin("RETURNING `users`.`id`, `users`.`status`, `users`.`updated_at`",
                           sql)
            @test params == [:id]
        end

        @testset "UPDATE...RETURNING without WHERE" begin
            q = update(:users) |>
                set_values(:status => literal("active")) |>
                returning(NamedTuple, col(:users, :id), col(:users, :status))

            sql, params = compile(dialect, q)

            @test occursin("UPDATE `users`", sql)
            @test occursin("SET `status` = 'active'", sql)
            @test occursin("RETURNING `users`.`id`, `users`.`status`", sql)
            @test !occursin("WHERE", sql)
            @test isempty(params)
        end

        @testset "UPDATE...RETURNING with placeholder syntax" begin
            q = update(:users) |>
                set_values(:status => param(String, :status)) |>
                where(p_.id == param(Int, :id)) |>
                returning(NamedTuple, p_.id, p_.status, p_.email)

            sql, params = compile(dialect, q)

            @test occursin("UPDATE `users`", sql)
            @test occursin("SET `status` = ?", sql)
            @test occursin("WHERE (`users`.`id` = ?)", sql)
            @test occursin("RETURNING `users`.`id`, `users`.`status`, `users`.`email`", sql)
            @test params == [:status, :id]
        end

        @testset "DELETE...RETURNING with WHERE" begin
            q = delete_from(:users) |>
                where(col(:users, :status) == literal("inactive")) |>
                returning(NamedTuple, col(:users, :id), col(:users, :email))

            sql, params = compile(dialect, q)

            @test occursin("DELETE FROM `users`", sql)
            @test occursin("WHERE (`users`.`status` = 'inactive')", sql)
            @test occursin("RETURNING `users`.`id`, `users`.`email`", sql)
            @test isempty(params)
        end

        @testset "DELETE...RETURNING without WHERE" begin
            q = delete_from(:users) |>
                returning(NamedTuple, col(:users, :id))

            sql, params = compile(dialect, q)

            @test occursin("DELETE FROM `users`", sql)
            @test occursin("RETURNING `users`.`id`", sql)
            @test !occursin("WHERE", sql)
            @test isempty(params)
        end

        @testset "DELETE...RETURNING with placeholder and parameters" begin
            q = delete_from(:users) |>
                where(p_.created_at < param(String, :cutoff_date)) |>
                returning(NamedTuple, p_.id, p_.email, p_.created_at)

            sql, params = compile(dialect, q)

            @test occursin("DELETE FROM `users`", sql)
            @test occursin("WHERE (`users`.`created_at` < ?)", sql)
            @test occursin("RETURNING `users`.`id`, `users`.`email`, `users`.`created_at`",
                           sql)
            @test params == [:cutoff_date]
        end

        @testset "RETURNING with single field" begin
            q = insert_into(:users, [:email]) |>
                insert_values([[literal("test@example.com")]]) |>
                returning(NamedTuple, col(:users, :id))

            sql, params = compile(dialect, q)

            @test occursin("RETURNING `users`.`id`", sql)
            @test isempty(params)
        end

        @testset "RETURNING with multiple rows INSERT" begin
            q = insert_into(:users, [:email]) |>
                insert_values([[literal("user1@example.com")],
                        [literal("user2@example.com")],
                        [literal("user3@example.com")]]) |>
                returning(NamedTuple, col(:users, :id), col(:users, :email))

            sql, params = compile(dialect, q)

            @test occursin("INSERT INTO `users` (`email`)", sql)
            @test occursin("VALUES ('user1@example.com'), ('user2@example.com'), ('user3@example.com')",
                           sql)
            @test occursin("RETURNING `users`.`id`, `users`.`email`", sql)
            @test isempty(params)
        end
    end
end

# DDL Compilation Tests

using SQLSketch.Core: CreateTable, AlterTable, DropTable, CreateIndex, DropIndex
using SQLSketch.Core: create_table, add_column, add_primary_key, add_foreign_key
using SQLSketch.Core: add_unique, add_check
using SQLSketch.Core: alter_table, add_alter_column, drop_alter_column, rename_alter_column
using SQLSketch.Core: set_column_default, drop_column_default, set_column_not_null,
                      drop_column_not_null, set_column_type
using SQLSketch.Core: drop_table, create_index, drop_index

@testset "SQLite Dialect - DDL Compilation" begin
    dialect = SQLiteDialect()

    @testset "CREATE TABLE - Basic" begin
        # Empty table (no columns)
        ddl = create_table(:users)
        sql, params = compile(dialect, ddl)
        @test sql == "CREATE TABLE `users` ()"
        @test isempty(params)

        # Single column
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true)
        sql, params = compile(dialect, ddl)
        @test sql == "CREATE TABLE `users` (`id` INTEGER PRIMARY KEY)"
        @test isempty(params)

        # Multiple columns
        ddl = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text, nullable = false)
        sql, params = compile(dialect, ddl)
        @test sql ==
              "CREATE TABLE `users` (`id` INTEGER PRIMARY KEY, `email` TEXT NOT NULL)"
        @test isempty(params)
    end

    @testset "CREATE TABLE - Column Types" begin
        test_types = [(:integer, "INTEGER"),
                      (:bigint, "INTEGER"),
                      (:real, "REAL"),
                      (:text, "TEXT"),
                      (:blob, "BLOB"),
                      (:boolean, "INTEGER"),
                      (:timestamp, "TEXT"),
                      (:date, "TEXT"),
                      (:uuid, "TEXT"),
                      (:json, "TEXT")]

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
        @test isempty(params)  # Literal is inline

        # DEFAULT with current_timestamp
        ddl = create_table(:users) |> add_column(:created_at, :timestamp,
                                                 default = func(:CURRENT_TIMESTAMP, SQLExpr[]))
        sql, _ = compile(dialect, ddl)
        @test occursin("DEFAULT", sql)

        # FOREIGN KEY (column-level)
        ddl = create_table(:posts) |>
              add_column(:user_id, :integer, references = (:users, :id))
        sql, _ = compile(dialect, ddl)
        @test occursin("REFERENCES `users`(`id`)", sql)

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

        # CHECK constraint
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
        @test occursin("CREATE TEMPORARY TABLE IF NOT EXISTS `temp_cache`", sql)
    end

    @testset "ALTER TABLE - ADD COLUMN" begin
        ddl = alter_table(:users) |> add_alter_column(:age, :integer)
        sql, params = compile(dialect, ddl)
        @test sql == "ALTER TABLE `users` ADD COLUMN `age` INTEGER"
        @test isempty(params)

        # With constraints
        ddl = alter_table(:users) |>
              add_alter_column(:email_verified, :boolean, nullable = false,
                               default = literal(false))
        sql, _ = compile(dialect, ddl)
        @test occursin("ALTER TABLE `users` ADD COLUMN `email_verified`", sql)
        @test occursin("NOT NULL", sql)
        @test occursin("DEFAULT", sql)
    end

    @testset "ALTER TABLE - RENAME COLUMN" begin
        ddl = alter_table(:users) |> rename_alter_column(:old_name, :new_name)
        sql, params = compile(dialect, ddl)
        @test sql == "ALTER TABLE `users` RENAME COLUMN `old_name` TO `new_name`"
        @test isempty(params)
    end

    @testset "ALTER TABLE - Unsupported Operations" begin
        # DROP COLUMN not supported
        ddl = alter_table(:users) |> drop_alter_column(:old_field)
        @test_throws ErrorException compile(dialect, ddl)

        # Multiple operations warning
        ddl = alter_table(:users) |>
              add_alter_column(:age, :integer) |>
              rename_alter_column(:old_name, :new_name)
        @test_logs (:warn,) compile(dialect, ddl)
    end

    @testset "DROP TABLE" begin
        ddl = drop_table(:users)
        sql, params = compile(dialect, ddl)
        @test sql == "DROP TABLE `users`"
        @test isempty(params)

        # IF EXISTS
        ddl = drop_table(:users, if_exists = true)
        sql, _ = compile(dialect, ddl)
        @test sql == "DROP TABLE IF EXISTS `users`"

        # CASCADE (not supported, should warn)
        ddl = drop_table(:users, cascade = true)
        @test_logs (:warn,) compile(dialect, ddl)
    end

    @testset "CREATE INDEX" begin
        # Basic index
        ddl = create_index(:idx_users_email, :users, [:email])
        sql, params = compile(dialect, ddl)
        @test sql == "CREATE INDEX `idx_users_email` ON `users` (`email`)"
        @test isempty(params)

        # UNIQUE index
        ddl = create_index(:idx_users_email, :users, [:email], unique = true)
        sql, _ = compile(dialect, ddl)
        @test sql == "CREATE UNIQUE INDEX `idx_users_email` ON `users` (`email`)"

        # IF NOT EXISTS
        ddl = create_index(:idx_users_email, :users, [:email], if_not_exists = true)
        sql, _ = compile(dialect, ddl)
        @test occursin("IF NOT EXISTS", sql)

        # Composite index
        ddl = create_index(:idx_user_email, :users, [:user_id, :email])
        sql, _ = compile(dialect, ddl)
        @test occursin("(`user_id`, `email`)", sql)

        # Partial index (with WHERE)
        ddl = create_index(:idx_active_users, :users, [:id],
                           where = col(:users, :active) == literal(true))
        sql, params = compile(dialect, ddl)
        @test occursin("WHERE", sql)
        @test occursin("`users`.`active`", sql)
    end

    @testset "CREATE INDEX - Expression Indexes" begin
        # Single expression index
        ddl = create_index(:idx_users_lower_email, :users, Symbol[],
                           expr = [func(:lower, [col(:users, :email)])])
        sql, params = compile(dialect, ddl)
        @test sql ==
              "CREATE INDEX `idx_users_lower_email` ON `users` (lower(`users`.`email`))"
        @test isempty(params)

        # Multiple expression index
        ddl2 = create_index(:idx_users_name, :users, Symbol[],
                            expr = [func(:lower, [col(:users, :first_name)]),
                                    func(:lower, [col(:users, :last_name)])])
        sql2, _ = compile(dialect, ddl2)
        @test occursin("lower(`users`.`first_name`), lower(`users`.`last_name`)", sql2)

        # Expression index with WHERE clause
        ddl3 = create_index(:idx_active_emails, :users, Symbol[],
                            expr = [func(:lower, [col(:users, :email)])],
                            where = col(:users, :active) == literal(true))
        sql3, _ = compile(dialect, ddl3)
        @test occursin("lower(`users`.`email`)", sql3)
        @test occursin("WHERE (`users`.`active` = 1)", sql3)

        # Unique expression index
        ddl4 = create_index(:idx_users_lower_email_unique, :users, Symbol[],
                            expr = [func(:lower, [col(:users, :email)])],
                            unique = true)
        sql4, _ = compile(dialect, ddl4)
        @test occursin("CREATE UNIQUE INDEX", sql4)
        @test occursin("lower(`users`.`email`)", sql4)
    end

    @testset "CREATE INDEX - Index Method (ignored in SQLite)" begin
        # SQLite ignores method parameter (no error, just silently ignore)
        ddl = create_index(:idx_users_tags, :users, [:tags], method = :gin)
        sql, _ = compile(dialect, ddl)
        @test sql == "CREATE INDEX `idx_users_tags` ON `users` (`tags`)"
        @test !occursin("USING", sql)  # SQLite doesn't support USING clause

        # Expression index with method (also ignored)
        ddl2 = create_index(:idx_lower_email, :users, Symbol[],
                            expr = [func(:lower, [col(:users, :email)])],
                            method = :btree)
        sql2, _ = compile(dialect, ddl2)
        @test !occursin("USING", sql2)
        @test occursin("lower(`users`.`email`)", sql2)
    end

    @testset "DROP INDEX" begin
        ddl = drop_index(:idx_users_email)
        sql, params = compile(dialect, ddl)
        @test sql == "DROP INDEX `idx_users_email`"
        @test isempty(params)

        # IF EXISTS
        ddl = drop_index(:idx_users_email, if_exists = true)
        sql, _ = compile(dialect, ddl)
        @test sql == "DROP INDEX IF EXISTS `idx_users_email`"
    end

    @testset "Complex Schema Compilation" begin
        # Complete users table
        users = create_table(:users, if_not_exists = true) |>
                add_column(:id, :integer, primary_key = true) |>
                add_column(:email, :text, nullable = false) |>
                add_column(:username, :text, nullable = false) |>
                add_column(:created_at, :timestamp,
                           default = func(:CURRENT_TIMESTAMP, SQLExpr[])) |>
                add_unique([:email]) |>
                add_unique([:username])

        sql, params = compile(dialect, users)
        @test occursin("CREATE TABLE IF NOT EXISTS `users`", sql)
        @test occursin("`id` INTEGER PRIMARY KEY", sql)
        @test occursin("`email` TEXT NOT NULL", sql)
        @test occursin("`username` TEXT NOT NULL", sql)
        @test occursin("UNIQUE (`email`)", sql)
        @test occursin("UNIQUE (`username`)", sql)
        @test isempty(params)

        # Posts table with foreign key
        posts = create_table(:posts) |>
                add_column(:id, :integer, primary_key = true) |>
                add_column(:user_id, :integer, nullable = false) |>
                add_column(:title, :text, nullable = false) |>
                add_column(:body, :text) |>
                add_foreign_key([:user_id], :users, [:id], on_delete = :cascade)

        sql, _ = compile(dialect, posts)
        @test occursin("CREATE TABLE `posts`", sql)
        @test occursin("FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE",
                       sql)
    end

    @testset "Extended Column Constraints - SQLite" begin
        # Column-level CHECK constraint
        ddl = create_table(:users) |>
              add_column(:age, :integer; check = col(:users, :age) >= literal(18))
        sql, _ = compile(dialect, ddl)
        @test occursin("CHECK ((`users`.`age` >= 18))", sql)

        # AUTO_INCREMENT constraint
        ddl2 = create_table(:users) |>
               add_column(:id, :integer; primary_key = true, auto_increment = true)
        sql2, _ = compile(dialect, ddl2)
        @test occursin("INTEGER PRIMARY KEY AUTOINCREMENT", sql2)

        # GENERATED column (STORED)
        ddl3 = create_table(:users) |>
               add_column(:id, :integer) |>
               add_column(:double_id, :integer;
                          generated = col(:users, :id) * literal(2))
        sql3, _ = compile(dialect, ddl3)
        @test occursin("GENERATED ALWAYS AS ((`users`.`id` * 2)) STORED", sql3)

        # GENERATED column (VIRTUAL)
        ddl4 = create_table(:users) |>
               add_column(:id, :integer) |>
               add_column(:double_id, :integer;
                          generated = col(:users, :id) * literal(2), stored = false)
        sql4, _ = compile(dialect, ddl4)
        @test occursin("GENERATED ALWAYS AS ((`users`.`id` * 2)) VIRTUAL", sql4)

        # COLLATION constraint
        ddl5 = create_table(:users) |>
               add_column(:email, :text; collation = :nocase)
        sql5, _ = compile(dialect, ddl5)
        @test occursin("TEXT COLLATE nocase", sql5)

        # Multiple constraints combined
        ddl6 = create_table(:users) |>
               add_column(:id, :integer; primary_key = true, auto_increment = true) |>
               add_column(:age, :integer; nullable = false,
                          check = col(:users, :age) >= literal(0))
        sql6, _ = compile(dialect, ddl6)
        @test occursin("INTEGER PRIMARY KEY AUTOINCREMENT", sql6)
        @test occursin("INTEGER NOT NULL CHECK", sql6)
    end

    @testset "Identifier Quoting in DDL" begin
        # Table names with special characters
        ddl = create_table(Symbol("user data")) |> add_column(:id, :integer)
        sql, _ = compile(dialect, ddl)
        @test occursin("`user data`", sql)

        # Column names with special characters
        ddl = create_table(:users) |> add_column(Symbol("email address"), :text)
        sql, _ = compile(dialect, ddl)
        @test occursin("`email address`", sql)

        # Index names
        ddl = create_index(Symbol("idx-users-email"), :users, [:email])
        sql, _ = compile(dialect, ddl)
        @test occursin("`idx-users-email`", sql)
    end

    @testset "ALTER COLUMN - Not Supported (SQLite)" begin
        # SET DEFAULT - not supported
        ddl = alter_table(:users) |>
              set_column_default(:status, literal("active"))
        @test_throws ErrorException compile(dialect, ddl)

        # DROP DEFAULT - not supported
        ddl2 = alter_table(:users) |>
               drop_column_default(:status)
        @test_throws ErrorException compile(dialect, ddl2)

        # SET NOT NULL - not supported
        ddl3 = alter_table(:users) |>
               set_column_not_null(:email)
        @test_throws ErrorException compile(dialect, ddl3)

        # DROP NOT NULL - not supported
        ddl4 = alter_table(:users) |>
               drop_column_not_null(:phone)
        @test_throws ErrorException compile(dialect, ddl4)

        # SET TYPE - not supported
        ddl5 = alter_table(:users) |>
               set_column_type(:age, :bigint)
        @test_throws ErrorException compile(dialect, ddl5)

        # SET STATISTICS - PostgreSQL only
        ddl6 = alter_table(:users) |>
               set_column_statistics(:email, 1000)
        @test_throws ErrorException compile(dialect, ddl6)

        # SET STORAGE - PostgreSQL only
        ddl7 = alter_table(:users) |>
               set_column_storage(:bio, :external)
        @test_throws ErrorException compile(dialect, ddl7)
    end
end
