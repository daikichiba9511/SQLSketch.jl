"""
# DDL (Data Definition Language) AST

This module defines the DDL abstract syntax tree for SQLSketch.

DDL statements represent schema operations (CREATE TABLE, ALTER TABLE, DROP TABLE, CREATE INDEX)
as structured, composable values.

## Design Principles

- DDL statements are type-safe and inspectable
- Support for portable column types (mapped by dialects)
- Constraints can be inline (column-level) or table-level
- Pipeline API for building complex schema definitions

## DDL Types

- `CreateTable` – CREATE TABLE statement
- `AlterTable` – ALTER TABLE statement
- `DropTable` – DROP TABLE statement
- `CreateIndex` – CREATE INDEX statement
- `DropIndex` – DROP INDEX statement

## Usage

```julia
create_table(:users) |>
    add_column(:id, :integer, primary_key=true) |>
    add_column(:email, :text, nullable=false) |>
    add_unique(:email)
```

See `docs/design.md` for detailed design rationale.
"""

#
# Abstract Base Type
#

"""
Abstract base type for all DDL statements.

All DDL subtypes represent schema operations that can be compiled to SQL.
"""
abstract type DDLStatement end

#
# Column Types
#

"""
Portable SQL column types.

These are mapped to dialect-specific types during compilation:

  - `:integer` → INTEGER (SQLite), INT (MySQL), INTEGER (PostgreSQL)
  - `:bigint` → INTEGER (SQLite), BIGINT (MySQL), BIGINT (PostgreSQL)
  - `:real` → REAL (SQLite), DOUBLE (MySQL), DOUBLE PRECISION (PostgreSQL)
  - `:text` → TEXT (all)
  - `:blob` → BLOB (SQLite), BLOB (MySQL), BYTEA (PostgreSQL)
  - `:boolean` → INTEGER (SQLite), BOOLEAN (MySQL/PostgreSQL)
  - `:timestamp` → TEXT (SQLite), TIMESTAMP (MySQL/PostgreSQL)
  - `:date` → TEXT (SQLite), DATE (MySQL/PostgreSQL)
  - `:uuid` → TEXT (SQLite), CHAR(36) (MySQL), UUID (PostgreSQL)
  - `:json` → TEXT (SQLite), JSON (MySQL), JSONB (PostgreSQL)
"""
const ColumnType = Symbol

#
# Column Constraints
#

"""
    ColumnConstraint

Represents a column-level constraint (e.g., PRIMARY KEY, NOT NULL, UNIQUE).
"""
abstract type ColumnConstraint end

"""
    PrimaryKeyConstraint()

PRIMARY KEY constraint for a column.
"""
struct PrimaryKeyConstraint <: ColumnConstraint end

"""
    NotNullConstraint()

NOT NULL constraint for a column.
"""
struct NotNullConstraint <: ColumnConstraint end

"""
    UniqueConstraint()

UNIQUE constraint for a column.
"""
struct UniqueConstraint <: ColumnConstraint end

"""
    DefaultConstraint(value::SQLExpr)

DEFAULT constraint with a value expression.
"""
struct DefaultConstraint <: ColumnConstraint
    value::SQLExpr
end

"""
    CheckConstraint(condition::SQLExpr)

CHECK constraint with a condition expression.
"""
struct CheckConstraint <: ColumnConstraint
    condition::SQLExpr
end

"""
    ForeignKeyConstraint(ref_table::Symbol, ref_column::Symbol, on_delete::Symbol, on_update::Symbol)

FOREIGN KEY constraint referencing another table's column.

# Fields

  - `ref_table::Symbol` – Referenced table name
  - `ref_column::Symbol` – Referenced column name
  - `on_delete::Symbol` – ON DELETE action (:cascade, :restrict, :set_null, :set_default, :no_action)
  - `on_update::Symbol` – ON UPDATE action (:cascade, :restrict, :set_null, :set_default, :no_action)
"""
struct ForeignKeyConstraint <: ColumnConstraint
    ref_table::Symbol
    ref_column::Symbol
    on_delete::Symbol  # :cascade, :restrict, :set_null, :set_default, :no_action
    on_update::Symbol  # :cascade, :restrict, :set_null, :set_default, :no_action
end

# Constructor with defaults
ForeignKeyConstraint(ref_table::Symbol, ref_column::Symbol;
on_delete::Symbol = :no_action,
on_update::Symbol = :no_action) = ForeignKeyConstraint(ref_table, ref_column, on_delete,
                                                       on_update)

"""
    AutoIncrementConstraint()

AUTO_INCREMENT / SERIAL constraint for a column.

Mapped to dialect-specific syntax:

  - SQLite: AUTOINCREMENT
  - PostgreSQL: SERIAL / BIGSERIAL
  - MySQL: AUTO_INCREMENT
"""
struct AutoIncrementConstraint <: ColumnConstraint end

"""
    GeneratedConstraint(expr::SQLExpr, stored::Bool)

GENERATED column constraint with expression.

# Fields

  - `expr::SQLExpr` – Generation expression
  - `stored::Bool` – true for STORED, false for VIRTUAL
"""
struct GeneratedConstraint <: ColumnConstraint
    expr::SQLExpr
    stored::Bool
end

GeneratedConstraint(expr::SQLExpr; stored::Bool = true) = GeneratedConstraint(expr, stored)

"""
    CollationConstraint(collation::Symbol)

COLLATE constraint for string columns.

# Example

```julia
CollationConstraint(:nocase)  # SQLite
CollationConstraint(:utf8mb4_unicode_ci)  # MySQL
```
"""
struct CollationConstraint <: ColumnConstraint
    collation::Symbol
end

"""
    OnUpdateConstraint(value::SQLExpr)

ON UPDATE constraint (MySQL-specific).

# Example

```julia
OnUpdateConstraint(literal(:current_timestamp))
```
"""
struct OnUpdateConstraint <: ColumnConstraint
    value::SQLExpr
end

"""
    CommentConstraint(comment::String)

Column comment (PostgreSQL, MySQL).

# Example

```julia
CommentConstraint("User's email address")
```
"""
struct CommentConstraint <: ColumnConstraint
    comment::String
