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
abstract type SQLExpr end

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
struct ColRef <: SQLExpr
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
struct Literal <: SQLExpr
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
struct Param <: SQLExpr
    type::Type
    name::Symbol
end

"""
    param(T::Type, name::Symbol) -> Param

Convenience constructor for bound parameters.
"""
param(T::Type, name::Symbol)::Param = Param(T, name)

# Placeholder (syntactic sugar)
"""
    PlaceholderField(column::Symbol)

Represents a placeholder field reference (e.g., `p_.email`).

This is syntactic sugar that gets resolved to a `ColRef` during query compilation.
The table name is inferred from the query context.

# Fields

  - `column::Symbol` – column name

# Example

```julia
where(p_.email == param(String, :email))
# Resolves to: where(col(:users, :email) == param(String, :email))
# (assuming FROM users context)
```

# Notes

Placeholders are **optional syntactic sugar**. The Core layer always accepts
explicit `ColRef` expressions. Placeholders simplify single-table queries but
may be ambiguous in multi-table JOINs.

See `docs/design.md` Section 9 for design rationale.
"""
struct PlaceholderField <: SQLExpr
    column::Symbol
end

"""
    Placeholder

Placeholder type for syntactic sugar. Use via the exported constant `p_`.

# Example

```julia
# Instead of:
where(col(:users, :email) == param(String, :email))

# You can write:
where(p_.email == param(String, :email))
```

The table name is automatically inferred from the query context.

Note: Uses `p_` because Julia reserves underscore-only identifiers
for write-only variables.
"""
struct Placeholder end

"""
    const p_ = Placeholder()

Global placeholder constant for convenient field access.

Note: Uses `p_` instead of `_` because Julia reserves underscore-only
identifiers for write-only variables.

# Usage

```julia
from(:users) |>
    where(p_.age > literal(18)) |>
    select(NamedTuple, p_.id, p_.email)
```

Internally, `p_.column` creates a `PlaceholderField(:column)` which is resolved
to `ColRef(table, :column)` during query compilation.
"""
const p_ = Placeholder()

"""
    Base.getproperty(::Placeholder, name::Symbol) -> PlaceholderField

Enables `_.column` syntax for placeholder field access.
"""
Base.getproperty(::Placeholder, name::Symbol)::PlaceholderField = PlaceholderField(name)

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
struct BinaryOp <: SQLExpr
    op::Symbol
    left::SQLExpr
    right::SQLExpr
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
struct UnaryOp <: SQLExpr
    op::Symbol
    expr::SQLExpr
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
struct FuncCall <: SQLExpr
    name::Symbol
    args::Vector{SQLExpr}
end

"""
    func(name::Symbol, args::Vector) -> FuncCall

Convenience constructor for function calls.
Accepts any vector of Expr subtypes and converts to Vector{Expr}.
"""
func(name::Symbol, args::Vector)::FuncCall = FuncCall(name, convert(Vector{SQLExpr}, args))

# BETWEEN operator
"""
    BetweenOp(expr::SQLExpr, low::SQLExpr, high::SQLExpr, negated::Bool)

Represents a BETWEEN or NOT BETWEEN operation in SQL.

# Fields

  - `expr::SQLExpr` – expression to test
  - `low::SQLExpr` – lower bound (inclusive)
  - `high::SQLExpr` – upper bound (inclusive)
  - `negated::Bool` – true for NOT BETWEEN, false for BETWEEN

# Example

```julia
between(col(:users, :age), literal(18), literal(65))
# → age BETWEEN 18 AND 65

not_between(col(:products, :price), param(Float64, :min), param(Float64, :max))
# → price NOT BETWEEN ? AND ?
```
"""
struct BetweenOp <: SQLExpr
    expr::SQLExpr
    low::SQLExpr
    high::SQLExpr
    negated::Bool
end

# IN operator
"""
    InOp(expr::SQLExpr, values::Vector{SQLExpr}, negated::Bool)

Represents an IN or NOT IN operation in SQL.

# Fields

  - `expr::SQLExpr` – expression to test
  - `values::Vector{SQLExpr}` – list of values to match against
  - `negated::Bool` – true for NOT IN, false for IN

# Example

```julia
in_list(col(:users, :status), [literal("active"), literal("pending")])
# → status IN ('active', 'pending')

not_in_list(col(:users, :id), [literal(1), literal(2), literal(3)])
# → id NOT IN (1, 2, 3)
```

# Note

Currently supports literal values and parameters. Subquery support is deferred to Phase 2 future.
"""
struct InOp <: SQLExpr
    expr::SQLExpr
    values::Vector{SQLExpr}
    negated::Bool
