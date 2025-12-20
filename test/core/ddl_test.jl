"""
# DDL AST Tests

Unit tests for the DDL (Data Definition Language) AST implementation.

These tests validate:
- DDL statement construction
- Column and constraint definitions
- Pipeline API functionality
- Type correctness
- Immutability

See `docs/roadmap.md` Phase 10 for implementation plan.
"""

using Test
using SQLSketch.Core: DDLStatement, CreateTable, AlterTable, DropTable, CreateIndex,
                      DropIndex
using SQLSketch.Core: ColumnDef, ColumnConstraint, ColumnType
using SQLSketch.Core: PrimaryKeyConstraint, NotNullConstraint, UniqueConstraint
using SQLSketch.Core: DefaultConstraint, CheckConstraint, ForeignKeyConstraint
using SQLSketch.Core: AutoIncrementConstraint, GeneratedConstraint, CollationConstraint
using SQLSketch.Core: OnUpdateConstraint, CommentConstraint, IdentityConstraint
using SQLSketch.Core: TableConstraint, TablePrimaryKey, TableForeignKey, TableUnique,
                      TableCheck
using SQLSketch.Core: AlterTableOp, AddColumn, DropColumn, RenameColumn
using SQLSketch.Core: create_table, add_column, add_primary_key, add_foreign_key
using SQLSketch.Core: add_unique, add_check
using SQLSketch.Core: alter_table, add_alter_column, drop_alter_column, rename_alter_column
using SQLSketch.Core: drop_table, create_index, drop_index
using SQLSketch.Core: col, literal, func, BinaryOp, Literal, SQLExpr