end

"""
    IdentityConstraint(always::Bool, start::Union{Int, Nothing}, increment::Union{Int, Nothing})

IDENTITY column constraint (PostgreSQL 10+).

# Fields

  - `always::Bool` – true for ALWAYS, false for BY DEFAULT
  - `start::Union{Int, Nothing}` – Starting value
  - `increment::Union{Int, Nothing}` – Increment value

# Example

```julia
IdentityConstraint(true, 1, 1)  # GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1)
```
"""
struct IdentityConstraint <: ColumnConstraint
    always::Bool
    start::Union{Int, Nothing}
    increment::Union{Int, Nothing}
end

IdentityConstraint(; always::Bool = false, start::Union{Int, Nothing} = nothing,
increment::Union{Int, Nothing} = nothing) = IdentityConstraint(always, start,
                                                               increment)

#
# Column Definition
#

"""
    ColumnDef(name::Symbol, type::ColumnType, constraints::Vector{ColumnConstraint})

Represents a column definition in a CREATE TABLE or ALTER TABLE statement.

# Fields

  - `name::Symbol` – Column name
  - `type::ColumnType` – Column type (portable symbol)
  - `constraints::Vector{ColumnConstraint}` – Column-level constraints

# Example

```julia
ColumnDef(:email, :text, [NotNullConstraint(), UniqueConstraint()])
```
"""
struct ColumnDef
    name::Symbol
    type::ColumnType
    constraints::Vector{ColumnConstraint}
end

# Constructor with empty constraints
ColumnDef(name::Symbol, type::ColumnType) = ColumnDef(name, type, ColumnConstraint[])

#
# Table Constraints
#

"""
    TableConstraint

Represents a table-level constraint (e.g., PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK).
"""
abstract type TableConstraint end

"""
    TablePrimaryKey(columns::Vector{Symbol}, name::Union{Symbol, Nothing})

Table-level PRIMARY KEY constraint.

# Fields

  - `columns::Vector{Symbol}` – Column names in the primary key
  - `name::Union{Symbol, Nothing}` – Optional constraint name
"""
struct TablePrimaryKey <: TableConstraint
    columns::Vector{Symbol}
    name::Union{Symbol, Nothing}
end

TablePrimaryKey(columns::Vector{Symbol}) = TablePrimaryKey(columns, nothing)

"""
    TableForeignKey(columns::Vector{Symbol}, ref_table::Symbol, ref_columns::Vector{Symbol},
                    on_delete::Symbol, on_update::Symbol, name::Union{Symbol, Nothing})

Table-level FOREIGN KEY constraint.

# Fields

  - `columns::Vector{Symbol}` – Local column names
  - `ref_table::Symbol` – Referenced table name
  - `ref_columns::Vector{Symbol}` – Referenced column names
  - `on_delete::Symbol` – ON DELETE action
  - `on_update::Symbol` – ON UPDATE action
  - `name::Union{Symbol, Nothing}` – Optional constraint name
"""
struct TableForeignKey <: TableConstraint
    columns::Vector{Symbol}
    ref_table::Symbol
    ref_columns::Vector{Symbol}
    on_delete::Symbol
    on_update::Symbol
    name::Union{Symbol, Nothing}
end

TableForeignKey(columns::Vector{Symbol}, ref_table::Symbol, ref_columns::Vector{Symbol};
on_delete::Symbol = :no_action, on_update::Symbol = :no_action,
name::Union{Symbol, Nothing} = nothing) = TableForeignKey(columns, ref_table, ref_columns,
                                                          on_delete, on_update, name)

"""
    TableUnique(columns::Vector{Symbol}, name::Union{Symbol, Nothing})

Table-level UNIQUE constraint.

# Fields

  - `columns::Vector{Symbol}` – Column names that must be unique together
  - `name::Union{Symbol, Nothing}` – Optional constraint name
"""
struct TableUnique <: TableConstraint
    columns::Vector{Symbol}
    name::Union{Symbol, Nothing}
end

TableUnique(columns::Vector{Symbol}) = TableUnique(columns, nothing)

"""
    TableCheck(condition::SQLExpr, name::Union{Symbol, Nothing})

Table-level CHECK constraint.

# Fields

  - `condition::SQLExpr` – Check condition expression
  - `name::Union{Symbol, Nothing}` – Optional constraint name
"""
struct TableCheck <: TableConstraint
    condition::SQLExpr
    name::Union{Symbol, Nothing}
end

TableCheck(condition::SQLExpr) = TableCheck(condition, nothing)

#
# CREATE TABLE
#

"""
    CreateTable(table::Symbol, columns::Vector{ColumnDef}, constraints::Vector{TableConstraint},
                if_not_exists::Bool, temporary::Bool)

Represents a CREATE TABLE statement.

# Fields

  - `table::Symbol` – Table name
  - `columns::Vector{ColumnDef}` – Column definitions
  - `constraints::Vector{TableConstraint}` – Table-level constraints
  - `if_not_exists::Bool` – Whether to include IF NOT EXISTS
  - `temporary::Bool` – Whether to create a temporary table

# Example

```julia
create_table(:users) |>
add_column(:id, :integer; primary_key = true) |>
add_column(:email, :text; nullable = false)
```
"""
struct CreateTable <: DDLStatement
    table::Symbol
    columns::Vector{ColumnDef}
    constraints::Vector{TableConstraint}
    if_not_exists::Bool
    temporary::Bool
end

# Constructor with defaults
CreateTable(table::Symbol;
if_not_exists::Bool = false,
temporary::Bool = false) = CreateTable(table, ColumnDef[], TableConstraint[], if_not_exists,
                                       temporary)

#
# ALTER TABLE
#

"""
Represents an ALTER TABLE operation type.
"""
abstract type AlterTableOp end

"""
    AddColumn(column::ColumnDef)

ALTER TABLE ADD COLUMN operation.
"""
struct AddColumn <: AlterTableOp
    column::ColumnDef
end

"""
    DropColumn(column::Symbol)

ALTER TABLE DROP COLUMN operation.
"""
struct DropColumn <: AlterTableOp
    column::Symbol