end

# Operator overloading for ergonomic expression construction
# These allow natural Julia syntax to build expression ASTs

# Comparison operators
Base.:(==)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:(=), left, right)
Base.:(!=)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:!=, left, right)
Base.:(<)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:<, left, right)
Base.:(>)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:>, left, right)
Base.:(<=)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:<=, left, right)
Base.:(>=)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:>=, left, right)

# Auto-wrap literals when mixing Expr with Julia values
Base.:(==)(left::SQLExpr, right)::BinaryOp = left == literal(right)
Base.:(==)(left, right::SQLExpr)::BinaryOp = literal(left) == right
Base.:(!=)(left::SQLExpr, right)::BinaryOp = left != literal(right)
Base.:(!=)(left, right::SQLExpr)::BinaryOp = literal(left) != right
Base.:(<)(left::SQLExpr, right)::BinaryOp = left < literal(right)
Base.:(<)(left, right::SQLExpr)::BinaryOp = literal(left) < right
Base.:(>)(left::SQLExpr, right)::BinaryOp = left > literal(right)
Base.:(>)(left, right::SQLExpr)::BinaryOp = literal(left) > right
Base.:(<=)(left::SQLExpr, right)::BinaryOp = left <= literal(right)
Base.:(<=)(left, right::SQLExpr)::BinaryOp = literal(left) <= right
Base.:(>=)(left::SQLExpr, right)::BinaryOp = left >= literal(right)
Base.:(>=)(left, right::SQLExpr)::BinaryOp = literal(left) >= right

# Logical operators (use & and | to avoid short-circuit evaluation)
Base.:(&)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:AND, left, right)
Base.:(|)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:OR, left, right)
Base.:(!)(expr::SQLExpr)::UnaryOp = UnaryOp(:NOT, expr)

# Arithmetic operators
Base.:(+)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:+, left, right)
Base.:(-)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:-, left, right)
Base.:(*)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:*, left, right)
Base.:(/)(left::SQLExpr, right::SQLExpr)::BinaryOp = BinaryOp(:/, left, right)

# Auto-wrap literals for arithmetic
Base.:(+)(left::SQLExpr, right)::BinaryOp = left + literal(right)
Base.:(+)(left, right::SQLExpr)::BinaryOp = literal(left) + right
Base.:(-)(left::SQLExpr, right)::BinaryOp = left - literal(right)
Base.:(-)(left, right::SQLExpr)::BinaryOp = literal(left) - right
Base.:(*)(left::SQLExpr, right)::BinaryOp = left * literal(right)
Base.:(*)(left, right::SQLExpr)::BinaryOp = literal(left) * right
Base.:(/)(left::SQLExpr, right)::BinaryOp = left / literal(right)
Base.:(/)(left, right::SQLExpr)::BinaryOp = literal(left) / right

# Null checking helpers
"""
    is_null(expr::SQLExpr) -> UnaryOp

Check if an expression is NULL.

# Example

```julia
is_null(col(:users, :deleted_at))
# → WHERE users.deleted_at IS NULL
```
"""
is_null(expr::SQLExpr)::UnaryOp = UnaryOp(:IS_NULL, expr)

"""
    is_not_null(expr::SQLExpr) -> UnaryOp

Check if an expression is NOT NULL.

# Example

```julia
is_not_null(col(:users, :email))
# → WHERE users.email IS NOT NULL
```
"""
is_not_null(expr::SQLExpr)::UnaryOp = UnaryOp(:IS_NOT_NULL, expr)

# Pattern matching operators (LIKE/ILIKE)
"""
    like(expr::SQLExpr, pattern::SQLExpr) -> BinaryOp

Pattern matching with LIKE operator.

Supports SQL wildcards:
- `%` matches any sequence of characters
- `_` matches any single character

# Example

```julia
like(col(:users, :email), literal("%@gmail.com"))
# → WHERE users.email LIKE '%@gmail.com'
```
"""
like(expr::SQLExpr, pattern::SQLExpr)::BinaryOp = BinaryOp(:LIKE, expr, pattern)
like(expr::SQLExpr, pattern)::BinaryOp = BinaryOp(:LIKE, expr, literal(pattern))

