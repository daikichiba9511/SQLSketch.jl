# SQLSketch.jl – Design Document

## 1. Purpose

SQLSketch.jl is an **experimental (“toy”) project** exploring the design of a
typed, composable SQL query core in Julia.

This project intentionally avoids competing with fully featured ORM frameworks.
Instead, it focuses on:

- exploring design trade-offs,
- clarifying abstraction boundaries,
- and validating architectural ideas in a small but realistic setting.

The code is serious; the positioning is not.

---

## 2. Design Goals

- SQL is always visible and inspectable
- Query APIs follow SQL's *logical evaluation order*
- Output SQL follows SQL's *syntactic order*
- Strong typing at query boundaries
- Minimal hidden magic
- Clear separation between core primitives and convenience layers
- **PostgreSQL-first development** with SQLite / MySQL compatibility

---

## 3. Non-Goals

- Replacing mature ORMs
- Hiding SQL completely
- Automatic schema diff or online migrations
- Full ActiveRecord-style relations
- Becoming a “standard” Julia DB abstraction

---

## 4. High-Level Architecture

```mermaid
flowchart TB
  A[Application] --> E[Extras Layer (optional)]
  E --> C[Core Layer (SQLSketch.Core)]

  subgraph Extras Layer (optional)
    E1[Repo / CRUD sugar]
    E2[Relations]
    E3[Validation integration]
    E4[Schema macros]
  end
  E --> E1
  E --> E2
  E --> E3
  E --> E4

  subgraph Core Layer (SQLSketch.Core)
    Q[Query AST]
    S[SQL Compile]
    X[Execute]
    M[Map]
    Q --> S --> X --> M

    EX[Expr AST] --> Q
    D[Dialect] --> S
    R[Driver] --> X
    K[CodecRegistry] --> M
  end
  C --> Q
Copy code
```

## 5. Core vs Extras Layer

SQLSketch.jl is intentionally designed as a **two-layer system**:

- a small, stable **Core layer**
- an optional, disposable **Extras layer**

This separation is fundamental to the project's goals.

---

### 5.1 Core Layer

The Core layer defines the **essential primitives** required to build,
compile, and execute SQL queries in a principled and inspectable way.

The Core layer is designed to be:

- minimal
- explicit
- stable over time
- independent of application-specific patterns

#### Core Responsibilities

The Core layer is responsible for:

- Query and Expression AST
- SQL compilation
- Dialect abstraction (PostgreSQL / MySQL / SQLite)
- Driver abstraction (connection, execution, transactions)
- Parameter binding
- Row decoding and mapping
- Transaction management
- Error normalization
- Observability hooks (logging / tracing)
- Migration application (runner)

The Core layer **does not** attempt to provide a full ORM experience.

---

### 5.2 Extras Layer

The Extras layer provides **convenience abstractions** built on top of the Core.

It exists to improve ergonomics, not to redefine semantics.

The Extras layer is explicitly considered **optional and replaceable**.

#### Extras Layer Responsibilities

Typical responsibilities of the Extras layer include:

- Repository patterns
- CRUD helpers
- Relation handling and preloading
- Schema definition macros
- DDL generation and diffing
- Validation-related sugar

All Extras-layer features must be expressible **purely in terms of Core APIs**.

---

### 5.3 Design Rationale

This separation allows SQLSketch.jl to:

- avoid over-committing to a single ORM style
- remain useful for both applications and data workflows
- keep the Core small enough to reason about
- experiment with higher-level abstractions without breaking the foundation

In other words:

> **Core defines "what is possible"; Extras defines "what is convenient".**

---

### 5.4 Stability Contract

The Core layer is expected to be:

- backward-compatible within reason
- conservative in API changes
- explicit about breaking changes

The Extras layer is free to evolve, change, or even be rewritten entirely.

This contract allows SQLSketch.jl to serve as a long-lived design exploration
without locking users into premature abstractions.

## 6. Query Model

At the heart of SQLSketch.jl is a **typed query model** built around
explicit structure and predictable transformations.

Rather than hiding SQL behind opaque abstractions, the query model
mirrors SQL semantics while remaining composable and inspectable.

---

### 6.1 Logical Pipeline API

