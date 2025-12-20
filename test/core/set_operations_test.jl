using Test
using SQLSketch.Core: Query, From, Where, Select, OrderBy, Limit
using SQLSketch.Core: SetUnion, SetIntersect, SetExcept
using SQLSketch.Core: from, where, select, order_by, limit
using SQLSketch.Core: union, intersect, except
using SQLSketch.Core: SQLExpr, col, literal, param
using SQLSketch: SQLiteDialect
using SQLSketch.Core: compile

@testset "Set Operations AST" begin
    @testset "Union constructor" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        # Basic UNION
        u = SetUnion{NamedTuple}(q1, q2, false)
        @test u isa Query{NamedTuple}
        @test u isa SetUnion{NamedTuple}
        @test u.left === q1
        @test u.right === q2
        @test u.all == false

        # UNION ALL
        u_all = SetUnion{NamedTuple}(q1, q2, true)
        @test u_all.all == true
    end

    @testset "union() helper - explicit" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        # Default (UNION)
        u = union(q1, q2)
        @test u isa SetUnion{NamedTuple}
        @test u.left === q1
        @test u.right === q2
        @test u.all == false

        # UNION ALL
        u_all = union(q1, q2, all = true)
        @test u_all.all == true
    end

    @testset "union() helper - curried" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        # Default (UNION)
        u = q1 |> union(q2)
        @test u isa SetUnion{NamedTuple}
        @test u.left === q1
        @test u.right === q2
        @test u.all == false

        # UNION ALL
        u_all = q1 |> union(q2, all = true)
        @test u_all.all == true
    end

    @testset "Intersect constructor" begin
        q1 = from(:customers) |> select(NamedTuple, col(:customers, :id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :customer_id))

        # Basic INTERSECT
        i = SetIntersect{NamedTuple}(q1, q2, false)
        @test i isa Query{NamedTuple}
        @test i isa SetIntersect{NamedTuple}
        @test i.left === q1
        @test i.right === q2
        @test i.all == false

        # INTERSECT ALL
        i_all = SetIntersect{NamedTuple}(q1, q2, true)
        @test i_all.all == true
    end

    @testset "intersect() helper - explicit" begin
        q1 = from(:customers) |> select(NamedTuple, col(:customers, :id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :customer_id))

        # Default (INTERSECT)
        i = intersect(q1, q2)
        @test i isa SetIntersect{NamedTuple}
        @test i.left === q1
        @test i.right === q2
        @test i.all == false

        # INTERSECT ALL
        i_all = intersect(q1, q2, all = true)
        @test i_all.all == true
    end

    @testset "intersect() helper - curried" begin
        q1 = from(:customers) |> select(NamedTuple, col(:customers, :id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :customer_id))

        # Default (INTERSECT)
        i = q1 |> intersect(q2)
        @test i isa SetIntersect{NamedTuple}
        @test i.left === q1
        @test i.right === q2
        @test i.all == false

        # INTERSECT ALL
        i_all = q1 |> intersect(q2, all = true)
        @test i_all.all == true
    end

    @testset "Except constructor" begin
        q1 = from(:all_users) |> select(NamedTuple, col(:all_users, :id))
        q2 = from(:banned_users) |> select(NamedTuple, col(:banned_users, :user_id))

        # Basic EXCEPT
        e = SetExcept{NamedTuple}(q1, q2, false)
        @test e isa Query{NamedTuple}
        @test e isa SetExcept{NamedTuple}
        @test e.left === q1
        @test e.right === q2
        @test e.all == false

        # EXCEPT ALL
        e_all = SetExcept{NamedTuple}(q1, q2, true)
        @test e_all.all == true
    end

    @testset "except() helper - explicit" begin
        q1 = from(:all_users) |> select(NamedTuple, col(:all_users, :id))
        q2 = from(:banned_users) |> select(NamedTuple, col(:banned_users, :user_id))

        # Default (EXCEPT)
        e = except(q1, q2)
        @test e isa SetExcept{NamedTuple}
        @test e.left === q1
        @test e.right === q2
        @test e.all == false

        # EXCEPT ALL
        e_all = except(q1, q2, all = true)
        @test e_all.all == true
    end

    @testset "except() helper - curried" begin
        q1 = from(:all_users) |> select(NamedTuple, col(:all_users, :id))
        q2 = from(:banned_users) |> select(NamedTuple, col(:banned_users, :user_id))

        # Default (EXCEPT)
        e = q1 |> except(q2)
        @test e isa SetExcept{NamedTuple}
        @test e.left === q1
        @test e.right === q2
        @test e.all == false

        # EXCEPT ALL
        e_all = q1 |> except(q2, all = true)
        @test e_all.all == true
    end

    @testset "Set operations with WHERE clauses" begin
        q1 = from(:users) |>
             where(col(:users, :active) == literal(true)) |>
             select(NamedTuple, col(:users, :email))

        q2 = from(:admins) |>
             where(col(:admins, :verified) == literal(true)) |>
             select(NamedTuple, col(:admins, :email))

        u = union(q1, q2)
        @test u isa SetUnion{NamedTuple}
        @test u.left.source isa Where{NamedTuple}
        @test u.right.source isa Where{NamedTuple}
    end

    @testset "Set operations with ORDER BY" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        # UNION with ORDER BY on result
        u = union(q1, q2) |> order_by(col(:users, :email))
        @test u isa OrderBy{NamedTuple}
        @test u.source isa SetUnion{NamedTuple}
    end

    @testset "Set operations with LIMIT" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        # UNION with LIMIT
        u = union(q1, q2) |> limit(10)
        @test u isa Limit{NamedTuple}
        @test u.source isa SetUnion{NamedTuple}
    end

    @testset "Multiple set operations chained" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))
        q3 = from(:guests) |> select(NamedTuple, col(:guests, :email))

        # UNION then UNION
        u = union(q1, q2) |> union(q3)
        @test u isa SetUnion{NamedTuple}
        @test u.left isa SetUnion{NamedTuple}
        @test u.right === q3
    end

    @testset "Type safety - same output type required" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        # Both have NamedTuple - OK
        u = union(q1, q2)
        @test u isa SetUnion{NamedTuple}
    end

    @testset "Structural equality - Union" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        u1 = union(q1, q2)
        u2 = union(q1, q2)
        @test isequal(u1, u2)

        u3 = union(q1, q2, all = true)
        @test !isequal(u1, u3)  # Different `all` flag
    end

    @testset "Structural equality - Intersect" begin
        q1 = from(:customers) |> select(NamedTuple, col(:customers, :id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :customer_id))

        i1 = intersect(q1, q2)
        i2 = intersect(q1, q2)
        @test isequal(i1, i2)

        i3 = intersect(q1, q2, all = true)
        @test !isequal(i1, i3)
    end

    @testset "Structural equality - Except" begin
        q1 = from(:all_users) |> select(NamedTuple, col(:all_users, :id))
        q2 = from(:banned_users) |> select(NamedTuple, col(:banned_users, :user_id))

        e1 = except(q1, q2)
        e2 = except(q1, q2)
        @test isequal(e1, e2)

        e3 = except(q1, q2, all = true)
        @test !isequal(e1, e3)
    end

    @testset "Hashing - Union" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        u1 = union(q1, q2)
        u2 = union(q1, q2)
        @test hash(u1) == hash(u2)

        # Can be used in Dict/Set
        d = Dict(u1 => "test")
        @test haskey(d, u2)
    end

    @testset "Hashing - Intersect" begin
        q1 = from(:customers) |> select(NamedTuple, col(:customers, :id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :customer_id))

        i1 = intersect(q1, q2)
        i2 = intersect(q1, q2)
        @test hash(i1) == hash(i2)
    end

    @testset "Hashing - Except" begin
        q1 = from(:all_users) |> select(NamedTuple, col(:all_users, :id))
        q2 = from(:banned_users) |> select(NamedTuple, col(:banned_users, :user_id))

        e1 = except(q1, q2)
        e2 = except(q1, q2)
        @test hash(e1) == hash(e2)
    end

    @testset "Complex pipeline with set operations" begin
        # Real-world example: Get all active emails from users and admins
        active_users = from(:users) |>
                       where(col(:users, :active) == literal(true)) |>
                       select(NamedTuple, col(:users, :email))

        active_admins = from(:admins) |>
                        where(col(:admins, :active) == literal(true)) |>
                        select(NamedTuple, col(:admins, :email))

        all_active = active_users |>
                     union(active_admins) |>
                     order_by(col(:users, :email)) |>
                     limit(100)

        @test all_active isa Limit{NamedTuple}
        @test all_active.source isa OrderBy{NamedTuple}
        @test all_active.source.source isa SetUnion{NamedTuple}
    end

    @testset "UNION ALL vs UNION" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        # UNION (removes duplicates)
        u_distinct = union(q1, q2, all = false)
        @test u_distinct.all == false

        # UNION ALL (keeps duplicates)
        u_all = union(q1, q2, all = true)
        @test u_all.all == true
    end
