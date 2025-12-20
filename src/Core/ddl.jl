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
                unique::Bool, if_not_exists::Bool, where::Union{SQLExpr, Nothing})

Represents a CREATE INDEX statement.

# Fields

  - `name::Symbol` – Index name
  - `table::Symbol` – Table name
  - `columns::Vector{Symbol}` – Columns to index
  - `unique::Bool` – Whether this is a unique index
  - `if_not_exists::Bool` – Whether to include IF NOT EXISTS
  - `where::Union{SQLExpr, Nothing}` – Optional partial index condition

# Example

```julia
create_index(:idx_users_email, :users, [:email]; unique = true)
```
"""
struct CreateIndex <: DDLStatement
    name::Symbol
    table::Symbol
    columns::Vector{Symbol}
    unique::Bool
    if_not_exists::Bool
    where::Union{SQLExpr, Nothing}
end

CreateIndex(name::Symbol, table::Symbol, columns::Vector{Symbol};
unique::Bool = false, if_not_exists::Bool = false,
where::Union{SQLExpr, Nothing} = nothing) = CreateIndex(name, table, columns, unique,
                                                        if_not_exists, where)

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
               references::Union{Tuple{Symbol, Symbol}, Nothing}=nothing) -> CreateTable

Add a column to a CREATE TABLE statement.

# Keyword Arguments

  - `primary_key::Bool` – Mark as PRIMARY KEY
  - `nullable::Bool` – Allow NULL values (default true)
  - `unique::Bool` – Add UNIQUE constraint
  - `default::Union{SQLExpr, Nothing}` – Default value expression
  - `references::Union{Tuple{Symbol, Symbol}, Nothing}` – Foreign key reference (table, column)

# Example

```julia
create_table(:users) |>
add_column(:id, :integer; primary_key = true) |>
add_column(:email, :text; nullable = false, unique = true) |>
add_column(:created_at, :timestamp; default = literal(:current_timestamp))
```
"""
function add_column(ct::CreateTable, name::Symbol, type::ColumnType;
                    primary_key::Bool = false,
                    nullable::Bool = true,
                    unique::Bool = false,
                    default::Union{SQLExpr, Nothing} = nothing,
                    references::Union{Tuple{Symbol, Symbol}, Nothing} = nothing)::CreateTable
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
add_column(:id, :integer; primary_key = true) |>
add_column(:email, :text; nullable = false)
```
"""
function add_column(name::Symbol, type::ColumnType;
                    primary_key::Bool = false,
                    nullable::Bool = true,
                    unique::Bool = false,
                    default::Union{SQLExpr, Nothing} = nothing,
                    references::Union{Tuple{Symbol, Symbol}, Nothing} = nothing)
    return ct -> add_column(ct, name, type;
                            primary_key = primary_key,
                            nullable = nullable,
                            unique = unique,
                            default = default,
                            references = references)
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
add_alter_column(:age, :integer; nullable = false)
```
"""
function add_alter_column(at::AlterTable, name::Symbol, type::ColumnType;
                          primary_key::Bool = false,
                          nullable::Bool = true,
                          unique::Bool = false,
                          default::Union{SQLExpr, Nothing} = nothing,
                          references::Union{Tuple{Symbol, Symbol}, Nothing} = nothing)::AlterTable
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
                          references::Union{Tuple{Symbol, Symbol}, Nothing} = nothing)
    return at -> add_alter_column(at, name, type;
                                  primary_key = primary_key,
                                  nullable = nullable,
                                  unique = unique,
                                  default = default,
                                  references = references)
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
                 where::Union{SQLExpr, Nothing}=nothing) -> CreateIndex

Create a CREATE INDEX statement.

# Example

```julia
create_index(:idx_users_email, :users, [:email])
create_index(:idx_users_email, :users, [:email]; unique = true)
create_index(:idx_active_users, :users, [:id];
             where = col(:users, :active) == literal(true))
```
"""
function create_index(name::Symbol, table::Symbol, columns::Vector{Symbol};
                      unique::Bool = false,
                      if_not_exists::Bool = false,
                      where::Union{SQLExpr, Nothing} = nothing)::CreateIndex
    return CreateIndex(name, table, columns, unique, if_not_exists, where)
end

# Convenience for single column
function create_index(name::Symbol, table::Symbol, column::Symbol;
                      unique::Bool = false,
                      if_not_exists::Bool = false,
                      where::Union{SQLExpr, Nothing} = nothing)::CreateIndex
    return create_index(name, table, [column]; unique = unique,
                        if_not_exists = if_not_exists, where = where)
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