@testset "DDL AST" begin
    @testset "Column Constraints" begin
        # PrimaryKeyConstraint
        pk = PrimaryKeyConstraint()
        @test pk isa ColumnConstraint
        @test pk isa PrimaryKeyConstraint

        # NotNullConstraint
        nn = NotNullConstraint()
        @test nn isa ColumnConstraint
        @test nn isa NotNullConstraint

        # UniqueConstraint
        uq = UniqueConstraint()
        @test uq isa ColumnConstraint
        @test uq isa UniqueConstraint

        # DefaultConstraint
        dc = DefaultConstraint(literal(42))
        @test dc isa ColumnConstraint
        @test dc.value isa Literal
        @test dc.value.value == 42

        # CheckConstraint
        cc = CheckConstraint(col(:users, :age) >= literal(0))
        @test cc isa ColumnConstraint
        @test cc.condition isa BinaryOp

        # ForeignKeyConstraint
        fk = ForeignKeyConstraint(:users, :id)
        @test fk isa ColumnConstraint
        @test fk.ref_table == :users
        @test fk.ref_column == :id
        @test fk.on_delete == :no_action
        @test fk.on_update == :no_action

        # ForeignKeyConstraint with actions
        fk2 = ForeignKeyConstraint(:users, :id, on_delete = :cascade, on_update = :restrict)
        @test fk2.on_delete == :cascade
        @test fk2.on_update == :restrict

        # AutoIncrementConstraint
        ai = AutoIncrementConstraint()
        @test ai isa ColumnConstraint
        @test ai isa AutoIncrementConstraint

        # GeneratedConstraint
        gc = GeneratedConstraint(col(:users, :id) + literal(1))
        @test gc isa ColumnConstraint
        @test gc.expr isa BinaryOp
        @test gc.stored == true

        gc_virtual = GeneratedConstraint(col(:users, :id) + literal(1); stored = false)
        @test gc_virtual.stored == false

        # CollationConstraint
        coll = CollationConstraint(:nocase)
        @test coll isa ColumnConstraint
        @test coll.collation == :nocase

        # OnUpdateConstraint
        ou = OnUpdateConstraint(literal(:current_timestamp))
        @test ou isa ColumnConstraint
        @test ou.value isa Literal

        # CommentConstraint
        comm = CommentConstraint("User ID")
        @test comm isa ColumnConstraint
        @test comm.comment == "User ID"

        # IdentityConstraint
        id_c = IdentityConstraint()
        @test id_c isa ColumnConstraint
        @test id_c.always == false
        @test id_c.start === nothing
        @test id_c.increment === nothing

        id_c2 = IdentityConstraint(; always = true, start = 100, increment = 2)
        @test id_c2.always == true
        @test id_c2.start == 100
        @test id_c2.increment == 2
    end

    @testset "Column Definitions" begin
        # Basic column definition
        col_def = ColumnDef(:id, :integer)
        @test col_def isa ColumnDef
        @test col_def.name == :id
        @test col_def.type == :integer
        @test isempty(col_def.constraints)

        # Column with constraints
        constraints = [PrimaryKeyConstraint(), NotNullConstraint()]
        col_def2 = ColumnDef(:email, :text, constraints)
        @test col_def2.name == :email
        @test col_def2.type == :text
        @test length(col_def2.constraints) == 2
        @test col_def2.constraints[1] isa PrimaryKeyConstraint
        @test col_def2.constraints[2] isa NotNullConstraint
    end

    @testset "Table Constraints" begin
        # TablePrimaryKey
        tpk = TablePrimaryKey([:id])
        @test tpk isa TableConstraint
        @test tpk.columns == [:id]
        @test tpk.name === nothing

        tpk_named = TablePrimaryKey([:id, :email], :pk_users)
        @test tpk_named.columns == [:id, :email]
        @test tpk_named.name == :pk_users

        # TableForeignKey
        tfk = TableForeignKey([:user_id], :users, [:id])
        @test tfk isa TableConstraint
        @test tfk.columns == [:user_id]
        @test tfk.ref_table == :users
        @test tfk.ref_columns == [:id]
        @test tfk.on_delete == :no_action
        @test tfk.name === nothing

        tfk_cascade = TableForeignKey([:user_id], :users, [:id],
                                      on_delete = :cascade, name = :fk_posts_user)
        @test tfk_cascade.on_delete == :cascade
        @test tfk_cascade.name == :fk_posts_user

        # TableUnique
        tuq = TableUnique([:email])
        @test tuq isa TableConstraint
        @test tuq.columns == [:email]
        @test tuq.name === nothing

        # TableCheck
        tchk = TableCheck(col(:users, :age) >= literal(18))
        @test tchk isa TableConstraint
        @test tchk.condition isa BinaryOp
        @test tchk.name === nothing
    end

    @testset "CREATE TABLE - Basic Construction" begin
        # Empty table
        ct = CreateTable(:users)
        @test ct isa DDLStatement
        @test ct isa CreateTable
        @test ct.table == :users
        @test isempty(ct.columns)
        @test isempty(ct.constraints)
        @test ct.if_not_exists == false
        @test ct.temporary == false

        # With options
        ct2 = CreateTable(:temp_data, if_not_exists = true, temporary = true)
        @test ct2.if_not_exists == true
        @test ct2.temporary == true

        # Using create_table function
        ct3 = create_table(:products)
        @test ct3 isa CreateTable
        @test ct3.table == :products

        ct4 = create_table(:cache, temporary = true)
        @test ct4.temporary == true
    end

    @testset "CREATE TABLE - Pipeline API" begin
        # Single column
        ct = create_table(:users) |>
             add_column(:id, :integer, primary_key = true)

        @test ct isa CreateTable
        @test length(ct.columns) == 1
        @test ct.columns[1].name == :id
        @test ct.columns[1].type == :integer
        @test length(ct.columns[1].constraints) == 1
        @test ct.columns[1].constraints[1] isa PrimaryKeyConstraint

        # Multiple columns
        ct2 = create_table(:users) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:email, :text, nullable = false, unique = true) |>
              add_column(:created_at, :timestamp,
                         default = func(:CURRENT_TIMESTAMP, SQLExpr[]))

        @test length(ct2.columns) == 3

        # First column
        @test ct2.columns[1].name == :id
        @test ct2.columns[1].constraints[1] isa PrimaryKeyConstraint

        # Second column
        @test ct2.columns[2].name == :email
        @test length(ct2.columns[2].constraints) == 2
        @test any(c -> c isa NotNullConstraint, ct2.columns[2].constraints)
        @test any(c -> c isa UniqueConstraint, ct2.columns[2].constraints)

        # Third column
        @test ct2.columns[3].name == :created_at
        @test ct2.columns[3].type == :timestamp
        @test any(c -> c isa DefaultConstraint, ct2.columns[3].constraints)
    end

    @testset "CREATE TABLE - Column Options" begin
        ct = create_table(:users) |>
             add_column(:id, :integer, primary_key = true) |>
             add_column(:email, :text, nullable = false) |>
             add_column(:bio, :text, nullable = true) |>
             add_column(:status, :text, default = literal("active")) |>
             add_column(:parent_id, :integer, references = (:users, :id))

        # Check NOT NULL
        email_col = ct.columns[2]
        @test any(c -> c isa NotNullConstraint, email_col.constraints)

        # Check nullable=true (no NOT NULL constraint)
        bio_col = ct.columns[3]
        @test !any(c -> c isa NotNullConstraint, bio_col.constraints)

        # Check DEFAULT
        status_col = ct.columns[4]
        @test any(c -> c isa DefaultConstraint, status_col.constraints)

        # Check FOREIGN KEY
        parent_col = ct.columns[5]
        @test any(c -> c isa ForeignKeyConstraint, parent_col.constraints)
        fk = findfirst(c -> c isa ForeignKeyConstraint, parent_col.constraints)
        @test parent_col.constraints[fk].ref_table == :users
        @test parent_col.constraints[fk].ref_column == :id
    end

    @testset "CREATE TABLE - Extended Column Constraints" begin
        # Column-level CHECK constraint
        ct1 = create_table(:users) |>
              add_column(:age, :integer; check = col(:users, :age) >= literal(0))
        age_col = ct1.columns[1]
        @test any(c -> c isa CheckConstraint, age_col.constraints)
        chk = findfirst(c -> c isa CheckConstraint, age_col.constraints)
        @test age_col.constraints[chk].condition isa BinaryOp

        # AUTO_INCREMENT constraint
        ct2 = create_table(:users) |>
              add_column(:id, :integer; primary_key = true, auto_increment = true)
        id_col = ct2.columns[1]
        @test any(c -> c isa AutoIncrementConstraint, id_col.constraints)
        @test any(c -> c isa PrimaryKeyConstraint, id_col.constraints)

        # GENERATED column constraint
        ct3 = create_table(:users) |>
              add_column(:id, :integer) |>
              add_column(:full_name, :text;
                         generated = func(:concat,
                                          [col(:users, :first), literal(" "),
                                           col(:users, :last)]))
        gen_col = ct3.columns[2]
        @test any(c -> c isa GeneratedConstraint, gen_col.constraints)
        gen_idx = findfirst(c -> c isa GeneratedConstraint, gen_col.constraints)
        @test gen_col.constraints[gen_idx].stored == true

        # GENERATED VIRTUAL column
        ct4 = create_table(:users) |>
              add_column(:id, :integer) |>
              add_column(:computed, :integer; generated = col(:users, :id) * literal(2),
                         stored = false)
        comp_col = ct4.columns[2]
        gen_idx2 = findfirst(c -> c isa GeneratedConstraint, comp_col.constraints)
        @test comp_col.constraints[gen_idx2].stored == false

        # COLLATION constraint
        ct5 = create_table(:users) |>
              add_column(:email, :text; collation = :nocase)
        email_col = ct5.columns[1]
        @test any(c -> c isa CollationConstraint, email_col.constraints)
        coll_idx = findfirst(c -> c isa CollationConstraint, email_col.constraints)
        @test email_col.constraints[coll_idx].collation == :nocase

        # ON UPDATE constraint (MySQL-specific)
        ct6 = create_table(:users) |>
              add_column(:updated_at, :timestamp;
                         on_update = literal(:current_timestamp))
        upd_col = ct6.columns[1]
        @test any(c -> c isa OnUpdateConstraint, upd_col.constraints)

        # Comment constraint
        ct7 = create_table(:users) |>
              add_column(:id, :integer; comment = "Primary key")
        id_col2 = ct7.columns[1]
        @test any(c -> c isa CommentConstraint, id_col2.constraints)
        comm_idx = findfirst(c -> c isa CommentConstraint, id_col2.constraints)
        @test id_col2.constraints[comm_idx].comment == "Primary key"

        # IDENTITY constraint (PostgreSQL)
        ct8 = create_table(:users) |>
              add_column(:id, :integer; identity = true, identity_always = true,
                         identity_start = 1, identity_increment = 1)
        id_col3 = ct8.columns[1]
        @test any(c -> c isa IdentityConstraint, id_col3.constraints)
        ident_idx = findfirst(c -> c isa IdentityConstraint, id_col3.constraints)
        @test id_col3.constraints[ident_idx].always == true
        @test id_col3.constraints[ident_idx].start == 1
        @test id_col3.constraints[ident_idx].increment == 1

        # Multiple constraints combined
        ct9 = create_table(:users) |>
              add_column(:id, :integer; primary_key = true, auto_increment = true,
                         comment = "Auto-incrementing primary key")
        multi_col = ct9.columns[1]
        @test any(c -> c isa PrimaryKeyConstraint, multi_col.constraints)
        @test any(c -> c isa AutoIncrementConstraint, multi_col.constraints)
        @test any(c -> c isa CommentConstraint, multi_col.constraints)
    end

    @testset "CREATE TABLE - Table Constraints" begin
        # Add primary key
        ct1 = create_table(:users) |>
              add_column(:id, :integer) |>
              add_primary_key([:id])

        @test length(ct1.constraints) == 1
        @test ct1.constraints[1] isa TablePrimaryKey
        @test ct1.constraints[1].columns == [:id]

        # Composite primary key
        ct2 = create_table(:user_roles) |>
              add_column(:user_id, :integer) |>
              add_column(:role_id, :integer) |>
              add_primary_key([:user_id, :role_id])

        @test ct2.constraints[1].columns == [:user_id, :role_id]

        # Add foreign key
        ct3 = create_table(:posts) |>
              add_column(:id, :integer, primary_key = true) |>
              add_column(:user_id, :integer) |>
              add_foreign_key([:user_id], :users, [:id], on_delete = :cascade)

        @test length(ct3.constraints) == 1
        @test ct3.constraints[1] isa TableForeignKey
        @test ct3.constraints[1].on_delete == :cascade

        # Add unique constraint
        ct4 = create_table(:users) |>
              add_column(:email, :text) |>
              add_unique([:email])

        @test length(ct4.constraints) == 1
        @test ct4.constraints[1] isa TableUnique

        # Add check constraint
        ct5 = create_table(:users) |>
              add_column(:age, :integer) |>
              add_check(col(:users, :age) >= literal(18))

        @test length(ct5.constraints) == 1
        @test ct5.constraints[1] isa TableCheck
    end

    @testset "ALTER TABLE - Construction" begin
        # Empty alter table
        at = AlterTable(:users)
        @test at isa DDLStatement
        @test at isa AlterTable
        @test at.table == :users
        @test isempty(at.operations)

        # Using alter_table function
        at2 = alter_table(:products)
        @test at2 isa AlterTable
        @test at2.table == :products
    end

    @testset "ALTER TABLE - Pipeline API" begin
        # Add column
        at = alter_table(:users) |>
             add_alter_column(:age, :integer)

        @test length(at.operations) == 1
        @test at.operations[1] isa AddColumn
        @test at.operations[1].column.name == :age
        @test at.operations[1].column.type == :integer

        # Add column with constraints
        at2 = alter_table(:users) |>
              add_alter_column(:email_verified, :boolean, nullable = false,
                               default = literal(false))

        @test length(at2.operations) == 1
        col_def = at2.operations[1].column
        @test any(c -> c isa NotNullConstraint, col_def.constraints)
        @test any(c -> c isa DefaultConstraint, col_def.constraints)

        # Drop column
        at3 = alter_table(:users) |>
              drop_alter_column(:old_field)

        @test length(at3.operations) == 1
        @test at3.operations[1] isa DropColumn
        @test at3.operations[1].column == :old_field

        # Rename column
        at4 = alter_table(:users) |>
              rename_alter_column(:old_name, :new_name)

        @test length(at4.operations) == 1
        @test at4.operations[1] isa RenameColumn
        @test at4.operations[1].old_name == :old_name
        @test at4.operations[1].new_name == :new_name

        # Multiple operations
        at5 = alter_table(:users) |>
              add_alter_column(:age, :integer) |>
              drop_alter_column(:legacy_field) |>
              rename_alter_column(:old_email, :email)

        @test length(at5.operations) == 3
        @test at5.operations[1] isa AddColumn
        @test at5.operations[2] isa DropColumn
        @test at5.operations[3] isa RenameColumn
    end

    @testset "DROP TABLE" begin
        # Basic drop
        dt = drop_table(:users)
        @test dt isa DDLStatement
        @test dt isa DropTable
        @test dt.table == :users
        @test dt.if_exists == false
        @test dt.cascade == false

        # With options
        dt2 = drop_table(:users, if_exists = true)
        @test dt2.if_exists == true

        dt3 = drop_table(:users, cascade = true)
        @test dt3.cascade == true

        # Both options
        dt4 = drop_table(:users, if_exists = true, cascade = true)
        @test dt4.if_exists == true
        @test dt4.cascade == true
    end

    @testset "CREATE INDEX" begin
        # Basic index
        ci = create_index(:idx_users_email, :users, [:email])
        @test ci isa DDLStatement
        @test ci isa CreateIndex
        @test ci.name == :idx_users_email
        @test ci.table == :users
        @test ci.columns == [:email]
        @test ci.unique == false
        @test ci.if_not_exists == false
        @test ci.where === nothing

        # Single column convenience
        ci2 = create_index(:idx_users_id, :users, :id)
        @test ci2.columns == [:id]

        # Unique index
        ci3 = create_index(:idx_users_email, :users, [:email], unique = true)
        @test ci3.unique == true

        # With IF NOT EXISTS
        ci4 = create_index(:idx_users_email, :users, [:email], if_not_exists = true)
        @test ci4.if_not_exists == true

        # Partial index (with WHERE clause)
        ci5 = create_index(:idx_active_users, :users, [:id],
                           where = col(:users, :active) == literal(true))
        @test ci5.where !== nothing
        @test ci5.where isa BinaryOp

        # Composite index
        ci6 = create_index(:idx_user_email, :users, [:user_id, :email])
        @test ci6.columns == [:user_id, :email]
    end

    @testset "DROP INDEX" begin
        # Basic drop
        di = drop_index(:idx_users_email)
        @test di isa DDLStatement
        @test di isa DropIndex
        @test di.name == :idx_users_email
        @test di.if_exists == false

        # With IF EXISTS
        di2 = drop_index(:idx_users_email, if_exists = true)
        @test di2.if_exists == true
    end

    @testset "Complex Schema Example" begin
        # Build a complete schema with multiple tables
        users = create_table(:users, if_not_exists = true) |>
                add_column(:id, :integer, primary_key = true) |>
                add_column(:email, :text, nullable = false) |>
                add_column(:username, :text, nullable = false) |>
                add_column(:created_at, :timestamp,
                           default = func(:CURRENT_TIMESTAMP, SQLExpr[])) |>
                add_unique([:email]) |>
                add_unique([:username]) |>
                add_check(col(:users, :email) != literal(""), name = :email_not_empty)

        @test users.if_not_exists == true
        @test length(users.columns) == 4
        @test length(users.constraints) == 3  # 2 unique + 1 check

        posts = create_table(:posts) |>
                add_column(:id, :integer, primary_key = true) |>
                add_column(:user_id, :integer, nullable = false) |>
                add_column(:title, :text, nullable = false) |>
                add_column(:body, :text) |>
                add_column(:published, :boolean, default = literal(false)) |>
                add_foreign_key([:user_id], :users, [:id], on_delete = :cascade)

        @test length(posts.columns) == 5
        @test length(posts.constraints) == 1
        @test posts.constraints[1] isa TableForeignKey
        @test posts.constraints[1].on_delete == :cascade
    end

    @testset "Immutability" begin
        # CREATE TABLE should be immutable
        ct = create_table(:users)
        ct2 = add_column(ct, :id, :integer, primary_key = true)

        @test ct !== ct2
        @test isempty(ct.columns)
        @test length(ct2.columns) == 1

        # ALTER TABLE should be immutable
        at = alter_table(:users)
        at2 = add_alter_column(at, :age, :integer)

        @test at !== at2
        @test isempty(at.operations)
        @test length(at2.operations) == 1
    end
end