Query construction follows **SQL’s logical evaluation order**, not its
syntactic order.

The logical order is:

```

FROM → JOIN → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT

````

In SQLSketch.jl, queries are constructed as a pipeline reflecting this order.

#### Example

```julia
q =
  from(users) |>
  where(_.active == true) |>
  select(UserDTO, _.id, _.email) |>
  order_by(_.created_at, desc=true) |>
  limit(10)
```


Internally, the query is represented as an AST.
When compiled, it is emitted as syntactically correct SQL:

```sql
SELECT id, email
FROM users
WHERE active = true
ORDER BY created_at DESC
LIMIT 10
```

---

### 6.2 Shape-Preserving vs Shape-Changing Operations

A key design rule in SQLSketch.jl is that **most query operations preserve
the output shape**.

#### Shape-Preserving Operations

The following operations do **not** change the query’s output type:

* `from`
* `join`
* `where`
* `group_by`
* `having`
* `order_by`
* `limit`
* `offset`
* `distinct`

These operations refine *which rows* are returned, not *what a row looks like*.

---

### 6.3 The Role of `select`

The `select` operation is the **only operation allowed to change
the output type** of a query.

This rule provides:

* predictable type flow
* easier reasoning about query transformations
* a clear boundary for data shaping

#### Examples

Selecting into a struct:

```julia
select(q, UserDTO, _.id, _.email)
```

Selecting into a `NamedTuple`:

```julia
select(q, _.id, _.email)
```

---

### 6.4 Output Type (`OutT`)

Each query is parameterized by an output type:

```
Select{OutT}
```

The output type determines:

* how rows are decoded
* how validation is applied (if any)
* what the user receives from `fetch_all`, `fetch_one`, or `fetch_maybe`

The Core layer treats `OutT` as an opaque type and relies on
constructors and codecs to enforce invariants.

---

### 6.5 Joins and Composite Results

JOIN operations combine multiple row sources.

By default, join results are represented as `NamedTuple` values,
preserving all columns explicitly.

Example:

```julia
from(users) |>
join(orders, on = _.users.id == _.orders.user_id)
```

This produces rows conceptually equivalent to:

```julia
(
  users = UserRow(...),
  orders = OrderRow(...)
)
```

Mapping into a domain-specific type requires an explicit `select`.

---

### 6.6 Rationale

This query model intentionally avoids:

* implicit projections
* automatic relation materialization
* silent type changes

Instead, it favors **explicitness and local reasoning**.

By constraining when and how the output type changes, SQLSketch.jl
makes complex queries easier to understand, refactor, and debug.

## 7. SQL Transparency

A core principle of SQLSketch.jl is that **SQL is never hidden**.

The library treats SQL as a first-class artifact that users are encouraged
to inspect, reason about, and debug.

---

### 7.1 Inspectable SQL

Every query can be inspected before execution.

SQLSketch.jl provides APIs such as:

- `sql(query)` – return the generated SQL string
- `compile(query)` – return SQL together with parameter ordering
- `explain(query)` – generate an EXPLAIN statement (if supported)

This design ensures that users are never forced to guess
what SQL is actually being executed.

---

### 7.2 Observability-Oriented Design

SQL transparency is also reflected in observability features.

The Core layer supports query hooks that receive:

- raw SQL
- parameter metadata
- execution timing
- row counts (when available)
- execution errors

This enables straightforward integration with logging,
tracing, and metrics systems without patching internals.

---

## 8. Expression Model

SQLSketch.jl represents SQL conditions and expressions explicitly
using an **Expression AST**.

Expressions are not strings.
They are structured values that can be inspected, transformed,
and compiled in a dialect-aware manner.

---

### 8.1 Expression AST

Examples of expression nodes include:

- column references
- literal values
- bound parameters
- binary operators (`=`, `<`, `AND`, `OR`, etc.)
- unary operators (`NOT`, `IS NULL`, etc.)
- subquery expressions (`IN`, `EXISTS`)

Expressions form trees that are embedded into query AST nodes
such as `WHERE`, `ON`, or `HAVING`.

---

### 8.2 Explicit Expressions

The Core API always allows expressions to be specified explicitly.

Example:

```julia
where(q, col(:users, :email) == param(String, :email))
````