"""
    not_like(expr::SQLExpr, pattern::SQLExpr) -> BinaryOp

Negated pattern matching with NOT LIKE operator.

# Example

```julia
not_like(col(:users, :email), literal("%@spam.com"))
# → WHERE users.email NOT LIKE '%@spam.com'
```
"""
not_like(expr::SQLExpr, pattern::SQLExpr)::BinaryOp = BinaryOp(:NOT_LIKE, expr, pattern)
not_like(expr::SQLExpr, pattern)::BinaryOp = BinaryOp(:NOT_LIKE, expr, literal(pattern))

"""
    ilike(expr::SQLExpr, pattern::SQLExpr) -> BinaryOp

Case-insensitive pattern matching with ILIKE operator (PostgreSQL).

Note: SQLite will emulate this with UPPER() if needed.

# Example

```julia
ilike(col(:users, :email), literal("%@GMAIL.COM"))
# → WHERE users.email ILIKE '%@GMAIL.COM'
```
"""
ilike(expr::SQLExpr, pattern::SQLExpr)::BinaryOp = BinaryOp(:ILIKE, expr, pattern)
ilike(expr::SQLExpr, pattern)::BinaryOp = BinaryOp(:ILIKE, expr, literal(pattern))

"""
    not_ilike(expr::SQLExpr, pattern::SQLExpr) -> BinaryOp

Negated case-insensitive pattern matching with NOT ILIKE operator (PostgreSQL).

# Example

```julia
not_ilike(col(:users, :email), literal("%@SPAM.COM"))
# → WHERE users.email NOT ILIKE '%@SPAM.COM'
```
"""
not_ilike(expr::SQLExpr, pattern::SQLExpr)::BinaryOp = BinaryOp(:NOT_ILIKE, expr, pattern)
not_ilike(expr::SQLExpr, pattern)::BinaryOp = BinaryOp(:NOT_ILIKE, expr, literal(pattern))

# Range operators (BETWEEN)
"""
    between(expr::SQLExpr, low::SQLExpr, high::SQLExpr) -> BetweenOp

Test if an expression is between two values (inclusive).

# Example

```julia
between(col(:users, :age), literal(18), literal(65))
# → WHERE users.age BETWEEN 18 AND 65

between(col(:products, :price), param(Float64, :min), param(Float64, :max))
# → WHERE products.price BETWEEN ? AND ?
```
"""
between(expr::SQLExpr, low::SQLExpr, high::SQLExpr)::BetweenOp =
    BetweenOp(expr, low, high, false)

# Auto-wrapping for literals
between(expr::SQLExpr, low, high)::BetweenOp =
    BetweenOp(expr, literal(low), literal(high), false)

"""
    not_between(expr::SQLExpr, low::SQLExpr, high::SQLExpr) -> BetweenOp

Test if an expression is NOT between two values.

# Example

```julia
not_between(col(:users, :age), literal(0), literal(17))
# → WHERE users.age NOT BETWEEN 0 AND 17
```
"""
not_between(expr::SQLExpr, low::SQLExpr, high::SQLExpr)::BetweenOp =
    BetweenOp(expr, low, high, true)

# Auto-wrapping for literals
not_between(expr::SQLExpr, low, high)::BetweenOp =
    BetweenOp(expr, literal(low), literal(high), true)

# List membership operators (IN)
"""
    in_list(expr::SQLExpr, values::Vector{SQLExpr}) -> InOp

Test if an expression is in a list of values.

# Example

```julia
in_list(col(:users, :status), [literal("active"), literal("pending")])
# → WHERE users.status IN ('active', 'pending')

in_list(col(:users, :id), [param(Int, :id1), param(Int, :id2)])
# → WHERE users.id IN (?, ?)
```
"""
in_list(expr::SQLExpr, values::Vector{SQLExpr})::InOp = InOp(expr, values, false)

# Auto-wrapping for literal values
"""
    in_list(expr::SQLExpr, values::Vector) -> InOp

Test if an expression is in a list of values (with auto-wrapping).

# Example

```julia
in_list(col(:users, :status), ["active", "pending", "suspended"])
# → WHERE users.status IN ('active', 'pending', 'suspended')

in_list(col(:users, :id), [1, 2, 3, 4, 5])
# → WHERE users.id IN (1, 2, 3, 4, 5)
```
"""
function in_list(expr::SQLExpr, values::Vector)::InOp
    # Convert all values to SQLExpr, but preserve existing SQLExpr objects
    expr_values = SQLExpr[v isa SQLExpr ? v : literal(v) for v in values]
    return InOp(expr, expr_values, false)