end

"""
    RenameColumn(old_name::Symbol, new_name::Symbol)

ALTER TABLE RENAME COLUMN operation.
"""
struct RenameColumn <: AlterTableOp
    old_name::Symbol
    new_name::Symbol
end

"""
    AddTableConstraint(constraint::TableConstraint)

ALTER TABLE ADD CONSTRAINT operation.
"""
struct AddTableConstraint <: AlterTableOp
    constraint::TableConstraint
end

"""
    DropConstraint(name::Symbol)

ALTER TABLE DROP CONSTRAINT operation.
"""
struct DropConstraint <: AlterTableOp
    name::Symbol
end

"""
    AlterColumnSetDefault(column::Symbol, value::SQLExpr)

ALTER TABLE ALTER COLUMN SET DEFAULT operation.

# Example

```julia
alter_table(:users) |>
set_column_default(:status, literal("active"))
```
"""
struct AlterColumnSetDefault <: AlterTableOp
    column::Symbol
    value::SQLExpr
end

"""
    AlterColumnDropDefault(column::Symbol)

ALTER TABLE ALTER COLUMN DROP DEFAULT operation.

# Example

```julia
alter_table(:users) |>
drop_column_default(:status)
```
"""
struct AlterColumnDropDefault <: AlterTableOp
    column::Symbol
end

"""
    AlterColumnSetNotNull(column::Symbol)

ALTER TABLE ALTER COLUMN SET NOT NULL operation.

# Example

```julia
alter_table(:users) |>
set_column_not_null(:email)
```
"""
struct AlterColumnSetNotNull <: AlterTableOp
    column::Symbol
end

"""
    AlterColumnDropNotNull(column::Symbol)

ALTER TABLE ALTER COLUMN DROP NOT NULL operation.

# Example

```julia
alter_table(:users) |>
drop_column_not_null(:phone)
```
"""
struct AlterColumnDropNotNull <: AlterTableOp
    column::Symbol
end

"""
    AlterColumnSetType(column::Symbol, type::ColumnType, using_expr::Union{SQLExpr, Nothing})

ALTER TABLE ALTER COLUMN SET DATA TYPE operation.

# Fields

  - `column::Symbol` – Column name
  - `type::ColumnType` – New column type
  - `using_expr::Union{SQLExpr, Nothing}` – Optional USING expression for type conversion

# Example

```julia
alter_table(:users) |>
set_column_type(:age, :bigint)

# With USING clause for type conversion
alter_table(:products) |>
set_column_type(:price, :integer; using_expr = cast(col(:products, :price), :integer))
```
"""
struct AlterColumnSetType <: AlterTableOp
    column::Symbol
    type::ColumnType
    using_expr::Union{SQLExpr, Nothing}
end

AlterColumnSetType(column::Symbol, type::ColumnType) = AlterColumnSetType(column, type,
                                                                          nothing)

"""
    AlterColumnSetStatistics(column::Symbol, target::Int)

ALTER TABLE ALTER COLUMN SET STATISTICS operation (PostgreSQL).

Sets the per-column statistics-gathering target.

# Example

```julia
alter_table(:users) |>
set_column_statistics(:email, 1000)
```
"""
struct AlterColumnSetStatistics <: AlterTableOp
    column::Symbol
    target::Int
end

"""
    AlterColumnSetStorage(column::Symbol, storage::Symbol)

ALTER TABLE ALTER COLUMN SET STORAGE operation (PostgreSQL).

Storage modes: :plain, :external, :extended, :main

# Example

```julia
alter_table(:users) |>
set_column_storage(:bio, :external)
```
"""
struct AlterColumnSetStorage <: AlterTableOp
    column::Symbol
    storage::Symbol  # :plain, :external, :extended, :main
end

"""
    AlterTable(table::Symbol, operations::Vector{AlterTableOp})

Represents an ALTER TABLE statement.

# Fields

  - `table::Symbol` – Table name
  - `operations::Vector{AlterTableOp}` – List of ALTER operations

# Example

```julia
alter_table(:users) |>
add_alter_column(:age, :integer) |>
drop_alter_column(:old_field)
```
"""
struct AlterTable <: DDLStatement
    table::Symbol
    operations::Vector{AlterTableOp}
end

AlterTable(table::Symbol) = AlterTable(table, AlterTableOp[])

#
# DROP TABLE
#

"""
    DropTable(table::Symbol, if_exists::Bool, cascade::Bool)

Represents a DROP TABLE statement.

# Fields

  - `table::Symbol` – Table name
  - `if_exists::Bool` – Whether to include IF EXISTS
  - `cascade::Bool` – Whether to include CASCADE

# Example

```julia
drop_table(:users; if_exists = true)
```
"""
struct DropTable <: DDLStatement
    table::Symbol
    if_exists::Bool
    cascade::Bool
end

DropTable(table::Symbol; if_exists::Bool = false, cascade::Bool = false) = DropTable(table,
                                                                                     if_exists,
                                                                                     cascade)

#
# CREATE INDEX
#

"""
    CreateIndex(name::Symbol, table::Symbol, columns::Vector{Symbol},
                unique::Bool, if_not_exists::Bool, where::Union{SQLExpr, Nothing},
                expressions::Union{Vector{SQLExpr}, Nothing}, method::Union{Symbol, Nothing})

Represents a CREATE INDEX statement.

# Fields

  - `name::Symbol` – Index name
  - `table::Symbol` – Table name
  - `columns::Vector{Symbol}` – Columns to index (mutually exclusive with expressions)
  - `unique::Bool` – Whether this is a unique index
  - `if_not_exists::Bool` – Whether to include IF NOT EXISTS
  - `where::Union{SQLExpr, Nothing}` – Optional partial index condition
  - `expressions::Union{Vector{SQLExpr}, Nothing}` – Expression index (e.g., `lower(email)`)
  - `method::Union{Symbol, Nothing}` – Index method (:btree, :hash, :gin, :gist, :brin, :spgist) - PostgreSQL only

# Example

```julia
# Column index
create_index(:idx_users_email, :users, [:email]; unique = true)

# Expression index
create_index(:idx_users_lower_email, :users;
             expr = [func(:lower, [col(:users, :email)])])

# Index with method (PostgreSQL)
create_index(:idx_users_tags, :users, [:tags]; method = :gin)
```
"""
struct CreateIndex <: DDLStatement
    name::Symbol
    table::Symbol
    columns::Vector{Symbol}
    unique::Bool
    if_not_exists::Bool
    where::Union{SQLExpr, Nothing}
    expressions::Union{Vector{SQLExpr}, Nothing}
    method::Union{Symbol, Nothing}
