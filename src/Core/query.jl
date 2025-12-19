"""
# Query AST

This module defines the query abstract syntax tree (AST) for SQLSketch.

Queries represent complete SQL statements (SELECT, INSERT, UPDATE, DELETE)
as structured, composable values.

## Design Principles

- Queries follow SQL's **logical evaluation order** (FROM → WHERE → SELECT → ORDER BY → LIMIT)
- Output SQL follows SQL's **syntactic order**
- Most operations are **shape-preserving** (only `select` changes the output type)
- Queries are built via a pipeline API using `|>`

## Query Types

- `From{T}` – table source
- `Where{T}` – filter condition (shape-preserving)
- `Join{T}` – join operation (shape-preserving)
- `Select{OutT}` – projection (shape-changing)
- `OrderBy{T}` – ordering (shape-preserving)
- `Limit{T}` – limit/offset (shape-preserving)

## Usage

```julia
q = from(:users) |>
    where(col(:users, :active) == true) |>
    select(NamedTuple, col(:users, :id), col(:users, :email)) |>
    order_by(col(:users, :created_at), desc=true) |>
    limit(10)
```

See `docs/design.md` Section 6 for detailed design rationale.
"""

"""
Abstract base type for all query nodes.

Each query node is parameterized by its output type `T`.
"""
abstract type Query{T} end

#
# Core Query Types
#

"""
    From{T}(table::Symbol)

Represents a table source in a SQL query.

This is the starting point of any query pipeline.

# Type Parameter

  - `T`: The output type of rows from this query node (typically `NamedTuple`)

# Example

```julia
q = From{NamedTuple}(:users)
```
"""
struct From{T} <: Query{T}
    table::Symbol
end

"""
    Where{T}(source::Query{T}, condition::Expr)

Represents a WHERE clause that filters rows.

This is a **shape-preserving** operation – the output type `T` remains unchanged.

# Type Parameter

  - `T`: The output type (inherited from the source query)

# Example

```julia
q = From{NamedTuple}(:users)
q2 = Where(q, col(:users, :active) == literal(true))
```
"""
struct Where{T} <: Query{T}
    source::Query{T}
    condition::SQLExpr
end

"""
    Select{OutT}(source::Query, fields::Vector{Expr})

Represents a SELECT clause that projects specific columns.

This is the **only shape-changing** operation – it changes the output type from the
source type to `OutT`.

# Type Parameter

  - `OutT`: The output type after projection (e.g., `NamedTuple`, or a user-defined struct)

# Example

```julia
q = From{NamedTuple}(:users)
q2 = Select{NamedTuple}(q, [col(:users, :id), col(:users, :email)])
```
"""
struct Select{OutT} <: Query{OutT}
    source::Query
    fields::Vector{SQLExpr}
end

"""
    OrderBy{T}(source::Query{T}, orderings::Vector{Tuple{Expr, Bool}})

Represents an ORDER BY clause.

This is a **shape-preserving** operation – the output type `T` remains unchanged.

# Type Parameter

  - `T`: The output type (inherited from the source query)

# Fields

  - `orderings`: A vector of `(expression, descending)` tuples

# Example

```julia
q = From{NamedTuple}(:users)
q2 = OrderBy(q, [(col(:users, :created_at), true)])  # DESC
```
"""
struct OrderBy{T} <: Query{T}
    source::Query{T}
    orderings::Vector{Tuple{SQLExpr, Bool}}
end

"""
    Limit{T}(source::Query{T}, n::Int)

Represents a LIMIT clause.

This is a **shape-preserving** operation – the output type `T` remains unchanged.

# Type Parameter

  - `T`: The output type (inherited from the source query)

# Example

```julia
q = From{NamedTuple}(:users)
q2 = Limit(q, 10)
```
"""
struct Limit{T} <: Query{T}
    source::Query{T}
    n::Int
end

"""
    Offset{T}(source::Query{T}, n::Int)

Represents an OFFSET clause.

This is a **shape-preserving** operation – the output type `T` remains unchanged.

# Type Parameter

  - `T`: The output type (inherited from the source query)

# Example

```julia
q = From{NamedTuple}(:users)
q2 = Offset(q, 20)
```
"""
struct Offset{T} <: Query{T}
    source::Query{T}
    n::Int
