using Test
using SQLSketch.Core: Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy,
                      Having, Join, CTE, With, Returning
using SQLSketch.Core: from, where, select, order_by, limit, offset, distinct, group_by,
                      having, inner_join, left_join, right_join, full_join, cte, with, returning
using SQLSketch.Core: insert_into, insert_values, update, set_values, delete_from
using SQLSketch.Core: SQLExpr, col, literal, param, func
using SQLSketch.Extras: p_

@testset "Query AST" begin
    @testset "From constructor" begin
        q = From{NamedTuple}(:users)
        @test q isa Query{NamedTuple}
        @test q isa From{NamedTuple}
        @test q.table == :users
    end

    @testset "from() helper" begin
        q = from(:users)
        @test q isa From{NamedTuple}
        @test q.table == :users
    end

    @testset "Where constructor" begin
        source = from(:users)
        condition = col(:users, :active) == literal(true)
        q = Where(source, condition)

        @test q isa Query{NamedTuple}
        @test q isa Where{NamedTuple}
        @test q.source === source
        @test q.condition === condition
    end

    @testset "where() helper" begin
        source = from(:users)
        condition = col(:users, :active) == literal(true)
        q = where(source, condition)

        @test q isa Where{NamedTuple}
        @test q.source === source
        @test q.condition === condition
    end

    @testset "Select constructor" begin
        source = from(:users)
        fields = SQLExpr[col(:users, :id), col(:users, :email)]
        q = Select{NamedTuple}(source, fields)

        @test q isa Query{NamedTuple}
        @test q isa Select{NamedTuple}
        @test q.source === source
        @test isequal(q.fields, fields)
    end

    @testset "select() helper" begin
        source = from(:users)
        q = select(source, NamedTuple, col(:users, :id), col(:users, :email))

        @test q isa Select{NamedTuple}
        @test q.source === source
        @test length(q.fields) == 2
        @test isequal(q.fields[1], col(:users, :id))
        @test isequal(q.fields[2], col(:users, :email))
    end

    @testset "OrderBy constructor" begin
        source = from(:users)
        orderings = Tuple{SQLExpr, Bool}[(col(:users, :created_at), true)]
        q = OrderBy(source, orderings)

        @test q isa Query{NamedTuple}
        @test q isa OrderBy{NamedTuple}
        @test q.source === source
        @test isequal(q.orderings, orderings)
    end

    @testset "order_by() helper" begin
        source = from(:users)
        q = order_by(source, col(:users, :created_at), desc = true)

        @test q isa OrderBy{NamedTuple}
        @test q.source === source
        @test length(q.orderings) == 1
        @test isequal(q.orderings[1], (col(:users, :created_at), true))
    end

    @testset "order_by() multiple fields" begin
        source = from(:users)
        q = source |>
            order_by(col(:users, :name), desc = false) |>
            order_by(col(:users, :created_at), desc = true)

        @test q isa OrderBy{NamedTuple}
        @test length(q.orderings) == 2
        @test isequal(q.orderings[1], (col(:users, :name), false))
        @test isequal(q.orderings[2], (col(:users, :created_at), true))
    end

    @testset "Limit constructor" begin
        source = from(:users)
        q = Limit(source, 10)

        @test q isa Query{NamedTuple}
        @test q isa Limit{NamedTuple}
        @test q.source === source
        @test q.n == 10
    end

    @testset "limit() helper" begin
        source = from(:users)
        q = limit(source, 10)

        @test q isa Limit{NamedTuple}
        @test q.source === source
        @test q.n == 10
    end

    @testset "Offset constructor" begin
        source = from(:users)
        q = Offset(source, 20)

        @test q isa Query{NamedTuple}
        @test q isa Offset{NamedTuple}
        @test q.source === source
        @test q.n == 20
    end

    @testset "offset() helper" begin
        source = from(:users)
        q = offset(source, 20)

        @test q isa Offset{NamedTuple}
        @test q.source === source
        @test q.n == 20
    end

    @testset "Distinct constructor" begin
        source = from(:users)
        q = Distinct(source)

        @test q isa Query{NamedTuple}
        @test q isa Distinct{NamedTuple}
        @test q.source === source
    end

    @testset "distinct() helper" begin
        source = from(:users)
        q = distinct(source)

        @test q isa Distinct{NamedTuple}
        @test q.source === source
    end

    @testset "GroupBy constructor" begin
        source = from(:orders)
        fields = SQLExpr[col(:orders, :user_id)]
        q = GroupBy(source, fields)

        @test q isa Query{NamedTuple}
        @test q isa GroupBy{NamedTuple}
        @test q.source === source
        @test isequal(q.fields, fields)
    end

    @testset "group_by() helper" begin
        source = from(:orders)
        q = group_by(source, col(:orders, :user_id))

        @test q isa GroupBy{NamedTuple}
        @test q.source === source
        @test length(q.fields) == 1
        @test isequal(q.fields[1], col(:orders, :user_id))
    end

    @testset "group_by() multiple fields" begin
        source = from(:orders)
        q = group_by(source, col(:orders, :user_id), col(:orders, :status))

        @test q isa GroupBy{NamedTuple}
        @test length(q.fields) == 2
        @test isequal(q.fields[1], col(:orders, :user_id))
        @test isequal(q.fields[2], col(:orders, :status))
    end

    @testset "Having constructor" begin
        source = from(:orders)
        condition = func(:COUNT, [col(:orders, :id)]) > literal(5)
        q = Having(source, condition)

        @test q isa Query{NamedTuple}
        @test q isa Having{NamedTuple}
        @test q.source === source
        @test q.condition === condition
    end

    @testset "having() helper" begin
        source = from(:orders)
        condition = func(:COUNT, [col(:orders, :id)]) > literal(5)
        q = having(source, condition)

        @test q isa Having{NamedTuple}
        @test q.source === source
        @test q.condition === condition
    end

    @testset "Join constructor" begin
        source = from(:users)
        on_condition = col(:users, :id) == col(:orders, :user_id)
        q = Join(source, :orders, on_condition, :inner)

        @test q isa Query{NamedTuple}
        @test q isa Join{NamedTuple}
        @test q.source === source
        @test q.table == :orders
        @test q.on === on_condition
        @test q.kind == :inner
    end

    @testset "inner_join() helper" begin
        source = from(:users)
        on_condition = col(:users, :id) == col(:orders, :user_id)
        q = inner_join(source, :orders, on_condition)

        @test q isa Join{NamedTuple}
        @test q.source === source
        @test q.table == :orders
        @test q.on === on_condition
        @test q.kind == :inner
    end

    @testset "left_join() helper" begin
        source = from(:users)
        on_condition = col(:users, :id) == col(:orders, :user_id)
        q = left_join(source, :orders, on_condition)

        @test q isa Join{NamedTuple}
        @test q.kind == :left
    end

    @testset "right_join() helper" begin
        source = from(:users)
        on_condition = col(:users, :id) == col(:orders, :user_id)
        q = right_join(source, :orders, on_condition)

        @test q isa Join{NamedTuple}
        @test q.kind == :right
    end

    @testset "full_join() helper" begin
        source = from(:users)
        on_condition = col(:users, :id) == col(:orders, :user_id)
        q = full_join(source, :orders, on_condition)

        @test q isa Join{NamedTuple}
        @test q.kind == :full
    end
