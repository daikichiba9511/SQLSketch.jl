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
using SQLSketch.Core: SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall
using SQLSketch.Core: col, literal, param, func, is_null, is_not_null

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
end