end

@testset "Set Operations SQL Compilation" begin
    dialect = SQLiteDialect()

    @testset "UNION compilation" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))
        q = union(q1, q2)

        sql, params = compile(dialect, q)
        @test occursin("UNION", sql)
        @test occursin("SELECT `users`.`email` FROM `users`", sql)
        @test occursin("SELECT `admins`.`email` FROM `admins`", sql)
        @test isempty(params)
    end

    @testset "UNION ALL compilation" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))
        q = union(q1, q2, all = true)

        sql, params = compile(dialect, q)
        @test occursin("UNION ALL", sql)
        @test isempty(params)
    end

    @testset "INTERSECT compilation" begin
        q1 = from(:customers) |> select(NamedTuple, col(:customers, :id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :customer_id))
        q = intersect(q1, q2)

        sql, params = compile(dialect, q)
        @test occursin("INTERSECT", sql)
        @test occursin("SELECT `customers`.`id` FROM `customers`", sql)
        @test occursin("SELECT `orders`.`customer_id` FROM `orders`", sql)
        @test isempty(params)
    end

    @testset "EXCEPT compilation" begin
        q1 = from(:all_users) |> select(NamedTuple, col(:all_users, :id))
        q2 = from(:banned_users) |> select(NamedTuple, col(:banned_users, :user_id))
        q = except(q1, q2)

        sql, params = compile(dialect, q)
        @test occursin("EXCEPT", sql)
        @test occursin("SELECT `all_users`.`id` FROM `all_users`", sql)
        @test occursin("SELECT `banned_users`.`user_id` FROM `banned_users`", sql)
        @test isempty(params)
    end

    @testset "Set operations with parameters" begin
        q1 = from(:users) |>
             where(col(:users, :active) == param(Bool, :active1)) |>
             select(NamedTuple, col(:users, :email))

        q2 = from(:admins) |>
             where(col(:admins, :verified) == param(Bool, :verified2)) |>
             select(NamedTuple, col(:admins, :email))

        q = union(q1, q2)

        sql, params = compile(dialect, q)
        @test occursin("UNION", sql)
        @test length(params) == 2
        @test :active1 in params
        @test :verified2 in params
    end

    @testset "Chained set operations" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))
        q3 = from(:guests) |> select(NamedTuple, col(:guests, :email))

        # (q1 UNION q2) UNION q3
        q = union(union(q1, q2), q3)

        sql, params = compile(dialect, q)
        # Should have two UNION operators
        @test length(collect(eachmatch(r"UNION", sql))) == 2
        @test isempty(params)
    end

    @testset "Set operations with ORDER BY and LIMIT" begin
        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:admins) |> select(NamedTuple, col(:admins, :email))

        q = union(q1, q2) |>
            order_by(col(:users, :email)) |>
            limit(10)

        sql, params = compile(dialect, q)
        @test occursin("UNION", sql)
        @test occursin("ORDER BY", sql)
        @test occursin("LIMIT", sql)
        @test isempty(params)
    end

    @testset "Complex set operations with WHERE" begin
        active_users = from(:users) |>
                       where(col(:users, :status) == literal("active")) |>
                       select(NamedTuple, col(:users, :id))

        premium_users = from(:users) |>
                        where(col(:users, :plan) == literal("premium")) |>
                        select(NamedTuple, col(:users, :id))

        banned_users = from(:banned) |>
                       select(NamedTuple, col(:banned, :user_id))

        # (active UNION premium) EXCEPT banned
        q = union(active_users, premium_users) |> except(banned_users)

        sql, params = compile(dialect, q)
        @test occursin("UNION", sql)
        @test occursin("EXCEPT", sql)
        @test occursin("WHERE", sql)
        @test isempty(params)
    end
end