end

@testset "Query Pipeline Composition" begin
    @testset "Simple pipeline with |>" begin
        q = from(:users) |>
            where(col(:users, :active) == literal(true)) |>
            select(NamedTuple, col(:users, :id), col(:users, :email)) |>
            limit(10)

        @test q isa Limit{NamedTuple}
        @test q.source isa Select{NamedTuple}
        @test q.source.source isa Where{NamedTuple}
        @test q.source.source.source isa From{NamedTuple}
    end

    @testset "Complex pipeline" begin
        q = from(:users) |>
            where(col(:users, :active) == literal(true)) |>
            select(NamedTuple, col(:users, :id), col(:users, :email),
                   col(:users, :created_at)) |>
            order_by(col(:users, :created_at), desc = true) |>
            limit(10) |>
            offset(20)

        @test q isa Offset{NamedTuple}
        @test q.source isa Limit{NamedTuple}
        @test q.source.source isa OrderBy{NamedTuple}
        @test q.source.source.source isa Select{NamedTuple}
        @test q.source.source.source.source isa Where{NamedTuple}
        @test q.source.source.source.source.source isa From{NamedTuple}
    end

    @testset "Pipeline with join" begin
        q = from(:users) |>
            inner_join(:orders, col(:users, :id) == col(:orders, :user_id)) |>
            where(col(:orders, :status) == literal("completed")) |>
            select(NamedTuple, col(:users, :email), col(:orders, :total))

        @test q isa Select{NamedTuple}
        @test q.source isa Where{NamedTuple}
        @test q.source.source isa Join{NamedTuple}
        @test q.source.source.source isa From{NamedTuple}
    end

    @testset "Pipeline with group by and having" begin
        q = from(:orders) |>
            group_by(col(:orders, :user_id)) |>
            having(func(:COUNT, [col(:orders, :id)]) > literal(5)) |>
            select(NamedTuple, col(:orders, :user_id), func(:COUNT, [col(:orders, :id)]))

        @test q isa Select{NamedTuple}
        @test q.source isa Having{NamedTuple}
        @test q.source.source isa GroupBy{NamedTuple}
        @test q.source.source.source isa From{NamedTuple}
    end

    @testset "Pipeline with distinct" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :email)) |>
            distinct

        @test q isa Distinct{NamedTuple}
        @test q.source isa Select{NamedTuple}
        @test q.source.source isa From{NamedTuple}
    end