This form is unambiguous and works uniformly across all query shapes,
including joins, subqueries, and correlated queries.

---

## 9. Placeholder Design

To improve ergonomics, SQLSketch.jl optionally supports
placeholder-based expression construction.

However, placeholders are **never required** by the Core layer.

---

### 9.1 Optional Placeholder (`_`)

A placeholder such as `_` may be used as syntactic sugar:

```julia
where(_.email == param(String, :email))
```

Internally, placeholder expressions are expanded into explicit
expression nodes.

---

### 9.2 Why Placeholders Are Optional

Placeholders are not mandatory for several reasons:

* they can become ambiguous in multi-join queries
* they add indirection during debugging
* they complicate core API contracts

For these reasons:

* the Core layer always accepts explicit expressions
* placeholder-based syntax is treated as optional sugar
* both styles can coexist in the same codebase

---

### 9.3 Design Rationale

By separating **expression semantics** from **expression syntax**,
SQLSketch.jl achieves the following:

* the Core remains small and explicit
* ergonomics can evolve independently
* advanced queries remain readable and debuggable

This approach balances usability with long-term maintainability.

## 10. Dialect and Driver Abstraction

SQLSketch.jl explicitly separates **what SQL is generated** from
**how SQL is executed**.

This separation is achieved through two orthogonal abstractions:

- **Dialect**: SQL generation and database semantics
- **Driver**: connection management and execution

---

### 10.1 Dialect

A Dialect represents a database’s SQL syntax and semantic differences.

Each supported database provides its own Dialect implementation
(e.g. SQLite, PostgreSQL, MySQL).

#### Dialect Responsibilities

A Dialect is responsible for:

- generating SQL strings from query ASTs
- quoting identifiers (tables, columns, aliases)
- defining placeholder syntax (`?`, `$1`, etc.)
- compiling DDL statements
- reporting supported features via capabilities

Dialect implementations are **pure**:
they do not manage connections or execute SQL.

---

### 10.2 Driver

A Driver represents the execution layer for a specific database backend.

Drivers handle all interactions with the underlying database client
(e.g. DBInterface, libpq, mysqlclient).

#### Driver Responsibilities

A Driver is responsible for:

- opening and closing connections
- preparing statements
- executing SQL statements
- binding parameters
- managing transactions
- handling cancellation and timeouts (if supported)

Drivers do **not** interpret query semantics or perform type conversion.

---

### 10.3 Why Separate Dialect and Driver

Separating Dialect and Driver provides several benefits:

- SQL generation can be tested without a database
- multiple drivers can share a dialect
- dialect logic remains independent of client libraries
- feature differences are made explicit

This design avoids conflating SQL semantics with execution mechanics.

---

## 11. Capability System

Database systems differ in supported features and behavior.
SQLSketch.jl makes these differences explicit using a **capability system**.

---

### 11.1 Capabilities

Capabilities describe optional database features, such as:

- Common Table Expressions (CTE)
- `RETURNING` clauses
- `UPSERT` / `ON CONFLICT`
- window functions
- bulk copy operations
- statement cancellation
- savepoints

Each Dialect reports which capabilities it supports.

---

### 11.2 Capability-Based Behavior

Capabilities influence behavior in two primary ways:

1. **Early failure**  
   If a query requires an unsupported capability,
   compilation fails with a clear error.

2. **Graceful degradation**  
   When possible, a Dialect may emit an alternative SQL formulation
   that avoids the unsupported feature.

This ensures that feature differences are visible and intentional.

---

### 11.3 Database-Specific Extensions

Some features are inherently database-specific.

Rather than forcing these into the Core API, SQLSketch.jl treats them
as **explicit extensions** guarded by capability checks.

Example:

````julia
if supports(dialect, CAP_COPY_FROM)
    copy_from(db, :table, source)
else
    error("COPY FROM is not supported by this database")
end
````

This approach keeps the Core API minimal while still allowing
advanced database-specific functionality.

---

### 11.4 Rationale

By combining Dialect abstraction with an explicit capability system,
SQLSketch.jl achieves:

* predictable cross-database behavior
* clear visibility into feature differences
* a stable foundation for experimentation
* a clean boundary between portable and non-portable code

This design avoids both lowest-common-denominator APIs
and accidental reliance on database-specific behavior.

## 12. Type Conversion and CodecRegistry

SQLSketch.jl centralizes all database-to-Julia type conversion
in a dedicated component called **CodecRegistry**.

This design explicitly separates:

- SQL semantics (Dialect)
- execution mechanics (Driver)
- **data representation and invariants (CodecRegistry)**

---

### 12.1 Motivation

Databases and Julia have fundamentally different type systems.

Examples include:

- NULL handling
- UUID representation
- Date / DateTime precision
- JSON storage formats
- SQLite’s dynamic typing

If handled implicitly, these differences quickly lead to
inconsistent behavior and subtle bugs.

SQLSketch.jl addresses this by making type conversion **explicit and centralized**.

---

### 12.2 CodecRegistry

The CodecRegistry defines how values are:

- encoded before being sent to the database
- decoded when read from the database

Each Julia type that participates in queries or result mapping
is associated with a codec.

Responsibilities of CodecRegistry include:

- encoding Julia values into database-compatible representations
- decoding database values into Julia types
- enforcing a consistent NULL policy
- normalizing backend-specific quirks

---

### 12.3 NULL Policy

NULL handling is a global policy decision.

SQLSketch.jl supports configurable NULL policies, such as:

- `Missing`-based representation (recommended)
- `Nothing`-based representation

The chosen policy is applied consistently across:

- query parameters
- result decoding
- struct construction

This avoids mixing NULL semantics within a single application.

---

### 12.4 Database-Specific Type Handling

#### PostgreSQL (Primary Target)

PostgreSQL is the primary development target with rich native type support:

- Native UUID type
- JSONB for structured data
- Precise timestamp handling with timezone support
- Arrays and composite types
- Full ACID compliance with strict type checking

#### SQLite (Development and Testing)

SQLite is supported as a lightweight backend for local development and testing.

Because SQLite is dynamically typed, the CodecRegistry plays
a critical role in enforcing invariants to maintain PostgreSQL compatibility.

Examples include:

- representing UUIDs as TEXT (PostgreSQL uses native UUID)
- normalizing DateTime values (PostgreSQL has precise TIMESTAMP WITH TIME ZONE)
- enforcing boolean semantics (PostgreSQL has native BOOLEAN)
- validating decoded values before struct construction

This ensures that SQLite-based testing remains meaningful
and compatible with PostgreSQL production deployments.

---

## 13. Query Execution Model

SQLSketch.jl provides a clear separation between **side-effecting operations** and **data retrieval operations**.

This distinction is fundamental to the execution API design.

---

### 13.1 Execute vs Fetch

The execution layer provides two categories of functions:

#### `execute` - Side Effects Only

```julia
execute(conn, query) -> Int64
```

**Purpose**: Execute SQL statements that produce **side effects** but do not return data.

**Returns**: Number of affected rows (for DML) or 0 (for DDL).

**Use cases**:
- `INSERT` without `RETURNING`
- `UPDATE` without `RETURNING`
- `DELETE` without `RETURNING`
- `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE`
- `CREATE INDEX`, `DROP INDEX`

**Example**:

```julia
# Insert without retrieving data
q = insert_into(:users, [:email, :name]) |>
    values([literal("alice@example.com"), literal("Alice")])

rows_affected = execute(conn, q)
# → 1
```

#### `fetch_*` - Data Retrieval

```julia
fetch_all(conn, query, T) -> Vector{T}
fetch_one(conn, query, T) -> T
fetch_maybe(conn, query, T) -> Union{T, Nothing}
```

**Purpose**: Execute SQL statements that **return data**.

**Returns**: Decoded rows as Julia values (structs, NamedTuples, etc.)

**Use cases**:
- `SELECT` queries
- `INSERT`/`UPDATE`/`DELETE` with `RETURNING`

**Example**:

```julia
# Retrieve data
q = from(:users) |>
    where(col(:users, :active) == literal(true)) |>
    select(NamedTuple, col(:users, :id), col(:users, :email))

users = fetch_all(conn, q, NamedTuple)
# → [{id: 1, email: "alice@example.com"}, ...]

# Insert with RETURNING
q = insert_into(:users, [:email, :name]) |>
    values([literal("bob@example.com"), literal("Bob")]) |>
    returning(col(:users, :id))

user_id = fetch_one(conn, q, Int64)
# → 42
```

---

### 13.2 Design Rationale

This separation provides several benefits:

1. **Intent clarity**: The function name signals whether you expect data back.

2. **Type safety**: `fetch_*` requires explicit result type, preventing type errors.

3. **Performance**: `execute` can skip row decoding overhead.

4. **Error detection**: Using `execute` on a `SELECT` or `fetch_*` on a `CREATE TABLE` makes the mistake obvious.

---

### 13.3 Unified API

Both `execute` and `fetch_*` accept the same connection types:

- `Connection` (direct connection)
- `TransactionHandle` (within a transaction)
- `SavepointHandle` (within a savepoint)

This means you can use the same code pattern regardless of transaction context:

```julia
# Direct execution
execute(conn, insert_query)

# Within transaction
transaction(conn) do tx
    execute(tx, insert_query)  # Same API
    users = fetch_all(tx, select_query, User)  # Same API
end
```

---

## 14. Transaction Model

Transaction handling is a **Core responsibility** in SQLSketch.jl.

Transactions are designed to be:

- explicit
- composable
- predictable
- safe by default

---

### 14.1 Transaction Semantics

Transactions follow a simple and strict rule:

- if the transaction block completes normally → **commit**
- if an exception escapes the block → **rollback**

Example:

````julia
transaction(db) do tx
    insert(tx, ...)
    update(tx, ...)
end
````

If any operation inside the block fails, all changes are rolled back.

---

### 14.2 Transaction Handles

Transaction handles are designed to be **connection-compatible**.

This means that within a transaction block:

* the same query execution APIs can be used
* code does not need to distinguish between a connection and a transaction

This simplifies application code and avoids branching logic.

---

### 14.3 Isolation and Advanced Features

Transaction options such as:

* isolation level
* read-only mode
* savepoints

are expressed explicitly and guarded by capabilities.

Unsupported options result in early, descriptive errors.

---

### 14.4 Rationale

By keeping transaction semantics simple and explicit,
SQLSketch.jl avoids:

* implicit nested transaction behavior
* hidden auto-commit rules
* backend-specific surprises

The transaction model favors clarity and correctness
over maximum flexibility, which aligns with the project’s
experimental and educational goals.

## 15. DDL and Migration Design

SQLSketch.jl treats schema management as a necessary but carefully
scoped responsibility.

The goal is to support **reliable schema evolution** without turning
the Core layer into a full schema-management framework.

---

### 14.1 Scope of Responsibility

The Core layer is responsible for:

- applying migrations
- tracking which migrations have been applied
- compiling DDL statements in a dialect-aware way

The Core layer explicitly does **not**:

- infer schema differences
- auto-generate migrations
- manage online or zero-downtime migrations

These higher-level concerns are intentionally left to the Extras layer
or external tooling.

---

### 14.2 Migration Runner

SQLSketch.jl includes a minimal **migration runner**.

The runner’s responsibilities include:

- discovering migration files
- applying migrations in a deterministic order
- recording applied versions
- preventing accidental re-application

A dedicated metadata table (e.g. `schema_migrations`) is used
to track applied migrations.

---

### 14.3 Migration Format

Migrations may be expressed in one of the following forms:

- raw SQL files
- structured DDL operations compiled by the Dialect

The Core layer treats migrations as **opaque units of change**.

This allows users to:

- write database-specific SQL when needed
- keep full control over schema evolution
- avoid leaky abstractions in DDL generation

---

### 14.4 Dialect-Aware DDL Compilation

DDL statements are compiled through the Dialect abstraction.

This allows:

- correct identifier quoting
- appropriate data type mapping
- explicit handling of unsupported features

If a DDL operation cannot be represented for a given Dialect,
the system fails early with a descriptive error.

---

### 14.5 Cross-Database Migration Support

#### PostgreSQL (Primary Target)

Migrations are primarily designed for PostgreSQL with full support for:

- Comprehensive constraint enforcement (CHECK, UNIQUE, FOREIGN KEY)
- Rich data types (UUID, JSONB, arrays, timestamps with timezone)
- Advanced features (partial indexes, exclusion constraints)

#### SQLite (Development and Testing)

SQLite is supported for local development and rapid iteration.

When applying the same migration set to SQLite, note that:

- SQLite may accept a broader range of schemas (more permissive)
- Some constraints behave differently (e.g., FOREIGN KEY enforcement)
- Runtime normalization is enforced via CodecRegistry to maintain PostgreSQL compatibility

This approach enables:
- Fast local testing without PostgreSQL infrastructure
- Early detection of schema issues before PostgreSQL deployment
- Consistent migration files across development and production databases

---

### 14.6 Rationale

By limiting the Core’s responsibility to migration application,
SQLSketch.jl avoids:

- overly complex schema DSLs
- brittle diff-based migration generation
- tight coupling between schema and query APIs

This design keeps schema management explicit, inspectable,
and aligned with the project’s exploratory nature.

## 16. Observability

SQLSketch.jl is designed to make database interactions **observable by default**.

Rather than hiding execution details behind abstractions, the Core layer
exposes hooks and inspection points that allow users to understand
what is happening at runtime.

---

### 15.1 Query Hooks

The Core layer supports query-level hooks that receive structured events,
including:

- the generated SQL string
- parameter metadata (keys and order)
- execution timing
- row counts (when available)
- execution errors

These hooks enable integration with:

- logging systems
- tracing frameworks
- metrics collection
- ad-hoc debugging tools

Observability is treated as a first-class concern, not an afterthought.

---

### 15.2 Explain and Debugging Support

SQLSketch.jl provides explicit support for query inspection via:

- `sql(query)` for raw SQL inspection
- `compile(query)` for SQL and parameter ordering
- `explain(query)` for database execution plans (when supported)

This allows performance issues to be investigated without
instrumenting internal code paths.

---

## 17. Testing Strategy

Testing is structured to reflect the layered architecture
and multi-database goals of SQLSketch.jl.

---

### 17.1 Unit Tests

Unit tests focus on **pure logic** and do not require a database.

Typical unit test targets include:

- Expression and Query AST construction
- SQL compilation for each Dialect
- Capability reporting
- CodecRegistry encode/decode behavior

These tests are fast and form the bulk of the test suite.

---

### 17.2 Integration Tests (SQLite)

Integration tests use **SQLite in-memory databases**.

They validate:

- end-to-end query execution
- parameter binding
- row decoding and mapping
- transaction commit and rollback
- migration application

SQLite enables fast, deterministic tests suitable for CI environments.

---

### 17.3 Compatibility Tests (PostgreSQL / MySQL)

A small number of compatibility tests are run against
PostgreSQL and MySQL.

These tests focus on:

- dialect-specific SQL generation
- feature-gated capabilities (e.g. RETURNING, UPSERT)
- type behavior differences
- transaction semantics

Compatibility tests are intentionally limited in scope
to avoid slowing down development.

---

## 18. Project Positioning

SQLSketch.jl is intentionally positioned as:

- exploratory
- educational
- experimental
- replaceable

It is not intended to be a drop-in replacement for mature ORMs
or database abstraction layers.

---

### 17.1 Design Exploration

The primary goal of SQLSketch.jl is to explore:

- how far a small, principled SQL core can go
- which abstractions are useful or harmful
- how to balance type safety with SQL transparency
- how Julia’s strengths apply to query construction

---

### 17.2 Evolution and Exit Strategy

If ideas explored in SQLSketch.jl prove valuable, they may be:

- extracted into separate libraries
- renamed and formalized
- upstreamed into more production-oriented projects

Conversely, if certain ideas do not work well,
they can be discarded without regret.

This flexibility is a deliberate design choice.

---

## 19. Summary

SQLSketch.jl explores how to build a **typed, composable SQL core**
without becoming a full ORM.

It prioritizes:

- clarity over completeness
- explicitness over convenience
- design exploration over polish

By keeping the Core small and principled,
SQLSketch.jl provides a safe environment for experimentation
while remaining grounded in real-world database usage.



