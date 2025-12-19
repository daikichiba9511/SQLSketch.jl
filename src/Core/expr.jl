"""
# Expression AST

This module defines the expression abstract syntax tree (AST) for SQLSketch.

Expressions represent SQL conditions, column references, literals, parameters,
and operations in a structured, inspectable way.

## Design Principles

- Expressions are **not strings** – they are typed, structured values
- Expressions can be inspected, transformed, and compiled in a dialect-aware manner
- Both explicit construction and placeholder-based construction are supported
- All expression nodes are immutable

## Core Expression Types

- `ColRef` – column references (e.g., `users.id`)
- `Literal` – literal values (e.g., `42`, `"hello"`)
- `Param` – bound parameters (e.g., `:email`)
- `BinaryOp` – binary operators (e.g., `=`, `<`, `AND`, `OR`)
- `UnaryOp` – unary operators (e.g., `NOT`, `IS NULL`)
- `FuncCall` – function calls (e.g., `COUNT(*)`, `LOWER(email)`)

## Usage

```julia
# Explicit construction
expr = col(:users, :email) == param(String, :email)

# With placeholders (future)
expr = _.email == param(String, :email)
```

See `docs/design.md` Section 8 for detailed design rationale.
"""

# Expression base type
"""
Abstract base type for all SQL expressions.

All expression subtypes must be immutable and inspectable.
"""
abstract type Expr end

# Column reference
"""
    ColRef(table::Symbol, column::Symbol)

Represents a column reference in SQL (e.g., `users.id`).

# Fields
- `table::Symbol` – table name or alias
- `column::Symbol` – column name

# Example
```julia
col(:users, :email)  # → users.email
```
"""
struct ColRef <: Expr
    table::Symbol
    column::Symbol
end

"""
    col(table::Symbol, column::Symbol) -> ColRef

Convenience constructor for column references.
"""
col(table::Symbol, column::Symbol)::ColRef = ColRef(table, column)

# Literal value
"""
    Literal(value::Any)

Represents a literal value in SQL (e.g., `42`, `"hello"`, `true`).

Literals are directly embedded in the generated SQL.

# Example
```julia
literal(42)      # → 42
literal("test")  # → 'test'
literal(true)    # → TRUE or 1 (dialect-dependent)
```
"""
struct Literal <: Expr
    value::Any
end

"""
    literal(value::Any) -> Literal

Convenience constructor for literal values.
Accepts any Julia value to be embedded as a literal in SQL.
"""
literal(value::Any)::Literal = Literal(value)

# Parameter (bound value)
"""
    Param(type::Type, name::Symbol)

Represents a bound parameter in SQL (e.g., `?`, `\$1`).

Parameters are passed separately during query execution and are properly
escaped by the database driver.

# Fields
- `type::Type` – expected Julia type of the parameter
- `name::Symbol` – parameter name for identification

# Example
```julia
param(String, :email)  # → ? or \$1 (dialect-dependent)
param(Int, :user_id)
```
"""
struct Param <: Expr
    type::Type
    name::Symbol
end

"""
    param(T::Type, name::Symbol) -> Param

Convenience constructor for bound parameters.
"""
param(T::Type, name::Symbol)::Param = Param(T, name)

# Binary operator
"""
    BinaryOp(op::Symbol, left::Expr, right::Expr)

Represents a binary operation in SQL (e.g., `=`, `<`, `AND`, `OR`).

# Fields
- `op::Symbol` – operator symbol (`:=`, `:<`, `:AND`, `:OR`, etc.)
- `left::Expr` – left-hand expression
- `right::Expr` – right-hand expression

# Supported Operators
- Comparison: `=`, `!=`, `<`, `>`, `<=`, `>=`
- Logical: `AND`, `OR`
- Arithmetic: `+`, `-`, `*`, `/`
- String: `LIKE`, `ILIKE`
- Membership: `IN`

# Example
```julia
col(:users, :age) > literal(18)
# → BinaryOp(:>, ColRef(:users, :age), Literal(18))

col(:users, :active) == literal(true) & col(:users, :verified) == literal(true)
# → BinaryOp(:AND, BinaryOp(:=, ...), BinaryOp(:=, ...))
```
"""
struct BinaryOp <: Expr
    op::Symbol
    left::Expr
    right::Expr
end

# Unary operator
"""
    UnaryOp(op::Symbol, expr::Expr)

Represents a unary operation in SQL (e.g., `NOT`, `IS NULL`).

# Fields
- `op::Symbol` – operator symbol (`:NOT`, `:IS_NULL`, `:IS_NOT_NULL`)
- `expr::Expr` – operand expression

# Example
```julia
is_null(col(:users, :deleted_at))
# → UnaryOp(:IS_NULL, ColRef(:users, :deleted_at))

!col(:users, :active)
# → UnaryOp(:NOT, ColRef(:users, :active))
```
"""
struct UnaryOp <: Expr
    op::Symbol
    expr::Expr