end

@testset "Type Safety" begin
    @testset "Shape-preserving operations maintain type" begin
        q1 = from(:users)
        @test q1 isa Query{NamedTuple}

        q2 = where(q1, col(:users, :active) == literal(true))
        @test q2 isa Query{NamedTuple}

        q3 = order_by(q2, col(:users, :created_at))
        @test q3 isa Query{NamedTuple}

        q4 = limit(q3, 10)
        @test q4 isa Query{NamedTuple}
    end

    @testset "select() changes output type" begin
        struct UserDTO
            id::Int
            email::String
        end

        q1 = from(:users)
        @test q1 isa Query{NamedTuple}

        q2 = select(q1, UserDTO, col(:users, :id), col(:users, :email))
        @test q2 isa Query{UserDTO}
        @test q2 isa Select{UserDTO}
    end

    @testset "Operations after select preserve new type" begin
        struct UserDTO2
            id::Int
            email::String
        end

        q = from(:users) |>
            select(UserDTO2, col(:users, :id), col(:users, :email)) |>
            limit(10)

        @test q isa Query{UserDTO2}
        @test q isa Limit{UserDTO2}
        @test q.source isa Select{UserDTO2}
    end
end

@testset "Query Immutability" begin
    @testset "Query nodes are immutable" begin
        q1 = from(:users)
        @test_throws ErrorException (q1.table = :orders)

        q2 = where(q1, col(:users, :active) == literal(true))
        @test_throws ErrorException (q2.source = from(:orders))

        q3 = select(q1, NamedTuple, col(:users, :id))
        @test_throws ErrorException (q3.fields = [])
    end

    @testset "Adding to pipeline doesn't modify original" begin
        q1 = from(:users)
        q2 = where(q1, col(:users, :active) == literal(true))
        q3 = limit(q2, 10)

        # q1 and q2 should remain unchanged
        @test q1 isa From{NamedTuple}
        @test q2 isa Where{NamedTuple}
        @test q3 isa Limit{NamedTuple}

        # Each should be independent
        @test q1.table == :users
        @test q2.source === q1
        @test q3.source === q2
    end
end

@testset "Edge Cases" begin
    @testset "Empty select fields" begin
        q = from(:users)
        q2 = select(q, NamedTuple)  # No fields

        @test q2 isa Select{NamedTuple}
        @test length(q2.fields) == 0
    end

    @testset "Empty group by fields" begin
        q = from(:users)
        q2 = group_by(q)  # No fields

        @test q2 isa GroupBy{NamedTuple}
        @test length(q2.fields) == 0
    end

    @testset "Multiple order_by calls accumulate" begin
        q = from(:users) |>
            order_by(col(:users, :name)) |>
            order_by(col(:users, :created_at), desc = true)

        @test q isa OrderBy{NamedTuple}
        @test length(q.orderings) == 2
        @test isequal(q.orderings[1][1], col(:users, :name))
        @test q.orderings[1][2] == false
        @test isequal(q.orderings[2][1], col(:users, :created_at))
        @test q.orderings[2][2] == true
    end

    @testset "Limit/Offset with zero" begin
        q1 = from(:users) |> limit(0)
        @test q1.n == 0

        q2 = from(:users) |> offset(0)
        @test q2.n == 0
    end
end