end

CreateIndex(name::Symbol, table::Symbol, columns::Vector{Symbol};
unique::Bool = false, if_not_exists::Bool = false,
where::Union{SQLExpr, Nothing} = nothing,
expressions::Union{Vector, Nothing} = nothing,
method::Union{Symbol, Nothing} = nothing) = CreateIndex(name, table, columns, unique,
                                                        if_not_exists, where,
                                                        expressions === nothing ? nothing :
                                                        convert(Vector{SQLExpr},
                                                                expressions),
                                                        method)

#
# DROP INDEX
#

"""
    DropIndex(name::Symbol, if_exists::Bool)

Represents a DROP INDEX statement.

# Fields

  - `name::Symbol` – Index name
  - `if_exists::Bool` – Whether to include IF EXISTS

# Example

```julia
drop_index(:idx_users_email; if_exists = true)
```
"""
struct DropIndex <: DDLStatement
    name::Symbol
    if_exists::Bool
end

DropIndex(name::Symbol; if_exists::Bool = false) = DropIndex(name, if_exists)

#
# Pipeline API - CREATE TABLE
#

"""
    create_table(table::Symbol; if_not_exists::Bool=false, temporary::Bool=false) -> CreateTable

Create a CREATE TABLE statement.

# Example

```julia
create_table(:users)
create_table(:users; if_not_exists = true)
create_table(:temp_data; temporary = true)
```
"""
function create_table(table::Symbol;
                      if_not_exists::Bool = false,
                      temporary::Bool = false)::CreateTable
    return CreateTable(table; if_not_exists = if_not_exists, temporary = temporary)
end

"""
    add_column(ct::CreateTable, name::Symbol, type::ColumnType;
               primary_key::Bool=false, nullable::Bool=true, unique::Bool=false,
               default::Union{SQLExpr, Nothing}=nothing,
               references::Union{Tuple{Symbol, Symbol}, Nothing}=nothing,
               check::Union{SQLExpr, Nothing}=nothing,
               auto_increment::Bool=false,
               generated::Union{SQLExpr, Nothing}=nothing,
               stored::Bool=true,
               collation::Union{Symbol, Nothing}=nothing,
               on_update::Union{SQLExpr, Nothing}=nothing,
               comment::Union{String, Nothing}=nothing,
               identity::Bool=false,
               identity_always::Bool=false,
               identity_start::Union{Int, Nothing}=nothing,
               identity_increment::Union{Int, Nothing}=nothing) -> CreateTable

Add a column to a CREATE TABLE statement.

# Keyword Arguments

  - `primary_key::Bool` – Mark as PRIMARY KEY
  - `nullable::Bool` – Allow NULL values (default true)
  - `unique::Bool` – Add UNIQUE constraint
  - `default::Union{SQLExpr, Nothing}` – Default value expression
  - `references::Union{Tuple{Symbol, Symbol}, Nothing}` – Foreign key reference (table, column)
  - `check::Union{SQLExpr, Nothing}` – Column-level CHECK constraint
  - `auto_increment::Bool` – AUTO_INCREMENT / SERIAL (dialect-specific)
  - `generated::Union{SQLExpr, Nothing}` – GENERATED column expression
  - `stored::Bool` – STORED (true) or VIRTUAL (false) for GENERATED columns
  - `collation::Union{Symbol, Nothing}` – COLLATE clause for string columns
  - `on_update::Union{SQLExpr, Nothing}` – ON UPDATE clause (MySQL)
  - `comment::Union{String, Nothing}` – Column comment
  - `identity::Bool` – IDENTITY column (PostgreSQL)
  - `identity_always::Bool` – ALWAYS (true) or BY DEFAULT (false) for IDENTITY
  - `identity_start::Union{Int, Nothing}` – Starting value for IDENTITY
  - `identity_increment::Union{Int, Nothing}` – Increment value for IDENTITY

# Example

```julia
create_table(:users) |>
add_column(:id, :integer; primary_key = true, auto_increment = true) |>
add_column(:email, :text; nullable = false, unique = true, collation = :nocase) |>
add_column(:age, :integer; check = col(:users, :age) >= literal(0)) |>
add_column(:created_at, :timestamp; default = literal(:current_timestamp))
```
"""
function add_column(ct::CreateTable, name::Symbol, type::ColumnType;
                    primary_key::Bool = false,
                    nullable::Bool = true,
                    unique::Bool = false,
                    default::Union{SQLExpr, Nothing} = nothing,
                    references::Union{Tuple{Symbol, Symbol}, Nothing} = nothing,
                    check::Union{SQLExpr, Nothing} = nothing,
                    auto_increment::Bool = false,
                    generated::Union{SQLExpr, Nothing} = nothing,
                    stored::Bool = true,
                    collation::Union{Symbol, Nothing} = nothing,
                    on_update::Union{SQLExpr, Nothing} = nothing,
                    comment::Union{String, Nothing} = nothing,
                    identity::Bool = false,
                    identity_always::Bool = false,
                    identity_start::Union{Int, Nothing} = nothing,
                    identity_increment::Union{Int, Nothing} = nothing)::CreateTable
    constraints = ColumnConstraint[]

    if primary_key
        push!(constraints, PrimaryKeyConstraint())
    end

    if !nullable
        push!(constraints, NotNullConstraint())
    end

    if unique
        push!(constraints, UniqueConstraint())
    end

    if default !== nothing
        push!(constraints, DefaultConstraint(default))
    end

    if references !== nothing
        ref_table, ref_column = references
        push!(constraints, ForeignKeyConstraint(ref_table, ref_column))
    end

    if check !== nothing
        push!(constraints, CheckConstraint(check))
    end

    if auto_increment
        push!(constraints, AutoIncrementConstraint())
    end

    if generated !== nothing
        push!(constraints, GeneratedConstraint(generated; stored = stored))
    end

    if collation !== nothing
        push!(constraints, CollationConstraint(collation))
    end

    if on_update !== nothing
        push!(constraints, OnUpdateConstraint(on_update))
    end

    if comment !== nothing
        push!(constraints, CommentConstraint(comment))
    end

    if identity
        push!(constraints,
              IdentityConstraint(; always = identity_always, start = identity_start,
                                 increment = identity_increment))
    end

    column = ColumnDef(name, type, constraints)
    new_columns = vcat(ct.columns, [column])

    return CreateTable(ct.table, new_columns, ct.constraints, ct.if_not_exists,
                       ct.temporary)
