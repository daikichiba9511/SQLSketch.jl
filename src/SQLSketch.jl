"""
# SQLSketch.jl

An experimental typed SQL query builder for Julia, exploring the design of a
composable SQL core with minimal hidden magic.

## Design Philosophy

  - SQL is always visible and inspectable
  - Query APIs follow SQL's logical evaluation order
  - Output SQL follows SQL's syntactic order
  - Strong typing at query boundaries
  - Clear separation between core primitives and convenience layers

## Architecture

SQLSketch is designed as a two-layer system:

  - **Core Layer**: Essential primitives for building, compiling, and executing SQL
  - **Easy Layer** (future): Optional convenience abstractions

This module re-exports the Core layer APIs.

See `docs/design.md` for detailed design rationale.
See `docs/roadmap.md` for implementation plan.
"""
module SQLSketch

# Core submodule
module Core
# Expression AST (Phase 1)
include("Core/expr.jl")
export SQLExpr, ColRef, Literal, Param, RawExpr, BinaryOp, UnaryOp, FuncCall, BetweenOp,
       InOp
export Cast, Subquery, CaseExpr
export WindowFrame, Over, WindowFunc
export col, literal, param, raw_expr, func
export is_null, is_not_null
export like, not_like, ilike, not_ilike
export between, not_between
export in_list, not_in_list
export cast, subquery, exists, not_exists, in_subquery, not_in_subquery
export case_expr
export window_frame, over
export row_number, rank, dense_rank, ntile
export lag, lead, first_value, last_value, nth_value
export win_sum, win_avg, win_min, win_max, win_count

# Query AST (Phase 2 + DML + CTE + Set Operations)
include("Core/query.jl")
export Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy, Having, Join
export InsertInto, InsertValues, Update, UpdateSet, UpdateWhere, DeleteFrom, DeleteWhere
export Returning
export CTE, With
export SetUnion, SetIntersect, SetExcept
export OnConflict
export from, where, select, order_by, limit, offset, distinct, group_by, having, join
export insert_into, values, update, set, delete_from
export returning
export cte, with
export union, intersect, except
export on_conflict_do_nothing, on_conflict_do_update
# Aliases to avoid Base conflicts
export innerjoin, leftjoin, rightjoin, fulljoin, insert_values

# Dialect abstraction (Phase 3)
include("Core/dialect.jl")
export Dialect, Capability
export CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW, CAP_LATERAL, CAP_BULK_COPY,
       CAP_SAVEPOINT, CAP_ADVISORY_LOCK
export compile, compile_expr, quote_identifier, placeholder, supports

# Driver abstraction (Phase 4)
include("Core/driver.jl")
export Driver, Connection
export connect
export execute_sql  # Low-level SQL execution (escape hatch)

# CodecRegistry (Phase 5)
include("Core/codec.jl")
export Codec, CodecRegistry
export encode, decode
export register!, get_codec
export map_row
export IntCodec, Float64Codec, StringCodec, BoolCodec
export DateCodec, DateTimeCodec, UUIDCodec

# Transaction Management (Phase 7)
include("Core/transaction.jl")
export TransactionHandle
export transaction, savepoint

# Query Execution (Phase 6)
include("Core/execute.jl")
export fetch_all, fetch_one, fetch_maybe
export sql, explain
export execute, ExecResult  # Unified execution API
# execute_dml is internal (not exported)

# DDL (Phase 10)
include("Core/ddl.jl")
export DDLStatement
export ColumnType, ColumnConstraint, ColumnDef
export PrimaryKeyConstraint, NotNullConstraint, UniqueConstraint, DefaultConstraint
export CheckConstraint, ForeignKeyConstraint
export TableConstraint, TablePrimaryKey, TableForeignKey, TableUnique, TableCheck
export CreateTable, AlterTable, DropTable, CreateIndex, DropIndex
export AlterTableOp, AddColumn, DropColumn, RenameColumn, AddTableConstraint, DropConstraint
export create_table, add_column, add_primary_key, add_foreign_key, add_unique, add_check
export alter_table, add_alter_column, drop_alter_column, rename_alter_column
export drop_table, create_index, drop_index
# execute_ddl is internal (not exported), use execute() instead
end # module Core

# Extras submodule - optional convenience features
module Extras
# Placeholder syntax sugar
include("Extras/placeholder.jl")
export PlaceholderField, Placeholder, p_