end

"""
    not_in_list(expr::SQLExpr, values::Vector{SQLExpr}) -> InOp

Test if an expression is NOT in a list of values.

# Example

```julia
not_in_list(col(:users, :status), [literal("banned"), literal("deleted")])
# → WHERE users.status NOT IN ('banned', 'deleted')
```
"""
not_in_list(expr::SQLExpr, values::Vector{SQLExpr})::InOp = InOp(expr, values, true)

# Auto-wrapping for literal values
"""
    not_in_list(expr::SQLExpr, values::Vector) -> InOp

Test if an expression is NOT in a list of values (with auto-wrapping).

# Example

```julia
not_in_list(col(:users, :role), ["guest", "anonymous"])
# → WHERE users.role NOT IN ('guest', 'anonymous')
```
"""
function not_in_list(expr::SQLExpr, values::Vector)::InOp
    # Convert all values to SQLExpr, but preserve existing SQLExpr objects
    expr_values = SQLExpr[v isa SQLExpr ? v : literal(v) for v in values]
    return InOp(expr, expr_values, true)
end

# CAST expression
"""
    Cast(expr::SQLExpr, target_type::Symbol)

Represents a CAST expression in SQL (e.g., `CAST(column AS INTEGER)`).

Type casting converts an expression to a different SQL type.

# Fields

  - `expr::SQLExpr` – expression to cast
  - `target_type::Symbol` – target SQL type (`:INTEGER`, `:TEXT`, `:REAL`, `:BOOLEAN`, etc.)

# Example

```julia
cast(col(:users, :age), :TEXT)
# → CAST(users.age AS TEXT)

cast(literal("42"), :INTEGER)
# → CAST('42' AS INTEGER)
```

# Note

The available types depend on the SQL dialect:
- SQLite: INTEGER, TEXT, REAL, BLOB
- PostgreSQL: INTEGER, TEXT, REAL, BOOLEAN, TIMESTAMP, etc.
- MySQL: SIGNED, UNSIGNED, CHAR, DATE, DATETIME, etc.
"""
struct Cast <: SQLExpr
    expr::SQLExpr
    target_type::Symbol
end

"""
    cast(expr::SQLExpr, target_type::Symbol) -> Cast

Convenience constructor for type casting.

# Example

```julia
cast(col(:users, :age), :TEXT)
# → CAST(users.age AS TEXT)
```
"""
cast(expr::SQLExpr, target_type::Symbol)::Cast = Cast(expr, target_type)

# Subquery expression
"""
    Subquery(query)

Represents a subquery expression that can be used in SQL expressions.

Subqueries can be used in various contexts:
- `WHERE column IN (SELECT ...)` – membership test
- `WHERE EXISTS (SELECT ...)` – existence test
- `SELECT (SELECT ...) AS field` – scalar subquery
- `FROM (SELECT ...) AS alias` – derived table (future)

# Fields

  - `query` – the query to use as a subquery (any Query type)

# Example

```julia
# IN subquery
sq = subquery(from(:orders) |>
              where(col(:orders, :status) == literal("pending")) |>
              select(NamedTuple, col(:orders, :user_id)))

where(in_subquery(col(:users, :id), sq))
# → WHERE users.id IN (SELECT orders.user_id FROM orders WHERE orders.status = 'pending')

# EXISTS subquery
sq = subquery(from(:orders) |>
              where(col(:orders, :user_id) == col(:users, :id)))

where(exists(sq))
# → WHERE EXISTS (SELECT * FROM orders WHERE orders.user_id = users.id)
```

# Note

The query field is not typed as Query to avoid circular dependencies between expr.jl and query.jl.
"""
struct Subquery <: SQLExpr
    query::Any  # Will be a Query{T} at runtime
end

"""
    subquery(query) -> Subquery

Convenience constructor for subquery expressions.

# Example

```julia
sq = subquery(from(:orders) |> select(NamedTuple, col(:orders, :user_id)))
```
"""
subquery(query)::Subquery = Subquery(query)

"""
    exists(sq::Subquery) -> UnaryOp

Test if a subquery returns any rows.

# Example

```julia
sq = subquery(from(:orders) |>
              where(col(:orders, :user_id) == col(:users, :id)))

where(exists(sq))
# → WHERE EXISTS (SELECT * FROM orders WHERE orders.user_id = users.id)
```
"""
exists(sq::Subquery)::UnaryOp = UnaryOp(:EXISTS, sq)