end

# Curried version for pipeline
"""
    add_column(name::Symbol, type::ColumnType; kwargs...) -> Function

Curried version of `add_column` for pipeline composition.

# Example

```julia
create_table(:users) |>
add_column(:id, :integer; primary_key = true, auto_increment = true) |>
add_column(:email, :text; nullable = false, collation = :nocase)
```
"""
function add_column(name::Symbol, type::ColumnType;
                    primary_key::Bool = false,
                    nullable::Bool = true,
                    unique::Bool = false,
                    default::Union{SQLExpr, Nothing} = nothing,
                    references::Union{Tuple{Symbol, Symbol}, Nothing} = nothing,
                    check::Union{SQLExpr, Nothing} = nothing,
                    auto_increment::Bool = false,
                    generated::Union{SQLExpr, Nothing} = nothing,
                    stored::Bool = true,
                    collation::Union{Symbol, Nothing} = nothing,
                    on_update::Union{SQLExpr, Nothing} = nothing,
                    comment::Union{String, Nothing} = nothing,
                    identity::Bool = false,
                    identity_always::Bool = false,
                    identity_start::Union{Int, Nothing} = nothing,
                    identity_increment::Union{Int, Nothing} = nothing)
    return ct -> add_column(ct, name, type;
                            primary_key = primary_key,
                            nullable = nullable,
                            unique = unique,
                            default = default,
                            references = references,
                            check = check,
                            auto_increment = auto_increment,
                            generated = generated,
                            stored = stored,
                            collation = collation,
                            on_update = on_update,
                            comment = comment,
                            identity = identity,
                            identity_always = identity_always,
                            identity_start = identity_start,
                            identity_increment = identity_increment)
end

"""
    add_primary_key(ct::CreateTable, columns::Vector{Symbol}; name::Union{Symbol, Nothing}=nothing) -> CreateTable

Add a table-level PRIMARY KEY constraint.

# Example

```julia
create_table(:users) |>
add_column(:id, :integer) |>
add_primary_key([:id])
```
"""
function add_primary_key(ct::CreateTable, columns::Vector{Symbol};
                         name::Union{Symbol, Nothing} = nothing)::CreateTable
    constraint = TablePrimaryKey(columns, name)
    new_constraints = vcat(ct.constraints, [constraint])
    return CreateTable(ct.table, ct.columns, new_constraints, ct.if_not_exists,
                       ct.temporary)
end

# Curried version
add_primary_key(columns::Vector{Symbol}; name::Union{Symbol, Nothing} = nothing) = ct -> add_primary_key(ct,
                                                                                                         columns;
                                                                                                         name = name)

"""
    add_foreign_key(ct::CreateTable, columns::Vector{Symbol}, ref_table::Symbol, ref_columns::Vector{Symbol};
                    on_delete::Symbol=:no_action, on_update::Symbol=:no_action,
                    name::Union{Symbol, Nothing}=nothing) -> CreateTable

Add a table-level FOREIGN KEY constraint.

# Example

```julia
create_table(:posts) |>
add_column(:user_id, :integer) |>
add_foreign_key([:user_id], :users, [:id]; on_delete = :cascade)
```
"""
function add_foreign_key(ct::CreateTable, columns::Vector{Symbol}, ref_table::Symbol,
                         ref_columns::Vector{Symbol};
                         on_delete::Symbol = :no_action,
                         on_update::Symbol = :no_action,
                         name::Union{Symbol, Nothing} = nothing)::CreateTable
    constraint = TableForeignKey(columns, ref_table, ref_columns;
                                 on_delete = on_delete, on_update = on_update, name = name)
    new_constraints = vcat(ct.constraints, [constraint])
    return CreateTable(ct.table, ct.columns, new_constraints, ct.if_not_exists,
                       ct.temporary)
end

# Curried version
function add_foreign_key(columns::Vector{Symbol}, ref_table::Symbol,
                         ref_columns::Vector{Symbol};
                         on_delete::Symbol = :no_action,
                         on_update::Symbol = :no_action,
                         name::Union{Symbol, Nothing} = nothing)
    return ct -> add_foreign_key(ct, columns, ref_table, ref_columns;
                                 on_delete = on_delete, on_update = on_update, name = name)
end

"""
    add_unique(ct::CreateTable, columns::Vector{Symbol}; name::Union{Symbol, Nothing}=nothing) -> CreateTable

Add a table-level UNIQUE constraint.

# Example

```julia
create_table(:users) |>
add_column(:email, :text) |>
add_unique([:email])
```
"""
function add_unique(ct::CreateTable, columns::Vector{Symbol};
                    name::Union{Symbol, Nothing} = nothing)::CreateTable
    constraint = TableUnique(columns, name)
    new_constraints = vcat(ct.constraints, [constraint])
    return CreateTable(ct.table, ct.columns, new_constraints, ct.if_not_exists,
                       ct.temporary)
end

# Curried version
add_unique(columns::Vector{Symbol}; name::Union{Symbol, Nothing} = nothing) = ct -> add_unique(ct,
                                                                                               columns;
                                                                                               name = name)

# Convenience for single column
add_unique(column::Symbol; name::Union{Symbol, Nothing} = nothing) = add_unique([column];
                                                                                name = name)

