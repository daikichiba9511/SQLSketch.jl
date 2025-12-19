"""
# Expression AST Tests

Unit tests for the expression AST implementation.

These tests validate:
- Expression type construction
- Operator overloading
- Expression composition
- Type correctness

See `docs/roadmap.md` Phase 1 for implementation plan.
"""

using Test
using SQLSketch.Core: SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall, BetweenOp, InOp
using SQLSketch.Core: Cast, Subquery
using SQLSketch.Core: col, literal, param, func, is_null, is_not_null
using SQLSketch.Core: like, not_like, ilike, not_ilike, between, not_between
using SQLSketch.Core: in_list, not_in_list
using SQLSketch.Core: cast, subquery, exists, not_exists, in_subquery, not_in_subquery
using SQLSketch.Core: from, where, select

@testset "Expression AST" begin
    @testset "Column References" begin
        # Basic construction
        c = col(:users, :email)
        @test c isa ColRef
        @test c.table == :users
        @test c.column == :email

        # Direct construction
        c2 = ColRef(:posts, :title)
        @test c2 isa ColRef
        @test c2.table == :posts
        @test c2.column == :title

        # Immutability
        @test c isa SQLExpr
    end

    @testset "Literals" begin
        # Integer literal
        l1 = literal(42)
        @test l1 isa Literal
        @test l1.value == 42

        # String literal
        l2 = literal("hello")
        @test l2 isa Literal
        @test l2.value == "hello"

        # Boolean literal
        l3 = literal(true)
        @test l3 isa Literal
        @test l3.value == true

        # Float literal
        l4 = literal(3.14)
        @test l4 isa Literal
        @test l4.value == 3.14

        # Nothing/null literal
        l5 = literal(nothing)
        @test l5 isa Literal
        @test l5.value === nothing

        # Type check
        @test l1 isa SQLExpr
    end

    @testset "Parameters" begin
        # Basic construction
        p1 = param(String, :email)
        @test p1 isa Param
        @test p1.type == String
        @test p1.name == :email

        # Different types
        p2 = param(Int, :user_id)
        @test p2.type == Int
        @test p2.name == :user_id

        p3 = param(Bool, :active)
        @test p3.type == Bool
        @test p3.name == :active

        # Direct construction
        p4 = Param(Float64, :price)
        @test p4 isa Param
        @test p4.type == Float64

        # Type check
        @test p1 isa SQLExpr
    end

    @testset "Binary Operators - Comparison" begin
        c = col(:users, :age)

        # Expr == Expr
        expr1 = col(:users, :id) == col(:posts, :user_id)
        @test expr1 isa BinaryOp
        @test expr1.op == :(=)
        @test expr1.left isa ColRef
        @test expr1.right isa ColRef

        # Expr == literal (auto-wrap)
        expr2 = c == 18
        @test expr2 isa BinaryOp
        @test expr2.op == :(=)
        @test expr2.left isa ColRef
        @test expr2.right isa Literal
        @test expr2.right.value == 18

        # literal == Expr (auto-wrap)
        expr3 = 18 == c
        @test expr3 isa BinaryOp
        @test expr3.op == :(=)
        @test expr3.left isa Literal
        @test expr3.right isa ColRef

        # Not equal
        expr4 = c != 21
        @test expr4 isa BinaryOp
        @test expr4.op == :!=

        # Less than
        expr5 = c < 30
        @test expr5 isa BinaryOp
        @test expr5.op == :<

        # Greater than
        expr6 = c > 10
        @test expr6 isa BinaryOp
        @test expr6.op == :>

        # Less than or equal
        expr7 = c <= 25
        @test expr7 isa BinaryOp
        @test expr7.op == :<=

        # Greater than or equal
        expr8 = c >= 18
        @test expr8 isa BinaryOp
        @test expr8.op == :>=
    end

    @testset "Binary Operators - Logical" begin
        c1 = col(:users, :active)
        c2 = col(:users, :verified)

        # AND operator (&)
        expr1 = c1 & c2
        @test expr1 isa BinaryOp
        @test expr1.op == :AND
        @test expr1.left isa ColRef
        @test expr1.right isa ColRef

        # OR operator (|)
        expr2 = c1 | c2
        @test expr2 isa BinaryOp
        @test expr2.op == :OR

        # Chained logical operators
        c3 = col(:users, :admin)
        expr3 = c1 & c2 & c3
        @test expr3 isa BinaryOp
        @test expr3.op == :AND
        @test expr3.left isa BinaryOp
        @test expr3.right isa ColRef
    end

    @testset "Binary Operators - Arithmetic" begin
        c1 = col(:products, :price)
        c2 = col(:products, :discount)

        # Addition
        expr1 = c1 + c2
        @test expr1 isa BinaryOp
        @test expr1.op == :+

        # Subtraction
        expr2 = c1 - c2
        @test expr2 isa BinaryOp
        @test expr2.op == :-

        # Multiplication
        expr3 = c1 * literal(1.1)
        @test expr3 isa BinaryOp
        @test expr3.op == :*

        # Division
        expr4 = c1 / literal(2)
        @test expr4 isa BinaryOp
        @test expr4.op == :/
    end

    @testset "Unary Operators" begin
        c = col(:users, :active)

        # NOT operator (!)
        expr1 = !c
        @test expr1 isa UnaryOp
        @test expr1.op == :NOT
        @test expr1.expr isa ColRef

        # IS NULL
        expr2 = is_null(col(:users, :deleted_at))
        @test expr2 isa UnaryOp
        @test expr2.op == :IS_NULL
        @test expr2.expr isa ColRef

        # IS NOT NULL
        expr3 = is_not_null(col(:users, :email))
        @test expr3 isa UnaryOp
        @test expr3.op == :IS_NOT_NULL
        @test expr3.expr isa ColRef

        # Nested NOT
        expr4 = !(!c)
        @test expr4 isa UnaryOp
        @test expr4.expr isa UnaryOp
    end

    @testset "Function Calls" begin
        # COUNT function
        expr1 = func(:COUNT, [col(:users, :id)])
        @test expr1 isa FuncCall
        @test expr1.name == :COUNT
        @test length(expr1.args) == 1
        @test expr1.args[1] isa ColRef

        # LOWER function
        expr2 = func(:LOWER, [col(:users, :email)])
        @test expr2 isa FuncCall
        @test expr2.name == :LOWER
        @test length(expr2.args) == 1

        # Multi-argument function (COALESCE)
        expr3 = func(:COALESCE, [col(:users, :name), literal("Anonymous")])
        @test expr3 isa FuncCall
        @test expr3.name == :COALESCE
        @test length(expr3.args) == 2
        @test expr3.args[1] isa ColRef
        @test expr3.args[2] isa Literal

        # No-argument function
        expr4 = func(:NOW, SQLExpr[])
        @test expr4 isa FuncCall
        @test expr4.name == :NOW
        @test length(expr4.args) == 0

        # Direct construction
        expr5 = FuncCall(:MAX, [col(:orders, :total)])
        @test expr5 isa FuncCall
        @test expr5 isa SQLExpr
    end

    @testset "Expression Composition" begin
        # Complex WHERE clause: age > 18 AND active = true
        expr1 = (col(:users, :age) > 18) & (col(:users, :active) == true)
        @test expr1 isa BinaryOp
        @test expr1.op == :AND
        @test expr1.left isa BinaryOp
        @test expr1.left.op == :>
        @test expr1.right isa BinaryOp
        @test expr1.right.op == :(=)

        # Multiple conditions with precedence
        # (active = true) AND (age >= 18) AND (verified = true)
        expr2 = (col(:users, :active) == true) &
                (col(:users, :age) >= 18) &
                (col(:users, :verified) == true)
        @test expr2 isa BinaryOp
        @test expr2.op == :AND

        # Mixed operators: (age > 18 OR admin = true) AND active = true
        expr3 = ((col(:users, :age) > 18) | (col(:users, :admin) == true)) &
                (col(:users, :active) == true)
        @test expr3 isa BinaryOp
        @test expr3.op == :AND
        @test expr3.left isa BinaryOp
        @test expr3.left.op == :OR

        # Arithmetic in comparison: price * 1.1 > 100
        expr4 = col(:products, :price) * 1.1 > 100
        @test expr4 isa BinaryOp
        @test expr4.op == :>
        @test expr4.left isa BinaryOp
        @test expr4.left.op == :*

        # Function in comparison: LOWER(email) = param
        expr5 = func(:LOWER, [col(:users, :email)]) == param(String, :email)
        @test expr5 isa BinaryOp
        @test expr5.op == :(=)
        @test expr5.left isa FuncCall
        @test expr5.right isa Param

        # NOT with complex expression
        expr6 = !((col(:users, :active) == true) & (col(:users, :verified) == true))
        @test expr6 isa UnaryOp
        @test expr6.op == :NOT
        @test expr6.expr isa BinaryOp
    end

    @testset "Type Hierarchy" begin
        # All expression types should be subtypes of Expr
        @test ColRef <: SQLExpr
        @test Literal <: SQLExpr
        @test Param <: SQLExpr
        @test BinaryOp <: SQLExpr
        @test UnaryOp <: SQLExpr
        @test FuncCall <: SQLExpr

        # Test abstract type
        @test isabstracttype(SQLExpr)
        @test !isabstracttype(ColRef)
        @test !isabstracttype(Literal)
    end

    @testset "Immutability" begin
        # All expression types should be immutable structs
        c = col(:users, :id)
        @test !ismutable(c)

        l = literal(42)
        @test !ismutable(l)

        p = param(String, :email)
        @test !ismutable(p)

        b = col(:users, :age) > 18
        @test !ismutable(b)

        u = !col(:users, :active)
        @test !ismutable(u)

        f = func(:COUNT, [col(:users, :id)])
        @test !ismutable(f)
    end

    @testset "LIKE/ILIKE Operators" begin
        # LIKE operator
        expr = like(col(:users, :email), literal("%@gmail.com"))
        @test expr isa BinaryOp
        @test expr.op == :LIKE
        @test isequal(expr.left, col(:users, :email))
        @test isequal(expr.right, literal("%@gmail.com"))

        # Auto-wrapping with literal
        expr2 = like(col(:users, :name), "Alice%")
        @test expr2 isa BinaryOp
        @test expr2.op == :LIKE
        @test isequal(expr2.right, literal("Alice%"))

        # NOT LIKE operator
        expr3 = not_like(col(:users, :email), literal("%@spam.com"))
        @test expr3 isa BinaryOp
        @test expr3.op == :NOT_LIKE

        # ILIKE operator (case-insensitive)
        expr4 = ilike(col(:users, :email), "%@GMAIL.COM")
        @test expr4 isa BinaryOp
        @test expr4.op == :ILIKE

        # NOT ILIKE operator
        expr5 = not_ilike(col(:users, :email), "%@SPAM.COM")
        @test expr5 isa BinaryOp
        @test expr5.op == :NOT_ILIKE

        # Hash and equality
        expr_a = like(col(:users, :email), "%@gmail.com")
        expr_b = like(col(:users, :email), "%@gmail.com")
        @test hash(expr_a) == hash(expr_b)
        @test isequal(expr_a, expr_b)
    end

    @testset "BETWEEN Operator" begin
        # Basic BETWEEN construction
        expr = between(col(:users, :age), literal(18), literal(65))
        @test expr isa BetweenOp
        @test isequal(expr.expr, col(:users, :age))
        @test isequal(expr.low, literal(18))
        @test isequal(expr.high, literal(65))
        @test expr.negated == false

        # Auto-wrapping with literals
        expr2 = between(col(:products, :price), 10.0, 100.0)
        @test expr2 isa BetweenOp
        @test isequal(expr2.low, literal(10.0))
        @test isequal(expr2.high, literal(100.0))

        # NOT BETWEEN
        expr3 = not_between(col(:users, :age), 0, 17)
        @test expr3 isa BetweenOp
        @test expr3.negated == true

        # With parameters
        expr4 = between(col(:products, :price), param(Float64, :min), param(Float64, :max))
        @test expr4 isa BetweenOp
        @test expr4.low isa Param
        @test expr4.high isa Param

        # Hash and equality
        expr_a = between(col(:users, :age), 18, 65)
        expr_b = between(col(:users, :age), 18, 65)
        @test hash(expr_a) == hash(expr_b)
        @test isequal(expr_a, expr_b)

        # Different values should not be equal
        expr_c = between(col(:users, :age), 20, 70)
        @test !isequal(expr_a, expr_c)

        # Negated vs non-negated should not be equal
        expr_d = not_between(col(:users, :age), 18, 65)
        @test !isequal(expr_a, expr_d)

        # Immutability
        @test !ismutable(expr)
    end

    @testset "IN Operator" begin
        # Basic IN construction with SQLExpr values
        expr = in_list(col(:users, :status), [literal("active"), literal("pending")])
        @test expr isa InOp
        @test isequal(expr.expr, col(:users, :status))
        @test length(expr.values) == 2
        @test expr.values[1] isa Literal
        @test expr.values[1].value === "active"
        @test expr.values[2] isa Literal
        @test expr.values[2].value === "pending"
        @test expr.negated === false

        # Auto-wrapping with literal values (strings)
        expr2 = in_list(col(:users, :role), ["admin", "moderator", "user"])
        @test expr2 isa InOp
        @test length(expr2.values) == 3
        @test expr2.values[1].value === "admin"
        @test expr2.values[2].value === "moderator"
        @test expr2.values[3].value === "user"

        # Auto-wrapping with literal values (integers)
        expr3 = in_list(col(:users, :id), [1, 2, 3, 4, 5])
        @test expr3 isa InOp
        @test length(expr3.values) == 5
        @test expr3.values[1].value === 1
        @test expr3.values[5].value === 5

        # NOT IN
        expr4 = not_in_list(col(:users, :status), ["banned", "deleted"])
        @test expr4 isa InOp
        @test expr4.negated == true
        @test length(expr4.values) == 2

        # With parameters
        expr5 = in_list(col(:users, :id), [param(Int, :id1), param(Int, :id2)])
        @test expr5 isa InOp
        @test expr5.values[1] isa Param
        @test expr5.values[2] isa Param

        # Empty list (edge case)
        expr6 = in_list(col(:users, :id), SQLExpr[])
        @test expr6 isa InOp
        @test length(expr6.values) == 0

        # Single value
        expr7 = in_list(col(:users, :status), ["active"])
        @test expr7 isa InOp
        @test length(expr7.values) == 1

        # Hash and equality
        expr_a = in_list(col(:users, :status), ["active", "pending"])
        expr_b = in_list(col(:users, :status), ["active", "pending"])
        @test hash(expr_a) == hash(expr_b)
        @test isequal(expr_a, expr_b)

        # Different values should not be equal
        expr_c = in_list(col(:users, :status), ["active", "banned"])
        @test !isequal(expr_a, expr_c)

        # Negated vs non-negated should not be equal
        expr_d = not_in_list(col(:users, :status), ["active", "pending"])
        @test !isequal(expr_a, expr_d)

        # Immutability
        @test !ismutable(expr)

        # Type check
        @test expr isa SQLExpr
    end

    @testset "CAST Expressions" begin
        # Basic cast
        expr = cast(col(:users, :age), :TEXT)
        @test expr isa Cast
        @test expr.expr isa ColRef
        @test expr.target_type == :TEXT

        # Cast literal
        expr2 = cast(literal("42"), :INTEGER)
        @test expr2 isa Cast
        @test expr2.expr isa Literal
        @test expr2.target_type == :INTEGER

        # Cast parameter
        expr3 = cast(param(String, :value), :REAL)
        @test expr3 isa Cast
        @test expr3.expr isa Param
        @test expr3.target_type == :REAL

        # Cast complex expression
        expr4 = cast(col(:users, :id) + literal(1), :TEXT)
        @test expr4 isa Cast
        @test expr4.expr isa BinaryOp

        # Hash and equality
        expr_a = cast(col(:users, :age), :TEXT)
        expr_b = cast(col(:users, :age), :TEXT)
        @test hash(expr_a) == hash(expr_b)
        @test isequal(expr_a, expr_b)

        # Different target types should not be equal
        expr_c = cast(col(:users, :age), :INTEGER)
        @test !isequal(expr_a, expr_c)

        # Different expressions should not be equal
        expr_d = cast(col(:users, :id), :TEXT)
        @test !isequal(expr_a, expr_d)

        # Immutability
        @test !ismutable(expr)

        # Type check
        @test expr isa SQLExpr
    end

    @testset "Subquery Expressions" begin
        # Basic subquery
        q = from(:orders) |> select(NamedTuple, col(:orders, :user_id))
        sq = subquery(q)
        @test sq isa Subquery
        @test sq.query == q

        # EXISTS
        sq2 = subquery(from(:orders) |> where(col(:orders, :user_id) == col(:users, :id)))
        expr = exists(sq2)
        @test expr isa UnaryOp
        @test expr.op == :EXISTS
        @test expr.expr isa Subquery

        # NOT EXISTS
        expr2 = not_exists(sq2)
        @test expr2 isa UnaryOp
        @test expr2.op == :NOT_EXISTS
        @test expr2.expr isa Subquery

        # IN subquery
        sq3 = subquery(from(:orders) |>
                      where(col(:orders, :status) == literal("pending")) |>
                      select(NamedTuple, col(:orders, :user_id)))
        expr3 = in_subquery(col(:users, :id), sq3)
        @test expr3 isa BinaryOp
        @test expr3.op == :IN
        @test expr3.left isa ColRef
        @test expr3.right isa Subquery

        # NOT IN subquery
        expr4 = not_in_subquery(col(:users, :id), sq3)
        @test expr4 isa BinaryOp
        @test expr4.op == :NOT_IN
        @test expr4.left isa ColRef
        @test expr4.right isa Subquery

        # Hash and equality
        q1 = from(:orders) |> select(NamedTuple, col(:orders, :user_id))
        q2 = from(:orders) |> select(NamedTuple, col(:orders, :user_id))
        sq_a = subquery(q1)
        sq_b = subquery(q2)
        @test hash(sq_a) == hash(sq_b)
        @test isequal(sq_a, sq_b)

        # Different queries should not be equal
        q3 = from(:users) |> select(NamedTuple, col(:users, :id))
        sq_c = subquery(q3)
        @test !isequal(sq_a, sq_c)

        # Immutability
        @test !ismutable(sq)

        # Type check
        @test sq isa SQLExpr
    end
end