"""
    not_exists(sq::Subquery) -> UnaryOp

Test if a subquery returns no rows.

# Example

```julia
sq = subquery(from(:orders) |>
              where(col(:orders, :user_id) == col(:users, :id)))

where(not_exists(sq))
# → WHERE NOT EXISTS (SELECT * FROM orders WHERE orders.user_id = users.id)
```
"""
not_exists(sq::Subquery)::UnaryOp = UnaryOp(:NOT_EXISTS, sq)

"""
    in_subquery(expr::SQLExpr, sq::Subquery) -> BinaryOp

Test if an expression is in the result set of a subquery.

# Example

```julia
sq = subquery(from(:orders) |>
              where(col(:orders, :status) == literal("pending")) |>
              select(NamedTuple, col(:orders, :user_id)))

in_subquery(col(:users, :id), sq)
# → users.id IN (SELECT orders.user_id FROM orders WHERE orders.status = 'pending')
```
"""
in_subquery(expr::SQLExpr, sq::Subquery)::BinaryOp = BinaryOp(:IN, expr, sq)

"""
    not_in_subquery(expr::SQLExpr, sq::Subquery) -> BinaryOp

Test if an expression is not in the result set of a subquery.

# Example

```julia
sq = subquery(from(:blocked_users) |>
              select(NamedTuple, col(:blocked_users, :user_id)))

not_in_subquery(col(:users, :id), sq)
# → users.id NOT IN (SELECT blocked_users.user_id FROM blocked_users)
```
"""
not_in_subquery(expr::SQLExpr, sq::Subquery)::BinaryOp = BinaryOp(:NOT_IN, expr, sq)

# CASE expression
"""
    CaseExpr(whens::Vector{Tuple{SQLExpr, SQLExpr}}, else_expr::Union{SQLExpr, Nothing})

Represents a CASE expression in SQL.

This implements the "searched CASE" form:
```sql
CASE
  WHEN condition1 THEN result1
  WHEN condition2 THEN result2
  ELSE else_result
END
```

# Fields

  - `whens::Vector{Tuple{SQLExpr, SQLExpr}}` – list of (condition, result) pairs
  - `else_expr::Union{SQLExpr, Nothing}` – optional ELSE clause result

# Example

```julia
# Age category
case_expr([
    (col(:users, :age) < literal(18), literal("minor")),
    (col(:users, :age) < literal(65), literal("adult"))
], literal("senior"))
# → CASE WHEN age < 18 THEN 'minor' WHEN age < 65 THEN 'adult' ELSE 'senior' END

# Grade calculation
case_expr([
    (col(:scores, :value) >= literal(90), literal("A")),
    (col(:scores, :value) >= literal(80), literal("B")),
    (col(:scores, :value) >= literal(70), literal("C"))
], literal("F"))
# → CASE WHEN value >= 90 THEN 'A' WHEN value >= 80 THEN 'B' WHEN value >= 70 THEN 'C' ELSE 'F' END
```

# Note

The simple CASE form (`CASE value WHEN x THEN y`) is not directly supported,
but can be achieved using searched CASE with equality comparisons.
"""
struct CaseExpr <: SQLExpr
    whens::Vector{Tuple{SQLExpr, SQLExpr}}
    else_expr::Union{SQLExpr, Nothing}
end

"""
    case_expr(whens::Vector{Tuple{SQLExpr, SQLExpr}}, else_result::SQLExpr) -> CaseExpr
    case_expr(whens::Vector{Tuple{SQLExpr, SQLExpr}}) -> CaseExpr

Convenience constructor for CASE expressions.

# Example

```julia
# With ELSE clause
case_expr([
    (col(:users, :status) == literal("active"), literal(1)),
    (col(:users, :status) == literal("pending"), literal(0))
], literal(-1))

# Without ELSE clause (returns NULL if no condition matches)
case_expr([
    (col(:users, :verified) == literal(true), literal("✓")),
    (col(:users, :verified) == literal(false), literal("✗"))
])
```
"""
case_expr(whens::Vector{Tuple{SQLExpr, SQLExpr}}, else_result::SQLExpr)::CaseExpr =
    CaseExpr(whens, else_result)

case_expr(whens::Vector{Tuple{SQLExpr, SQLExpr}})::CaseExpr =
    CaseExpr(whens, nothing)