"""
    add_check(ct::CreateTable, condition::SQLExpr; name::Union{Symbol, Nothing}=nothing) -> CreateTable

Add a table-level CHECK constraint.

# Example

```julia
create_table(:users) |>
add_column(:age, :integer) |>
add_check(col(:users, :age) >= literal(0))
```
"""
function add_check(ct::CreateTable, condition::SQLExpr;
                   name::Union{Symbol, Nothing} = nothing)::CreateTable
    constraint = TableCheck(condition, name)
    new_constraints = vcat(ct.constraints, [constraint])
    return CreateTable(ct.table, ct.columns, new_constraints, ct.if_not_exists,
                       ct.temporary)
end

# Curried version
add_check(condition::SQLExpr; name::Union{Symbol, Nothing} = nothing) = ct -> add_check(ct,
                                                                                        condition;
                                                                                        name = name)

#
# Pipeline API - ALTER TABLE
#

"""
    alter_table(table::Symbol) -> AlterTable

Create an ALTER TABLE statement.

# Example

```julia
alter_table(:users) |>
add_alter_column(:age, :integer)
```
"""
function alter_table(table::Symbol)::AlterTable
    return AlterTable(table)
end

"""
    add_alter_column(at::AlterTable, name::Symbol, type::ColumnType; kwargs...) -> AlterTable

Add a column to an existing table (ALTER TABLE ADD COLUMN).

# Example

```julia
alter_table(:users) |>
add_alter_column(:age, :integer; nullable = false, check = col(:users, :age) >= literal(0))
```
"""
function add_alter_column(at::AlterTable, name::Symbol, type::ColumnType;
                          primary_key::Bool = false,
                          nullable::Bool = true,
                          unique::Bool = false,
                          default::Union{SQLExpr, Nothing} = nothing,
                          references::Union{Tuple{Symbol, Symbol}, Nothing} = nothing,
                          check::Union{SQLExpr, Nothing} = nothing,
                          auto_increment::Bool = false,
                          generated::Union{SQLExpr, Nothing} = nothing,
                          stored::Bool = true,
                          collation::Union{Symbol, Nothing} = nothing,
                          on_update::Union{SQLExpr, Nothing} = nothing,
                          comment::Union{String, Nothing} = nothing,
                          identity::Bool = false,
                          identity_always::Bool = false,
                          identity_start::Union{Int, Nothing} = nothing,
                          identity_increment::Union{Int, Nothing} = nothing)::AlterTable
    constraints = ColumnConstraint[]

    if primary_key
        push!(constraints, PrimaryKeyConstraint())
    end

    if !nullable
        push!(constraints, NotNullConstraint())
    end

    if unique
        push!(constraints, UniqueConstraint())
    end

    if default !== nothing
        push!(constraints, DefaultConstraint(default))
    end

    if references !== nothing
        ref_table, ref_column = references
        push!(constraints, ForeignKeyConstraint(ref_table, ref_column))
    end

    if check !== nothing
        push!(constraints, CheckConstraint(check))
    end

    if auto_increment
        push!(constraints, AutoIncrementConstraint())
    end

    if generated !== nothing
        push!(constraints, GeneratedConstraint(generated; stored = stored))
    end

    if collation !== nothing
        push!(constraints, CollationConstraint(collation))
    end

    if on_update !== nothing
        push!(constraints, OnUpdateConstraint(on_update))
    end

    if comment !== nothing
        push!(constraints, CommentConstraint(comment))
    end

    if identity
        push!(constraints,
              IdentityConstraint(; always = identity_always, start = identity_start,
                                 increment = identity_increment))
    end

    column = ColumnDef(name, type, constraints)
    op = AddColumn(column)
    new_ops = vcat(at.operations, [op])

    return AlterTable(at.table, new_ops)
end

# Curried version
function add_alter_column(name::Symbol, type::ColumnType;
                          primary_key::Bool = false,
                          nullable::Bool = true,
                          unique::Bool = false,
                          default::Union{SQLExpr, Nothing} = nothing,
                          references::Union{Tuple{Symbol, Symbol}, Nothing} = nothing,
                          check::Union{SQLExpr, Nothing} = nothing,
                          auto_increment::Bool = false,
                          generated::Union{SQLExpr, Nothing} = nothing,
                          stored::Bool = true,
                          collation::Union{Symbol, Nothing} = nothing,
                          on_update::Union{SQLExpr, Nothing} = nothing,
                          comment::Union{String, Nothing} = nothing,
                          identity::Bool = false,
                          identity_always::Bool = false,
                          identity_start::Union{Int, Nothing} = nothing,
                          identity_increment::Union{Int, Nothing} = nothing)
    return at -> add_alter_column(at, name, type;
                                  primary_key = primary_key,
                                  nullable = nullable,
                                  unique = unique,
                                  default = default,
                                  references = references,
                                  check = check,
                                  auto_increment = auto_increment,
                                  generated = generated,
                                  stored = stored,
                                  collation = collation,
                                  on_update = on_update,
                                  comment = comment,
                                  identity = identity,
                                  identity_always = identity_always,
                                  identity_start = identity_start,
                                  identity_increment = identity_increment)
end

"""
    drop_alter_column(at::AlterTable, column::Symbol) -> AlterTable

Drop a column from an existing table (ALTER TABLE DROP COLUMN).

# Example

```julia
alter_table(:users) |>
drop_alter_column(:old_field)
```
"""
function drop_alter_column(at::AlterTable, column::Symbol)::AlterTable
    op = DropColumn(column)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
drop_alter_column(column::Symbol) = at -> drop_alter_column(at, column)

"""
    rename_alter_column(at::AlterTable, old_name::Symbol, new_name::Symbol) -> AlterTable

Rename a column in an existing table (ALTER TABLE RENAME COLUMN).

# Example

```julia
alter_table(:users) |>
rename_alter_column(:old_name, :new_name)
```
"""
function rename_alter_column(at::AlterTable, old_name::Symbol, new_name::Symbol)::AlterTable
    op = RenameColumn(old_name, new_name)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
rename_alter_column(old_name::Symbol, new_name::Symbol) = at -> rename_alter_column(at,
                                                                                    old_name,
                                                                                    new_name)