# Migration runner
include("Extras/migrations.jl")
export Migration, MigrationStatus
export migration_checksum
export discover_migrations, parse_migration_file
export apply_migration, apply_migrations
export migration_status, validate_migration_checksums
export generate_migration
end # module Extras

# Dialect implementations
# Include shared helpers once before dialects
include("Dialects/shared_helpers.jl")
include("Dialects/sqlite.jl")
include("Dialects/postgresql.jl")

# Driver implementations
module Drivers
include("Drivers/sqlite.jl")
include("Drivers/postgresql.jl")
export SQLiteDriver, SQLiteConnection
export PostgreSQLDriver, PostgreSQLConnection
end

# PostgreSQL-specific codecs
module Codecs
module PostgreSQL
include("Codecs/postgresql.jl")
end
end

# Re-export everything from Core for convenience
using .Core
export SQLExpr, ColRef, Literal, Param, BinaryOp, UnaryOp, FuncCall, BetweenOp, InOp
export Cast, Subquery, CaseExpr
export WindowFrame, Over, WindowFunc
export col, literal, param, func
export is_null, is_not_null
export like, not_like, ilike, not_ilike
export between, not_between
export in_list, not_in_list
export cast, subquery, exists, not_exists, in_subquery, not_in_subquery
export case_expr
export window_frame, over
export row_number, rank, dense_rank, ntile
export lag, lead, first_value, last_value, nth_value
export win_sum, win_avg, win_min, win_max, win_count
export Query, From, Where, Select, OrderBy, Limit, Offset, Distinct, GroupBy, Having, Join
export InsertInto, InsertValues, Update, UpdateSet, UpdateWhere, DeleteFrom, DeleteWhere
export Returning
export CTE, With
export SetUnion, SetIntersect, SetExcept
export OnConflict
export from, where, select, order_by, limit, offset, distinct, group_by, having, join
export insert_into, values, update, set, delete_from
export returning
export cte, with
export union, intersect, except
export on_conflict_do_nothing, on_conflict_do_update
# Aliases to avoid Base conflicts
export innerjoin, leftjoin, rightjoin, fulljoin, insert_values
export Dialect, Capability
export CAP_CTE, CAP_RETURNING, CAP_UPSERT, CAP_WINDOW, CAP_LATERAL, CAP_BULK_COPY,
       CAP_SAVEPOINT, CAP_ADVISORY_LOCK
export compile, compile_expr, quote_identifier, placeholder, supports
export Driver, Connection
export connect
export execute_sql  # Low-level SQL execution (escape hatch)
export Codec, CodecRegistry
export encode, decode
export register!, get_codec
export map_row
export IntCodec, Float64Codec, StringCodec, BoolCodec
export DateCodec, DateTimeCodec, UUIDCodec

# Query execution (Phase 6)
export fetch_all, fetch_one, fetch_maybe
export sql, explain
export execute, ExecResult  # Unified execution API

# Transaction management (Phase 7)
export TransactionHandle
export transaction, savepoint

# DDL (Phase 10)
export DDLStatement
export ColumnType, ColumnConstraint, ColumnDef
export PrimaryKeyConstraint, NotNullConstraint, UniqueConstraint, DefaultConstraint
export CheckConstraint, ForeignKeyConstraint
export TableConstraint, TablePrimaryKey, TableForeignKey, TableUnique, TableCheck
export CreateTable, AlterTable, DropTable, CreateIndex, DropIndex
export AlterTableOp, AddColumn, DropColumn, RenameColumn, AddTableConstraint, DropConstraint
export create_table, add_column, add_primary_key, add_foreign_key, add_unique, add_check
export alter_table, add_alter_column, drop_alter_column, rename_alter_column
export drop_table, create_index, drop_index

# Export Dialect implementations
export SQLiteDialect, PostgreSQLDialect

# Re-export Driver implementations
using .Drivers
export SQLiteDriver, SQLiteConnection
export PostgreSQLDriver, PostgreSQLConnection

# Export PostgreSQL codecs module (users can access via SQLSketch.Codecs.PostgreSQL)
# Do not re-export individual codec types to avoid namespace pollution

# Re-export Extras layer for convenience
using .Extras
export PlaceholderField, Placeholder, p_
export Migration, MigrationStatus
export migration_checksum
export discover_migrations, parse_migration_file
export apply_migration, apply_migrations
export migration_status, validate_migration_checksums
export generate_migration

end # module SQLSketch