end

"""
    Distinct{T}(source::Query{T})

Represents a DISTINCT clause.

This is a **shape-preserving** operation – the output type `T` remains unchanged.

# Type Parameter

  - `T`: The output type (inherited from the source query)

# Example

```julia
q = From{NamedTuple}(:users)
q2 = Distinct(q)
```
"""
struct Distinct{T} <: Query{T}
    source::Query{T}
end

"""
    GroupBy{T}(source::Query{T}, fields::Vector{Expr})

Represents a GROUP BY clause.

This is a **shape-preserving** operation – the output type `T` remains unchanged.

# Type Parameter

  - `T`: The output type (inherited from the source query)

# Example

```julia
q = From{NamedTuple}(:orders)
q2 = GroupBy(q, [col(:orders, :user_id)])
```
"""
struct GroupBy{T} <: Query{T}
    source::Query{T}
    fields::Vector{SQLExpr}
end

"""
    Having{T}(source::Query{T}, condition::Expr)

Represents a HAVING clause (used with GROUP BY).

This is a **shape-preserving** operation – the output type `T` remains unchanged.

# Type Parameter

  - `T`: The output type (inherited from the source query)

# Example

```julia
q = From{NamedTuple}(:orders) |> GroupBy([col(:orders, :user_id)])
q2 = Having(q, func(:COUNT, [col(:orders, :id)]) > literal(5))
```
"""
struct Having{T} <: Query{T}
    source::Query{T}
    condition::SQLExpr
end

"""
    Join{T}(source::Query, table::Symbol, on::Expr, kind::Symbol)

Represents a JOIN clause.

This is a **shape-preserving** operation for now – the output type `T` remains unchanged.
(In a full implementation, joins would combine types from both tables.)

# Type Parameter

  - `T`: The output type (inherited from the source query)

# Fields

  - `kind`: Join type (`:inner`, `:left`, `:right`, `:full`)

# Example

```julia
q = From{NamedTuple}(:users)
q2 = Join(q, :orders, col(:users, :id) == col(:orders, :user_id), :inner)
```
"""
struct Join{T} <: Query{T}
    source::Query{T}
    table::Symbol
    on::SQLExpr
    kind::Symbol  # :inner, :left, :right, :full
end

#
# Pipeline API
#

"""
    from(table::Symbol) -> From{NamedTuple}

Creates a FROM clause as the starting point of a query.

# Example

```julia
q = from(:users)
```
"""
function from(table::Symbol)::From{NamedTuple}
    return From{NamedTuple}(table)
end

"""
    where(q, condition)

Adds a WHERE clause to filter rows.

This is a **shape-preserving** operation.

Can be used in two ways:

  - Explicit: `where(query, condition)`
  - Pipeline: `query |> where(condition)`

The curried form `where(condition)` returns a function suitable for pipeline composition.

# Example

```julia
# Pipeline style
q = from(:users) |> where(col(:users, :active) == literal(true))

# Explicit style
q = where(from(:users), col(:users, :active) == literal(true))
```
"""
function where(q::Query{T}, condition::SQLExpr)::Where{T} where {T}
    return Where{T}(q, condition)
end

# Curried version for pipeline composition
where(condition::SQLExpr) = q -> where(q, condition)

"""
    select(q::Query, OutT::Type, fields::SQLExpr...) -> Select{OutT}

Adds a SELECT clause to project specific columns.

This is the **only shape-changing** operation – it changes the output type to `OutT`.

Can be used in two ways:

  - Explicit: `select(query, OutT, fields...)`
  - Pipeline: `query |> select(OutT, fields...)`

The curried form `select(OutT, fields...)` returns a function suitable for pipeline composition.

# Example

```julia
# Pipeline style
q = from(:users) |> select(NamedTuple, col(:users, :id), col(:users, :email))

# Explicit style
q = select(from(:users), NamedTuple, col(:users, :id), col(:users, :email))
```
"""
select(q::Query, OutT::Type, fields::SQLExpr...)::Select{OutT} = Select{OutT}(q,
                                                                              collect(fields))