#
# Pipeline API - ALTER COLUMN operations
#

"""
    set_column_default(at::AlterTable, column::Symbol, value::SQLExpr) -> AlterTable

Set a DEFAULT value for a column (ALTER TABLE ALTER COLUMN SET DEFAULT).

# Example

```julia
alter_table(:users) |>
set_column_default(:status, literal("active"))
```
"""
function set_column_default(at::AlterTable, column::Symbol, value::SQLExpr)::AlterTable
    op = AlterColumnSetDefault(column, value)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
set_column_default(column::Symbol, value::SQLExpr) = at -> set_column_default(at, column,
                                                                              value)

"""
    drop_column_default(at::AlterTable, column::Symbol) -> AlterTable

Drop the DEFAULT value for a column (ALTER TABLE ALTER COLUMN DROP DEFAULT).

# Example

```julia
alter_table(:users) |>
drop_column_default(:status)
```
"""
function drop_column_default(at::AlterTable, column::Symbol)::AlterTable
    op = AlterColumnDropDefault(column)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
drop_column_default(column::Symbol) = at -> drop_column_default(at, column)

"""
    set_column_not_null(at::AlterTable, column::Symbol) -> AlterTable

Set a column to NOT NULL (ALTER TABLE ALTER COLUMN SET NOT NULL).

# Example

```julia
alter_table(:users) |>
set_column_not_null(:email)
```
"""
function set_column_not_null(at::AlterTable, column::Symbol)::AlterTable
    op = AlterColumnSetNotNull(column)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
set_column_not_null(column::Symbol) = at -> set_column_not_null(at, column)

"""
    drop_column_not_null(at::AlterTable, column::Symbol) -> AlterTable

Allow NULL values for a column (ALTER TABLE ALTER COLUMN DROP NOT NULL).

# Example

```julia
alter_table(:users) |>
drop_column_not_null(:phone)
```
"""
function drop_column_not_null(at::AlterTable, column::Symbol)::AlterTable
    op = AlterColumnDropNotNull(column)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
drop_column_not_null(column::Symbol) = at -> drop_column_not_null(at, column)

"""
    set_column_type(at::AlterTable, column::Symbol, type::ColumnType;
                    using_expr::Union{SQLExpr, Nothing}=nothing) -> AlterTable

Change the data type of a column (ALTER TABLE ALTER COLUMN SET DATA TYPE).

# Keyword Arguments

  - `using_expr::Union{SQLExpr, Nothing}` – Optional USING expression for type conversion (PostgreSQL)

# Example

```julia
alter_table(:users) |>
set_column_type(:age, :bigint)

# With USING clause for type conversion
alter_table(:products) |>
set_column_type(:price, :integer; using_expr = cast(col(:products, :price), :integer))
```
"""
function set_column_type(at::AlterTable, column::Symbol, type::ColumnType;
                         using_expr::Union{SQLExpr, Nothing} = nothing)::AlterTable
    op = AlterColumnSetType(column, type, using_expr)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
function set_column_type(column::Symbol, type::ColumnType;
                         using_expr::Union{SQLExpr, Nothing} = nothing)
    return at -> set_column_type(at, column, type; using_expr = using_expr)
end

"""
    set_column_statistics(at::AlterTable, column::Symbol, target::Int) -> AlterTable

Set the statistics-gathering target for a column (ALTER TABLE ALTER COLUMN SET STATISTICS).

PostgreSQL only.

# Example

```julia
alter_table(:users) |>
set_column_statistics(:email, 1000)
```
"""
function set_column_statistics(at::AlterTable, column::Symbol, target::Int)::AlterTable
    op = AlterColumnSetStatistics(column, target)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
set_column_statistics(column::Symbol, target::Int) = at -> set_column_statistics(at, column,
                                                                                 target)

"""
    set_column_storage(at::AlterTable, column::Symbol, storage::Symbol) -> AlterTable

Set the storage mode for a column (ALTER TABLE ALTER COLUMN SET STORAGE).

PostgreSQL only. Storage modes: :plain, :external, :extended, :main

# Example

```julia
alter_table(:users) |>
set_column_storage(:bio, :external)
```
"""
function set_column_storage(at::AlterTable, column::Symbol, storage::Symbol)::AlterTable
    op = AlterColumnSetStorage(column, storage)
    new_ops = vcat(at.operations, [op])
    return AlterTable(at.table, new_ops)
end

# Curried version
set_column_storage(column::Symbol, storage::Symbol) = at -> set_column_storage(at, column,
                                                                               storage)

#
# Pipeline API - DROP TABLE
#

"""
    drop_table(table::Symbol; if_exists::Bool=false, cascade::Bool=false) -> DropTable

Create a DROP TABLE statement.

# Example

```julia
drop_table(:users)
drop_table(:users; if_exists = true)
drop_table(:users; cascade = true)
```
"""
function drop_table(table::Symbol; if_exists::Bool = false,
                    cascade::Bool = false)::DropTable
    return DropTable(table, if_exists, cascade)
end

#
# Pipeline API - CREATE INDEX
#

