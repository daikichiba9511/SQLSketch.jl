using Test
using SQLSketch.Core: Dialect, Capability, CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW,
                      CAP_LATERAL
using SQLSketch.Core: Query, From, Where, Select, Join, OrderBy, Limit, Offset, Distinct,
                      GroupBy, Having
using SQLSketch.Core: InsertInto, InsertValues, Update, UpdateSet, UpdateWhere,
                      DeleteFrom, DeleteWhere
using SQLSketch.Core: from, where, select, join, order_by, limit, offset, distinct,
                      group_by, having
using SQLSketch.Core: insert_into, values, update, set, delete_from
using SQLSketch.Core: SQLExpr, col, literal, param, func, is_null, is_not_null
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
end