# Curried version for pipeline composition
select(OutT::Type, fields::SQLExpr...) = q -> select(q, OutT, fields...)

"""
    order_by(q::Query{T}, field::SQLExpr; desc::Bool=false)::OrderBy{T}

Adds an ORDER BY clause.

This is a **shape-preserving** operation.

Can be used in two ways:

  - Explicit: `order_by(query, field, desc=false)`
  - Pipeline: `query |> order_by(field, desc=false)`

The curried form `order_by(field; desc=false)` returns a function suitable for pipeline composition.

# Example

```julia
# Pipeline style
q = from(:users) |> order_by(col(:users, :created_at); desc = true)

# Explicit style
q = order_by(from(:users), col(:users, :created_at); desc = true)
```
"""
function order_by(q::Query{T}, field::SQLExpr; desc::Bool = false) where {T}
    # If the query is already an OrderBy, append to its orderings
    if q isa OrderBy{T}
        return OrderBy{T}(q.source, vcat(q.orderings, [(field, desc)]))
    else
        return OrderBy{T}(q, [(field, desc)])
    end
end

# Curried version for pipeline composition
order_by(field::SQLExpr; desc::Bool = false) = q -> order_by(q, field, desc = desc)

"""
    limit(q::Query{T}, n::Int)::Limit{T}

Adds a LIMIT clause.

This is a **shape-preserving** operation.

Can be used in two ways:

  - Explicit: `limit(query, n)`
  - Pipeline: `query |> limit(n)`

The curried form `limit(n)` returns a function suitable for pipeline composition.

# Example

```julia
q = from(:users) |> limit(10)
```
"""
function limit(q::Query{T}, n::Int)::Limit{T} where {T}
    return Limit{T}(q, n)
end

# Curried version for pipeline composition
limit(n::Int) = q -> limit(q, n)

"""
    offset(q::Query{T}, n::Int)::Offset{T}

Adds an OFFSET clause.

This is a **shape-preserving** operation.

Can be used in two ways:

  - Explicit: `offset(query, n)`
  - Pipeline: `query |> offset(n)`

The curried form `offset(n)` returns a function suitable for pipeline composition.

# Example

```julia
q = from(:users) |> offset(20)
```
"""
function offset(q::Query{T}, n::Int)::Offset{T} where {T}
    return Offset{T}(q, n)
end

# Curried version for pipeline composition
offset(n::Int) = q -> offset(q, n)

"""
    distinct(q::Query{T}) -> Distinct{T}

Adds a DISTINCT clause.

This is a **shape-preserving** operation.

# Example

```julia
q = from(:users) |> select(NamedTuple, col(:users, :email)) |> distinct
```
"""
function distinct(q::Query{T})::Distinct{T} where {T}
    return Distinct{T}(q)
end

"""
    group_by(q::Query{T}, fields::SQLExpr...)::GroupBy{T}

Adds a GROUP BY clause.

This is a **shape-preserving** operation.

Can be used in two ways:

  - Explicit: `group_by(query, fields...)`
  - Pipeline: `query |> group_by(fields...)`

The curried form `group_by(fields...)` returns a function suitable for pipeline composition.

# Example

```julia
q = from(:orders) |> group_by(col(:orders, :user_id))
```
"""
function group_by(q::Query{T}, fields::SQLExpr...)::GroupBy{T} where {T}
    return GroupBy{T}(q, collect(fields))
end

# Curried version for pipeline composition
group_by(fields::SQLExpr...) = q -> group_by(q, fields...)

"""
    having(q::Query{T}, condition::SQLExpr)::Having{T}

Adds a HAVING clause (used with GROUP BY).

This is a **shape-preserving** operation.

Can be used in two ways:

  - Explicit: `having(query, condition)`
  - Pipeline: `query |> having(condition)`

The curried form `having(condition)` returns a function suitable for pipeline composition.

# Example

```julia
q = from(:orders) |>
    group_by(col(:orders, :user_id)) |>
    having(func(:COUNT, [col(:orders, :id)]) > literal(5))
```
"""
function having(q::Query{T}, condition::SQLExpr)::Having{T} where {T}
    return Having{T}(q, condition)