"""
    create_index(name::Symbol, table::Symbol, columns::Vector{Symbol};
                 unique::Bool=false, if_not_exists::Bool=false,
                 where::Union{SQLExpr, Nothing}=nothing,
                 expr::Union{Vector{SQLExpr}, Nothing}=nothing,
                 method::Union{Symbol, Nothing}=nothing) -> CreateIndex

Create a CREATE INDEX statement.

# Keyword Arguments

  - `unique::Bool` – Create a unique index
  - `if_not_exists::Bool` – Include IF NOT EXISTS clause
  - `where::Union{SQLExpr, Nothing}` – Partial index condition
  - `expr::Union{Vector{SQLExpr}, Nothing}` – Expression index (mutually exclusive with columns)
  - `method::Union{Symbol, Nothing}` – Index method (:btree, :hash, :gin, :gist, :brin, :spgist) - PostgreSQL only

# Example

```julia
# Column index
create_index(:idx_users_email, :users, [:email])
create_index(:idx_users_email, :users, [:email]; unique = true)

# Partial index
create_index(:idx_active_users, :users, [:id];
             where = col(:users, :active) == literal(true))

# Expression index
create_index(:idx_users_lower_email, :users, Symbol[];
             expr = [func(:lower, [col(:users, :email)])])

# Index with method (PostgreSQL)
create_index(:idx_users_tags, :users, [:tags]; method = :gin)
```
"""
function create_index(name::Symbol, table::Symbol, columns::Vector{Symbol} = Symbol[];
                      unique::Bool = false,
                      if_not_exists::Bool = false,
                      where::Union{SQLExpr, Nothing} = nothing,
                      expr::Union{Vector, Nothing} = nothing,
                      method::Union{Symbol, Nothing} = nothing)::CreateIndex
    # Validate mutually exclusive options
    if !isempty(columns) && expr !== nothing
        error("Cannot specify both columns and expr for index. Use one or the other.")
    end

    if isempty(columns) && expr === nothing
        error("Must specify either columns or expr for index.")
    end

    # Convert expr to Vector{SQLExpr} if provided
    expressions = expr === nothing ? nothing : convert(Vector{SQLExpr}, expr)

    return CreateIndex(name, table, columns, unique, if_not_exists, where, expressions,
                       method)
end

# Convenience for single column
function create_index(name::Symbol, table::Symbol, column::Symbol;
                      unique::Bool = false,
                      if_not_exists::Bool = false,
                      where::Union{SQLExpr, Nothing} = nothing,
                      method::Union{Symbol, Nothing} = nothing)::CreateIndex
    return create_index(name, table, [column]; unique = unique,
                        if_not_exists = if_not_exists, where = where, method = method)
end

#
# Pipeline API - DROP INDEX
#

"""
    drop_index(name::Symbol; if_exists::Bool=false) -> DropIndex

Create a DROP INDEX statement.

# Example

```julia
drop_index(:idx_users_email)
drop_index(:idx_users_email; if_exists = true)
```
"""
function drop_index(name::Symbol; if_exists::Bool = false)::DropIndex
    return DropIndex(name, if_exists)
end

#
# DDL Execution
#

# Helper: Infer command type from DDLStatement
"""
    infer_command_type(stmt::DDLStatement) -> Symbol

Infer the command type from a DDLStatement AST node.

Returns one of: :create_table, :drop_table, :alter_table, :create_index, :drop_index
"""
function infer_command_type(stmt::DDLStatement)::Symbol
    if stmt isa CreateTable
        return :create_table
    elseif stmt isa DropTable
        return :drop_table
    elseif stmt isa AlterTable
        return :alter_table
    elseif stmt isa CreateIndex
        return :create_index
    elseif stmt isa DropIndex
        return :drop_index
    else
        return :unknown
    end
end

"""
    execute_ddl(conn, dialect, ddl_statement) -> ExecResult

Execute a DDL (Data Definition Language) statement.

**Note:** This is an internal API. Most users should use the unified `execute()` API instead.

# Arguments

  - `conn::Connection`: Active database connection
  - `dialect::Dialect`: SQL dialect to use for compilation
  - `ddl_statement::DDLStatement`: DDL statement to execute (CREATE TABLE, DROP TABLE, etc.)

# Returns

ExecResult with command_type (:create_table, :drop_table, :alter_table, :create_index, :drop_index)
and rowcount = nothing

# Example

```julia
ddl = create_table(:users) |>
      add_column(:id, :integer; primary_key = true) |>
      add_column(:name, :text; nullable = false)

result = execute_ddl(db, dialect, ddl)
# -> ExecResult(:create_table, nothing)
```
"""
function execute_ddl(conn::Connection,
                     dialect::Dialect,
                     ddl_statement::DDLStatement)::ExecResult
    # Compile DDL to SQL (returns tuple (sql, params))
    sql, _params = compile(dialect, ddl_statement)

    # Execute DDL (no parameters needed)
    execute_sql(conn, sql, Any[])

    # Return execution result
    return ExecResult(infer_command_type(ddl_statement), nothing)
end

# Allow execute_ddl to work with TransactionHandle
function execute_ddl(tx::TransactionHandle,
                     dialect::Dialect,
                     ddl_statement::DDLStatement)::ExecResult
    # Compile DDL to SQL (returns tuple (sql, params))
    sql, _params = compile(dialect, ddl_statement)

    # Execute DDL (no parameters needed)
    execute_sql(tx, sql, Any[])

    # Return execution result
    return ExecResult(infer_command_type(ddl_statement), nothing)
end

"""
    execute(conn::Connection, dialect::Dialect, ddl::DDLStatement) -> ExecResult

Unified API for executing DDL statements (CREATE TABLE, DROP TABLE, etc.) with side effects.

This is the recommended API for all DDL execution. Dispatches internally to `execute_ddl`.

# Arguments

  - `conn`: Database connection
  - `dialect`: SQL dialect for compilation
  - `ddl`: DDL statement AST

# Returns

ExecResult containing:

  - `command_type::Symbol`: Type of command executed (:create_table, :drop_table, etc.)
  - `rowcount::Union{Int, Nothing}`: Always nothing for DDL

# Example

```julia
# CREATE TABLE
ddl = create_table(:users) |>
      add_column(:id, :integer; primary_key = true) |>
      add_column(:name, :text; nullable = false)
result = execute(conn, dialect, ddl)
# -> ExecResult(:create_table, nothing)

# DROP TABLE
ddl = drop_table(:users; if_exists = true)
result = execute(conn, dialect, ddl)
# -> ExecResult(:drop_table, nothing)

# CREATE INDEX
ddl = create_index(:idx_users_email) |> on(:users, :email)
result = execute(conn, dialect, ddl)
# -> ExecResult(:create_index, nothing)
```
"""
function execute(conn::Connection,
                 dialect::Dialect,
                 ddl::DDLStatement)::ExecResult
    return execute_ddl(conn, dialect, ddl)
end

# Allow execute with DDLStatement to work with TransactionHandle
function execute(tx::TransactionHandle,
                 dialect::Dialect,
                 ddl::DDLStatement)::ExecResult
    return execute_ddl(tx, dialect, ddl)
end