"""
    case_expr(whens::Vector, else_result) -> CaseExpr
    case_expr(whens::Vector) -> CaseExpr

Convenience constructor with auto-wrapping for else_result.

# Example

```julia
# else_result as plain value (auto-wrapped in literal)
case_expr([
    (col(:users, :age) < 18, "minor"),
    (col(:users, :age) < 65, "adult")
], "senior")
```
"""
function case_expr(whens::Vector, else_result)::CaseExpr
    # Convert tuples with non-SQLExpr results to SQLExpr
    converted_whens = Tuple{SQLExpr, SQLExpr}[
        (cond, result isa SQLExpr ? result : literal(result))
        for (cond, result) in whens
    ]
    else_wrapped = else_result isa SQLExpr ? else_result : literal(else_result)
    return CaseExpr(converted_whens, else_wrapped)
end

function case_expr(whens::Vector)::CaseExpr
    # Convert tuples with non-SQLExpr results to SQLExpr
    converted_whens = Tuple{SQLExpr, SQLExpr}[
        (cond, result isa SQLExpr ? result : literal(result))
        for (cond, result) in whens
    ]
    return CaseExpr(converted_whens, nothing)
end

# Structural equality for testing
# These are used by @test and other testing utilities
Base.isequal(a::ColRef, b::ColRef)::Bool = a.table == b.table && a.column == b.column
Base.isequal(a::Literal, b::Literal)::Bool = isequal(a.value, b.value)
Base.isequal(a::Param, b::Param)::Bool = a.type == b.type && a.name == b.name
Base.isequal(a::PlaceholderField, b::PlaceholderField)::Bool = a.column == b.column
Base.isequal(a::BinaryOp, b::BinaryOp)::Bool = a.op == b.op && isequal(a.left, b.left) &&
                                               isequal(a.right, b.right)
Base.isequal(a::UnaryOp, b::UnaryOp)::Bool = a.op == b.op && isequal(a.expr, b.expr)
Base.isequal(a::FuncCall, b::FuncCall)::Bool = a.name == b.name && isequal(a.args, b.args)
Base.isequal(a::BetweenOp, b::BetweenOp)::Bool = isequal(a.expr, b.expr) && isequal(a.low, b.low) &&
                                                  isequal(a.high, b.high) && a.negated == b.negated
Base.isequal(a::InOp, b::InOp)::Bool = isequal(a.expr, b.expr) && isequal(a.values, b.values) &&
                                       a.negated == b.negated
Base.isequal(a::Cast, b::Cast)::Bool = isequal(a.expr, b.expr) && a.target_type == b.target_type
Base.isequal(a::Subquery, b::Subquery)::Bool = isequal(a.query, b.query)
function Base.isequal(a::CaseExpr, b::CaseExpr)::Bool
    # Check WHEN clauses
    if !isequal(a.whens, b.whens)
        return false
    end

    # Check ELSE clause - handle Nothing properly
    if a.else_expr === nothing && b.else_expr === nothing
        return true
    elseif a.else_expr === nothing || b.else_expr === nothing
        return false
    else
        return isequal(a.else_expr, b.else_expr)
    end
end

# Hash functions for Dict/Set support
Base.hash(a::ColRef, h::UInt)::UInt = hash((a.table, a.column), h)
Base.hash(a::Literal, h::UInt)::UInt = hash(a.value, h)
Base.hash(a::Param, h::UInt)::UInt = hash((a.type, a.name), h)
Base.hash(a::PlaceholderField, h::UInt)::UInt = hash(a.column, h)
Base.hash(a::BinaryOp, h::UInt)::UInt = hash((a.op, a.left, a.right), h)
Base.hash(a::UnaryOp, h::UInt)::UInt = hash((a.op, a.expr), h)
Base.hash(a::FuncCall, h::UInt)::UInt = hash((a.name, a.args), h)
Base.hash(a::BetweenOp, h::UInt)::UInt = hash((a.expr, a.low, a.high, a.negated), h)
Base.hash(a::InOp, h::UInt)::UInt = hash((a.expr, a.values, a.negated), h)
Base.hash(a::Cast, h::UInt)::UInt = hash((a.expr, a.target_type), h)
Base.hash(a::Subquery, h::UInt)::UInt = hash(a.query, h)
Base.hash(a::CaseExpr, h::UInt)::UInt = hash((a.whens, a.else_expr), h)

# Future: Additional expression types
# (All major expression types now implemented)