end

# Curried version for pipeline composition
having(condition::SQLExpr) = q -> having(q, condition)

"""
    join(q::Query{T}, table::Symbol, on::SQLExpr; kind::Symbol=:inner)::Join{T}

Adds a JOIN clause.

This is a **shape-preserving** operation (for now).

Can be used in two ways:

  - Explicit: `join(query, table, on, kind=:inner)`
  - Pipeline: `query |> join(table, on, kind=:inner)`

The curried form `join(table, on; kind=:inner)` returns a function suitable for pipeline composition.

# Arguments

  - `kind`: Join type (`:inner`, `:left`, `:right`, `:full`)

# Example

```julia
q = from(:users) |>
    join(:orders, col(:users, :id) == col(:orders, :user_id))
```
"""
function join(q::Query{T}, table::Symbol, on::SQLExpr; kind::Symbol = :inner) where {T}
    @assert kind in (:inner, :left, :right, :full) "Invalid join kind: $kind"
    return Join{T}(q, table, on, kind)
end

# Curried version for pipeline composition
join(table::Symbol, on::SQLExpr; kind::Symbol = :inner) = q -> join(q, table, on,
                                                                    kind = kind)

#
# Structural Equality (for testing)
#

Base.isequal(a::From{T}, b::From{T}) where {T} = a.table == b.table
Base.isequal(a::Where{T}, b::Where{T}) where {T} = isequal(a.source, b.source) &&
                                                   isequal(a.condition, b.condition)
Base.isequal(a::Select{T}, b::Select{T}) where {T} = isequal(a.source, b.source) &&
                                                     isequal(a.fields, b.fields)
Base.isequal(a::OrderBy{T}, b::OrderBy{T}) where {T} = isequal(a.source, b.source) &&
                                                       isequal(a.orderings, b.orderings)
Base.isequal(a::Limit{T}, b::Limit{T}) where {T} = isequal(a.source, b.source) && a.n == b.n
Base.isequal(a::Offset{T}, b::Offset{T}) where {T} = isequal(a.source, b.source) &&
                                                     a.n == b.n
Base.isequal(a::Distinct{T}, b::Distinct{T}) where {T} = isequal(a.source, b.source)
Base.isequal(a::GroupBy{T}, b::GroupBy{T}) where {T} = isequal(a.source, b.source) &&
                                                       isequal(a.fields, b.fields)
Base.isequal(a::Having{T}, b::Having{T}) where {T} = isequal(a.source, b.source) &&
                                                     isequal(a.condition, b.condition)
Base.isequal(a::Join{T}, b::Join{T}) where {T} = isequal(a.source, b.source) &&
                                                 a.table == b.table &&
                                                 isequal(a.on, b.on) && a.kind == b.kind

# Different types are never equal
Base.isequal(a::Query, b::Query) = false

# Hash functions (for Dict/Set support)
Base.hash(a::From{T}, h::UInt) where {T} = hash(a.table, h)
Base.hash(a::Where{T}, h::UInt) where {T} = hash((a.source, a.condition), h)
Base.hash(a::Select{T}, h::UInt) where {T} = hash((a.source, a.fields), h)
Base.hash(a::OrderBy{T}, h::UInt) where {T} = hash((a.source, a.orderings), h)
Base.hash(a::Limit{T}, h::UInt) where {T} = hash((a.source, a.n), h)
Base.hash(a::Offset{T}, h::UInt) where {T} = hash((a.source, a.n), h)
Base.hash(a::Distinct{T}, h::UInt) where {T} = hash(a.source, h)
Base.hash(a::GroupBy{T}, h::UInt) where {T} = hash((a.source, a.fields), h)
Base.hash(a::Having{T}, h::UInt) where {T} = hash((a.source, a.condition), h)
Base.hash(a::Join{T}, h::UInt) where {T} = hash((a.source, a.table, a.on, a.kind), h)