@testset "Real-World Query Examples" begin
    @testset "Example 1: Active users with pagination" begin
        q = from(:users) |>
            where(col(:users, :active) == literal(true)) |>
            select(NamedTuple, col(:users, :id), col(:users, :email), col(:users, :name)) |>
            order_by(col(:users, :created_at), desc = true) |>
            limit(20) |>
            offset(0)

        @test q isa Offset{NamedTuple}
        @test q.n == 0
        @test q.source isa Limit{NamedTuple}
        @test q.source.n == 20
    end

    @testset "Example 2: Aggregation query" begin
        q = from(:orders) |>
            where(col(:orders, :status) == literal("completed")) |>
            group_by(col(:orders, :user_id)) |>
            having(func(:COUNT, [col(:orders, :id)]) > literal(5)) |>
            select(NamedTuple,
                   col(:orders, :user_id),
                   func(:COUNT, [col(:orders, :id)]),
                   func(:SUM, [col(:orders, :total)]))

        @test q isa Select{NamedTuple}
        @test length(q.fields) == 3
    end

    @testset "Example 3: Join query" begin
        q = from(:users) |>
            left_join(:orders, col(:users, :id) == col(:orders, :user_id)) |>
            where(col(:users, :active) == literal(true)) |>
            select(NamedTuple,
                   col(:users, :email),
                   col(:orders, :id),
                   col(:orders, :total)) |>
            order_by(col(:orders, :created_at), desc = true)

        @test q isa OrderBy{NamedTuple}
        @test q.source isa Select{NamedTuple}
        @test q.source.source isa Where{NamedTuple}
        @test q.source.source.source isa Join{NamedTuple}
        @test q.source.source.source.kind == :left
    end

    @testset "Example 4: Distinct email addresses" begin
        q = from(:users) |>
            select(NamedTuple, col(:users, :email)) |>
            distinct |>
            order_by(col(:users, :email))

        @test q isa OrderBy{NamedTuple}
        @test q.source isa Distinct{NamedTuple}
        @test q.source.source isa Select{NamedTuple}
    end

    # CTE (Common Table Expressions) Tests
    @testset "CTE constructor" begin
        subq = from(:users) |> where(col(:users, :active) == literal(true))

        # Without column aliases
        c = CTE(:active_users, Symbol[], subq)
        @test c.name == :active_users
        @test c.columns == Symbol[]
        @test c.query === subq

        # With column aliases
        c2 = CTE(:active_users, [:id, :email], subq)
        @test c2.name == :active_users
        @test c2.columns == [:id, :email]
        @test c2.query === subq
    end

    @testset "cte() helper" begin
        subq = from(:users) |> where(col(:users, :active) == literal(true))

        # Basic CTE without column aliases
        c = cte(:active_users, subq)
        @test c isa CTE
        @test c.name == :active_users
        @test c.columns == Symbol[]
        @test c.query === subq

        # CTE with column aliases
        c2 = cte(:user_summary, subq, columns = [:user_id, :user_email])
        @test c2 isa CTE
        @test c2.name == :user_summary
        @test c2.columns == [:user_id, :user_email]
        @test c2.query === subq
    end

    @testset "With constructor - single CTE" begin
        subq = from(:users) |> where(col(:users, :active) == literal(true))
        c = cte(:active_users, subq)
        main_q = from(:active_users) |> select(NamedTuple, col(:active_users, :id))

        w = With{NamedTuple}([c], main_q)
        @test w isa Query{NamedTuple}
        @test w isa With{NamedTuple}
        @test length(w.ctes) == 1
        @test w.ctes[1] === c
        @test w.main_query === main_q
    end

    @testset "With constructor - multiple CTEs" begin
        subq1 = from(:users) |> where(col(:users, :active) == literal(true))
        subq2 = from(:orders) |> where(col(:orders, :status) == literal("completed"))
        c1 = cte(:active_users, subq1)
        c2 = cte(:completed_orders, subq2)
        main_q = from(:active_users) |>
                 inner_join(:completed_orders,
                            col(:active_users, :id) == col(:completed_orders, :user_id)) |>
                 select(NamedTuple, col(:active_users, :id))

        w = With{NamedTuple}([c1, c2], main_q)
        @test w isa With{NamedTuple}
        @test length(w.ctes) == 2
        @test w.ctes[1] === c1
        @test w.ctes[2] === c2
        @test w.main_query === main_q
    end

    @testset "with() helper - single CTE object" begin
        subq = from(:users) |> where(col(:users, :active) == literal(true))
        c = cte(:active_users, subq)
        main_q = from(:active_users) |> select(NamedTuple, col(:active_users, :id))

        w = with(c, main_q)
        @test w isa With{NamedTuple}
        @test length(w.ctes) == 1
        @test w.ctes[1] === c
        @test w.main_query === main_q
    end

    @testset "with() helper - multiple CTE objects" begin
        subq1 = from(:users) |> where(col(:users, :active) == literal(true))
        subq2 = from(:orders) |> where(col(:orders, :status) == literal("completed"))
        c1 = cte(:active_users, subq1)
        c2 = cte(:completed_orders, subq2)
        main_q = from(:active_users) |> select(NamedTuple, col(:active_users, :id))

        w = with([c1, c2], main_q)
        @test w isa With{NamedTuple}
        @test length(w.ctes) == 2
        @test w.ctes[1] === c1
        @test w.ctes[2] === c2
    end

    @testset "with() helper - convenience syntax" begin
        subq = from(:users) |> where(col(:users, :active) == literal(true))
        main_q = from(:active_users) |> select(NamedTuple, col(:active_users, :id))

        # Without column aliases
        w = with(:active_users, subq, main_q)
        @test w isa With{NamedTuple}
        @test length(w.ctes) == 1
        @test w.ctes[1].name == :active_users
        @test w.ctes[1].columns == Symbol[]
        @test w.ctes[1].query === subq
        @test w.main_query === main_q

        # With column aliases
        w2 = with(:active_users, subq, main_q, columns = [:user_id, :is_active])
        @test w2 isa With{NamedTuple}
        @test w2.ctes[1].columns == [:user_id, :is_active]
    end

    @testset "CTE type preservation" begin
        # Output type should come from main_query
        subq = from(:users) |> where(col(:users, :active) == literal(true))
        c = cte(:active_users, subq)

        # Main query returns NamedTuple
        main_q1 = from(:active_users) |> select(NamedTuple, col(:active_users, :id))
        w1 = with(c, main_q1)
        @test w1 isa With{NamedTuple}

        # If we had a custom type (hypothetically)
        struct User
            id::Int
        end
        main_q2 = from(:active_users) |> select(User, col(:active_users, :id))
        w2 = with(c, main_q2)
        @test w2 isa With{User}
    end

    @testset "CTE structural equality" begin
        subq1 = from(:users) |> where(col(:users, :active) == literal(true))
        subq2 = from(:users) |> where(col(:users, :active) == literal(true))

        c1 = CTE(:active_users, Symbol[], subq1)
        c2 = CTE(:active_users, Symbol[], subq1)  # same instance
        c3 = CTE(:active_users, Symbol[], subq2)  # different instance, same structure
        c4 = CTE(:different_name, Symbol[], subq1)

        @test isequal(c1, c2)
        @test isequal(c1, c3)  # structural equality
        @test !isequal(c1, c4)  # different name

        # With column aliases
        c5 = CTE(:active_users, [:id, :email], subq1)
        c6 = CTE(:active_users, [:id, :email], subq1)
        @test isequal(c5, c6)
        @test !isequal(c1, c5)  # different columns
    end

    @testset "With structural equality" begin
        subq = from(:users) |> where(col(:users, :active) == literal(true))
        c = cte(:active_users, subq)
        main_q = from(:active_users) |> select(NamedTuple, col(:active_users, :id))

        w1 = With{NamedTuple}([c], main_q)
        w2 = With{NamedTuple}([c], main_q)
        @test isequal(w1, w2)

        # Different main query
        main_q2 = from(:active_users) |> select(NamedTuple, col(:active_users, :email))
        w3 = With{NamedTuple}([c], main_q2)
        @test !isequal(w1, w3)
    end

    @testset "CTE hash functions" begin
        subq = from(:users) |> where(col(:users, :active) == literal(true))
        c1 = cte(:active_users, subq)
        c2 = cte(:active_users, subq)

        # Same structure should have same hash
        @test hash(c1) == hash(c2)

        # Can be used in Dict/Set
        dict = Dict(c1 => "value")
        @test haskey(dict, c2)  # structural equality
    end

    @testset "RETURNING clause" begin
        @testset "Returning constructor with INSERT" begin
            insert_q = insert_into(:users, [:email]) |>
                       insert_values([[literal("test@example.com")]])
            fields = [col(:users, :id), col(:users, :email)]
            q = Returning{NamedTuple}(insert_q, fields)

            @test q isa Query{NamedTuple}
            @test q isa Returning{NamedTuple}
            @test q.source === insert_q
            @test isequal(q.fields, fields)
        end

        @testset "Returning constructor with UPDATE" begin
            update_q = update(:users) |>
                       set_values(:status => literal("active")) |>
                       where(col(:users, :id) == param(Int, :id))
            fields = [col(:users, :id), col(:users, :status)]
            q = Returning{NamedTuple}(update_q, fields)

            @test q isa Returning{NamedTuple}
            @test q.source === update_q
            @test isequal(q.fields, fields)
        end

        @testset "Returning constructor with DELETE" begin
            delete_q = delete_from(:users) |>
                       where(col(:users, :status) == literal("inactive"))
            fields = [col(:users, :id), col(:users, :email)]
            q = Returning{NamedTuple}(delete_q, fields)

            @test q isa Returning{NamedTuple}
            @test q.source === delete_q
            @test isequal(q.fields, fields)
        end

        @testset "returning() helper with explicit version" begin
            insert_q = insert_into(:users, [:email]) |>
                       insert_values([[literal("test@example.com")]])
            q = returning(insert_q, NamedTuple, col(:users, :id), col(:users, :email))

            @test q isa Returning{NamedTuple}
            @test q.source === insert_q
            @test length(q.fields) == 2
        end

        @testset "returning() curried for pipeline" begin
            q = insert_into(:users, [:email]) |>
                insert_values([[literal("test@example.com")]]) |>
                returning(NamedTuple, col(:users, :id), col(:users, :email))

            @test q isa Returning{NamedTuple}
            @test length(q.fields) == 2
        end

        @testset "RETURNING with placeholder syntax" begin
            q = insert_into(:users, [:email]) |>
                insert_values([[param(String, :email)]]) |>
                returning(NamedTuple, p_.id, p_.email)

            @test q isa Returning{NamedTuple}
            @test length(q.fields) == 2
            # Fields should contain PlaceholderField nodes
            @test all(f -> f isa SQLExpr, q.fields)
        end

        @testset "RETURNING type changes output type (shape-changing)" begin
            # INSERT returns NamedTuple
            insert_q = insert_into(:users, [:email]) |>
                       insert_values([[literal("test@example.com")]])
            @test insert_q isa Query{NamedTuple}

            # RETURNING changes type to specified OutT
            struct UserResult
                id::Int
                email::String
            end
            q = returning(insert_q, UserResult, col(:users, :id), col(:users, :email))

            @test q isa Query{UserResult}
            @test q isa Returning{UserResult}
        end

        @testset "RETURNING structural equality" begin
            insert_q = insert_into(:users, [:email]) |>
                       insert_values([[literal("test@example.com")]])
            r1 = returning(insert_q, NamedTuple, col(:users, :id), col(:users, :email))
            r2 = returning(insert_q, NamedTuple, col(:users, :id), col(:users, :email))

            @test isequal(r1, r2)

            # Different fields
            r3 = returning(insert_q, NamedTuple, col(:users, :id))
            @test !isequal(r1, r3)

            # Different source
            different_insert = insert_into(:users, [:name]) |>
                               insert_values([[literal("Alice")]])
            r4 = returning(different_insert, NamedTuple, col(:users, :id),
                           col(:users, :email))
            @test !isequal(r1, r4)
        end

        @testset "RETURNING hash function" begin
            insert_q = insert_into(:users, [:email]) |>
                       insert_values([[literal("test@example.com")]])
            r1 = returning(insert_q, NamedTuple, col(:users, :id), col(:users, :email))
            r2 = returning(insert_q, NamedTuple, col(:users, :id), col(:users, :email))

            # Same structure should have same hash
            @test hash(r1) == hash(r2)

            # Can be used in Dict/Set
            dict = Dict(r1 => "value")
            @test haskey(dict, r2)
        end

        @testset "RETURNING with UPDATE SET variations" begin
            # UPDATE without WHERE
            q1 = update(:users) |>
                 set_values(:status => literal("active")) |>
                 returning(NamedTuple, col(:users, :id))
            @test q1 isa Returning{NamedTuple}

            # UPDATE with WHERE
            q2 = update(:users) |>
                 set_values(:status => literal("active")) |>
                 where(col(:users, :id) == param(Int, :id)) |>
                 returning(NamedTuple, col(:users, :id), col(:users, :status))
            @test q2 isa Returning{NamedTuple}
        end

        @testset "RETURNING with DELETE variations" begin
            # DELETE without WHERE
            q1 = delete_from(:users) |>
                 returning(NamedTuple, col(:users, :id))
            @test q1 isa Returning{NamedTuple}

            # DELETE with WHERE
            q2 = delete_from(:users) |>
                 where(col(:users, :status) == literal("inactive")) |>
                 returning(NamedTuple, col(:users, :id), col(:users, :email))
            @test q2 isa Returning{NamedTuple}
        end
    end
end
