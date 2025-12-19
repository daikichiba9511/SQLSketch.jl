using Test
using SQLSketch.Core: Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy,
                      Having, Join
using SQLSketch.Core: from, where, select, order_by, limit, offset, distinct, group_by,
                      having, join
using SQLSketch.Core: SQLExpr, col, literal, param, func

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

    @testset "join() helper - inner join" begin
        source = from(:users)
        on_condition = col(:users, :id) == col(:orders, :user_id)
        q = join(source, :orders, on_condition)

        @test q isa Join{NamedTuple}
        @test q.source === source
        @test q.table == :orders
        @test q.on === on_condition
        @test q.kind == :inner  # default
    end

    @testset "join() helper - left join" begin
        source = from(:users)
        on_condition = col(:users, :id) == col(:orders, :user_id)
        q = join(source, :orders, on_condition, kind = :left)

        @test q isa Join{NamedTuple}
        @test q.kind == :left
    end

    @testset "join() helper - invalid kind" begin
        source = from(:users)
        on_condition = col(:users, :id) == col(:orders, :user_id)
        @test_throws AssertionError join(source, :orders, on_condition, kind = :invalid)
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
            join(:orders, col(:users, :id) == col(:orders, :user_id)) |>
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
            join(:orders, col(:users, :id) == col(:orders, :user_id), kind = :left) |>
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
end