end

# Function call
"""
    FuncCall(name::Symbol, args::Vector{Expr})

Represents a SQL function call (e.g., `COUNT(*)`, `LOWER(email)`).

# Fields
- `name::Symbol` – function name
- `args::Vector{Expr}` – function arguments

# Example
```julia
func(:COUNT, [col(:users, :id)])
# → COUNT(users.id)

func(:LOWER, [col(:users, :email)])
# → LOWER(users.email)
```
"""
struct FuncCall <: Expr
    name::Symbol
    args::Vector{Expr}
end

"""
    func(name::Symbol, args::Vector) -> FuncCall

Convenience constructor for function calls.
Accepts any vector of Expr subtypes and converts to Vector{Expr}.
"""
func(name::Symbol, args::Vector)::FuncCall = FuncCall(name, convert(Vector{Expr}, args))

# Operator overloading for ergonomic expression construction
# These allow natural Julia syntax to build expression ASTs

# Comparison operators
Base.:(==)(left::Expr, right::Expr) = BinaryOp(:(=), left, right)
Base.:(!=)(left::Expr, right::Expr) = BinaryOp(:!=, left, right)
Base.:(<)(left::Expr, right::Expr) = BinaryOp(:<, left, right)
Base.:(>)(left::Expr, right::Expr) = BinaryOp(:>, left, right)
Base.:(<=)(left::Expr, right::Expr) = BinaryOp(:<=, left, right)
Base.:(>=)(left::Expr, right::Expr) = BinaryOp(:>=, left, right)

# Auto-wrap literals when mixing Expr with Julia values
Base.:(==)(left::Expr, right) = left == literal(right)
Base.:(==)(left, right::Expr) = literal(left) == right
Base.:(!=)(left::Expr, right) = left != literal(right)
Base.:(!=)(left, right::Expr) = literal(left) != right
Base.:(<)(left::Expr, right) = left < literal(right)
Base.:(<)(left, right::Expr) = literal(left) < right
Base.:(>)(left::Expr, right) = left > literal(right)
Base.:(>)(left, right::Expr) = literal(left) > right
Base.:(<=)(left::Expr, right) = left <= literal(right)
Base.:(<=)(left, right::Expr) = literal(left) <= right
Base.:(>=)(left::Expr, right) = left >= literal(right)
Base.:(>=)(left, right::Expr) = literal(left) >= right

# Logical operators (use & and | to avoid short-circuit evaluation)
Base.:(&)(left::Expr, right::Expr) = BinaryOp(:AND, left, right)
Base.:(|)(left::Expr, right::Expr) = BinaryOp(:OR, left, right)
Base.:(!)(expr::Expr) = UnaryOp(:NOT, expr)

# Arithmetic operators
Base.:(+)(left::Expr, right::Expr) = BinaryOp(:+, left, right)
Base.:(-)(left::Expr, right::Expr) = BinaryOp(:-, left, right)
Base.:(*)(left::Expr, right::Expr) = BinaryOp(:*, left, right)
Base.:(/)(left::Expr, right::Expr) = BinaryOp(:/, left, right)

# Auto-wrap literals for arithmetic
Base.:(+)(left::Expr, right) = left + literal(right)
Base.:(+)(left, right::Expr) = literal(left) + right
Base.:(-)(left::Expr, right) = left - literal(right)
Base.:(-)(left, right::Expr) = literal(left) - right
Base.:(*)(left::Expr, right) = left * literal(right)
Base.:(*)(left, right::Expr) = literal(left) * right
Base.:(/)(left::Expr, right) = left / literal(right)
Base.:(/)(left, right::Expr) = literal(left) / right

# Null checking helpers
"""
    is_null(expr::Expr) -> UnaryOp

Check if an expression is NULL.

# Example
```julia
is_null(col(:users, :deleted_at))
# → WHERE users.deleted_at IS NULL
```
"""
is_null(expr::Expr)::UnaryOp = UnaryOp(:IS_NULL, expr)

"""
    is_not_null(expr::Expr) -> UnaryOp

Check if an expression is NOT NULL.

# Example
```julia
is_not_null(col(:users, :email))
# → WHERE users.email IS NOT NULL
```
"""
is_not_null(expr::Expr)::UnaryOp = UnaryOp(:IS_NOT_NULL, expr)

# TODO: Add support for:
# - IN operator (expr in [values...])
# - BETWEEN operator
# - LIKE operator
# - Subquery expressions
# - CASE expressions
# - Type casting

# TODO (Phase 2): Placeholder support
# struct Placeholder end
# const _ = Placeholder()
# Base.getproperty(::Placeholder, name::Symbol) = PlaceholderField(name)
