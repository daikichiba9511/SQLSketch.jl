"""
# UPSERT (ON CONFLICT) Tests

Test suite for UPSERT/ON CONFLICT functionality.
"""

using Test
using SQLSketch
using SQLSketch.Core
using SQLSketch.Core: insert_values  # Avoid conflict with Base.values

@testset "ON CONFLICT DO NOTHING - AST Construction" begin
    # Basic ON CONFLICT DO NOTHING
    base_insert = insert_into(:users, [:id, :email, :name]) |>
                  insert_values([[literal(1), literal("alice@example.com"), literal("Alice")]])

    upsert = base_insert |> on_conflict_do_nothing()

    @test upsert isa OnConflict{NamedTuple}
    @test upsert.source == base_insert
    @test upsert.target === nothing
    @test upsert.action == :DO_NOTHING
    @test isempty(upsert.updates)
    @test upsert.where_clause === nothing

    # ON CONFLICT with specific columns
    upsert_cols = base_insert |> on_conflict_do_nothing([:email])

    @test upsert_cols isa OnConflict{NamedTuple}
    @test upsert_cols.target == [:email]
    @test upsert_cols.action == :DO_NOTHING

    # ON CONFLICT with multiple target columns
    upsert_multi = base_insert |> on_conflict_do_nothing([:email, :name])

    @test upsert_multi.target == [:email, :name]
end

@testset "ON CONFLICT DO UPDATE - AST Construction" begin
    base_insert = insert_into(:users, [:id, :email, :name]) |>
                  insert_values([[literal(1), literal("alice@example.com"), literal("Alice")]])

    # Basic ON CONFLICT DO UPDATE
    upsert = base_insert |>
             on_conflict_do_update([:email],
                                   :name => col(:excluded, :name))

    @test upsert isa OnConflict{NamedTuple}
    @test upsert.source == base_insert
    @test upsert.target == [:email]
    @test upsert.action == :DO_UPDATE
    @test length(upsert.updates) == 1
    @test upsert.updates[1][1] == :name
    @test upsert.updates[1][2] isa ColRef
    @test upsert.updates[1][2].table == :excluded
    @test upsert.updates[1][2].column == :name
    @test upsert.where_clause === nothing

    # Multiple update columns
    upsert_multi = base_insert |>
                   on_conflict_do_update([:email],
                                         :name => col(:excluded, :name),
                                         :updated_at => func(:NOW, SQLExpr[]))

    @test length(upsert_multi.updates) == 2
    @test upsert_multi.updates[1][1] == :name
    @test upsert_multi.updates[1][2] isa ColRef
    @test upsert_multi.updates[1][2].table == :excluded
    @test upsert_multi.updates[1][2].column == :name
    @test upsert_multi.updates[2][1] == :updated_at
    @test upsert_multi.updates[2][2] isa FuncCall
    @test upsert_multi.updates[2][2].name == :NOW

    # With WHERE clause
    upsert_where = base_insert |>
                   on_conflict_do_update([:email],
                                         :name => col(:excluded, :name);
                                         where = col(:users, :version) <
                                                 col(:excluded, :version))

    @test upsert_where.where_clause isa BinaryOp
    @test upsert_where.where_clause.op == :(<)
end

@testset "ON CONFLICT - Explicit Function Calls" begin
    base_insert = insert_into(:users, [:id, :email, :name]) |>
                  insert_values([[literal(1), literal("alice@example.com"), literal("Alice")]])

    # Explicit on_conflict_do_nothing
    upsert1 = on_conflict_do_nothing(base_insert)
    @test upsert1 isa OnConflict{NamedTuple}
    @test upsert1.action == :DO_NOTHING

    upsert2 = on_conflict_do_nothing(base_insert; target = [:email])
    @test upsert2.target == [:email]

    # Explicit on_conflict_do_update
    upsert3 = on_conflict_do_update(base_insert,
                                    [:email],
                                    :name => col(:excluded, :name))
    @test upsert3 isa OnConflict{NamedTuple}
    @test upsert3.action == :DO_UPDATE
    @test length(upsert3.updates) == 1

    # With WHERE clause
    upsert4 = on_conflict_do_update(base_insert,
                                    [:email],
                                    :name => col(:excluded, :name);
                                    where = col(:users, :active) == literal(true))
    @test upsert4.where_clause isa BinaryOp
    @test upsert4.where_clause.op == :(=)
end

@testset "ON CONFLICT - Structural Equality" begin
    base_insert = insert_into(:users, [:id, :email]) |>
                  insert_values([[param(Int, :id), param(String, :email)]])

    # Same ON CONFLICT DO NOTHING queries have same structure
    upsert1 = base_insert |> on_conflict_do_nothing()
    upsert2 = base_insert |> on_conflict_do_nothing()
    @test upsert1.action == upsert2.action
    @test upsert1.target == upsert2.target

    # Same target columns have same structure
    upsert3 = base_insert |> on_conflict_do_nothing([:email])
    upsert4 = base_insert |> on_conflict_do_nothing([:email])
    @test upsert3.target == upsert4.target

    # Different targets have different structure
    upsert5 = base_insert |> on_conflict_do_nothing([:id])
    @test upsert3.target != upsert5.target

    # Same DO UPDATE queries have same structure
    upsert6 = base_insert |> on_conflict_do_update([:email], :id => col(:excluded, :id))
    upsert7 = base_insert |> on_conflict_do_update([:email], :id => col(:excluded, :id))
    @test upsert6.action == upsert7.action
    @test upsert6.target == upsert7.target
    @test length(upsert6.updates) == length(upsert7.updates)

    # Different updates have different structure
    upsert8 = base_insert |> on_conflict_do_update([:email], :id => literal(999))
    @test upsert6.updates[1][2] isa ColRef
    @test upsert8.updates[1][2] isa Literal
end

@testset "ON CONFLICT - Edge Cases" begin
    base_insert = insert_into(:users, [:id, :email, :name]) |>
                  insert_values([[literal(1), literal("alice@example.com"), literal("Alice")]])

    # Empty target columns (conflict on any constraint)
    upsert_empty = on_conflict_do_nothing(base_insert; target = Symbol[])
    @test upsert_empty.target == Symbol[]

    # Single column update
    upsert_single = base_insert |>
                    on_conflict_do_update([:email], :name => col(:excluded, :name))
    @test length(upsert_single.updates) == 1

    # Update with literal value
    upsert_literal = base_insert |>
                     on_conflict_do_update([:email], :active => literal(true))
    @test upsert_literal.updates[1][1] == :active
    @test upsert_literal.updates[1][2] isa Literal

    # Update with function call
    upsert_func = base_insert |>
                  on_conflict_do_update([:email],
                                        :updated_at => func(:CURRENT_TIMESTAMP, SQLExpr[]))
    @test upsert_func.updates[1][1] == :updated_at
    @test upsert_func.updates[1][2] isa FuncCall

    # Update with binary operation
    upsert_binop = base_insert |>
                   on_conflict_do_update([:email],
                                         :login_count => col(:users, :login_count) +
                                                         literal(1))
    @test upsert_binop.updates[1][1] == :login_count
    @test upsert_binop.updates[1][2] isa BinaryOp
end

@testset "ON CONFLICT - Type Preservation" begin
    # Type should be preserved through ON CONFLICT
    base_insert = insert_into(:users, [:id, :email, :name]) |>
                  insert_values([[literal(1), literal("alice@example.com"), literal("Alice")]])

    upsert = base_insert |> on_conflict_do_nothing()

    @test upsert isa OnConflict{NamedTuple}
    @test typeof(upsert).parameters[1] == NamedTuple

    # Even with DO UPDATE
    upsert_update = base_insert |>
                    on_conflict_do_update([:email], :name => col(:excluded, :name))

    @test upsert_update isa OnConflict{NamedTuple}
    @test typeof(upsert_update).parameters[1] == NamedTuple
end

# =============================================================================
# SQLite Dialect Compilation Tests
# =============================================================================

@testset "SQLite - ON CONFLICT DO NOTHING Compilation" begin
    dialect = SQLiteDialect()

    # Basic ON CONFLICT DO NOTHING
    q = insert_into(:users, [:id, :email]) |>
        insert_values([[param(Int, :id), param(String, :email)]]) |>
        on_conflict_do_nothing()

    sql, params = compile(dialect, q)
    @test sql == "INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT DO NOTHING"
    @test params == [:id, :email]

    # With specific conflict columns
    q2 = insert_into(:users, [:id, :email]) |>
         insert_values([[param(Int, :id), param(String, :email)]]) |>
         on_conflict_do_nothing([:email])

    sql2, params2 = compile(dialect, q2)
    @test sql2 ==
          "INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT (`email`) DO NOTHING"
    @test params2 == [:id, :email]

    # Multiple conflict columns
    q3 = insert_into(:users, [:id, :email, :name]) |>
         insert_values([[param(Int, :id), param(String, :email), param(String, :name)]]) |>
         on_conflict_do_nothing([:email, :name])

    sql3, params3 = compile(dialect, q3)
    @test sql3 ==
          "INSERT INTO `users` (`id`, `email`, `name`) VALUES (?, ?, ?) ON CONFLICT (`email`, `name`) DO NOTHING"
    @test params3 == [:id, :email, :name]
end

@testset "SQLite - ON CONFLICT DO UPDATE Compilation" begin
    dialect = SQLiteDialect()

    # Basic DO UPDATE with single column
    q = insert_into(:users, [:id, :email, :name]) |>
        insert_values([[param(Int, :id), param(String, :email), param(String, :name)]]) |>
        on_conflict_do_update([:email],
                              :name => col(:excluded, :name))

    sql, params = compile(dialect, q)
    @test sql ==
          "INSERT INTO `users` (`id`, `email`, `name`) VALUES (?, ?, ?) ON CONFLICT (`email`) DO UPDATE SET `name` = `excluded`.`name`"
    @test params == [:id, :email, :name]

    # Multiple update columns
    q2 = insert_into(:users, [:id, :email, :name, :active]) |>
         insert_values([[param(Int, :id), param(String, :email), param(String, :name),
                  param(Bool, :active)]]) |>
         on_conflict_do_update([:email],
                               :name => col(:excluded, :name),
                               :active => col(:excluded, :active))

    sql2, params2 = compile(dialect, q2)
    @test sql2 ==
          "INSERT INTO `users` (`id`, `email`, `name`, `active`) VALUES (?, ?, ?, ?) ON CONFLICT (`email`) DO UPDATE SET `name` = `excluded`.`name`, `active` = `excluded`.`active`"
    @test params2 == [:id, :email, :name, :active]

    # Update with literal value
    q3 = insert_into(:users, [:id, :email]) |>
         insert_values([[param(Int, :id), param(String, :email)]]) |>
         on_conflict_do_update([:email],
                               :active => literal(true))

    sql3, params3 = compile(dialect, q3)
    @test sql3 ==
          "INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT (`email`) DO UPDATE SET `active` = 1"
    @test params3 == [:id, :email]

    # Update with function call
    q4 = insert_into(:users, [:id, :email]) |>
         insert_values([[param(Int, :id), param(String, :email)]]) |>
         on_conflict_do_update([:email],
                               :updated_at => func(:CURRENT_TIMESTAMP, SQLExpr[]))

    sql4, params4 = compile(dialect, q4)
    @test sql4 ==
          "INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT (`email`) DO UPDATE SET `updated_at` = CURRENT_TIMESTAMP()"
    @test params4 == [:id, :email]

    # Update with binary operation
    q5 = insert_into(:users, [:id, :email, :login_count]) |>
         insert_values([[param(Int, :id), param(String, :email), param(Int, :login_count)]]) |>
         on_conflict_do_update([:email],
                               :login_count => col(:users, :login_count) + literal(1))

    sql5, params5 = compile(dialect, q5)
    @test sql5 ==
          "INSERT INTO `users` (`id`, `email`, `login_count`) VALUES (?, ?, ?) ON CONFLICT (`email`) DO UPDATE SET `login_count` = (`users`.`login_count` + 1)"
    @test params5 == [:id, :email, :login_count]
end

@testset "SQLite - ON CONFLICT with WHERE Clause" begin
    dialect = SQLiteDialect()

    # DO UPDATE with WHERE clause
    q = insert_into(:users, [:id, :email, :name, :version]) |>
        insert_values([[param(Int, :id), param(String, :email), param(String, :name),
                 param(Int, :version)]]) |>
        on_conflict_do_update([:email],
                              :name => col(:excluded, :name);
                              where = col(:users, :version) < col(:excluded, :version))

    sql, params = compile(dialect, q)
    @test sql ==
          "INSERT INTO `users` (`id`, `email`, `name`, `version`) VALUES (?, ?, ?, ?) ON CONFLICT (`email`) DO UPDATE SET `name` = `excluded`.`name` WHERE (`users`.`version` < `excluded`.`version`)"
    @test params == [:id, :email, :name, :version]

    # WHERE with literal comparison
    q2 = insert_into(:users, [:id, :email, :active]) |>
         insert_values([[param(Int, :id), param(String, :email), param(Bool, :active)]]) |>
         on_conflict_do_update([:email],
                               :active => col(:excluded, :active);
                               where = col(:users, :active) == literal(false))

    sql2, params2 = compile(dialect, q2)
    @test sql2 ==
          "INSERT INTO `users` (`id`, `email`, `active`) VALUES (?, ?, ?) ON CONFLICT (`email`) DO UPDATE SET `active` = `excluded`.`active` WHERE (`users`.`active` = 0)"
    @test params2 == [:id, :email, :active]
end

@testset "SQLite - ON CONFLICT Edge Cases" begin
    dialect = SQLiteDialect()

    # No target columns (conflict on any constraint)
    q1 = insert_into(:users, [:id, :email]) |>
         insert_values([[param(Int, :id), param(String, :email)]]) |>
         on_conflict_do_nothing(Symbol[])

    sql1, params1 = compile(dialect, q1)
    @test sql1 == "INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT DO NOTHING"

    # ON CONFLICT with nothing target (same as empty)
    q2 = insert_into(:users, [:id, :email]) |>
         insert_values([[param(Int, :id), param(String, :email)]]) |>
         on_conflict_do_nothing()

    sql2, params2 = compile(dialect, q2)
    @test sql2 == "INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT DO NOTHING"

    # Single target column
    q3 = insert_into(:users, [:id, :email]) |>
         insert_values([[param(Int, :id), param(String, :email)]]) |>
         on_conflict_do_nothing([:id])

    sql3, params3 = compile(dialect, q3)
    @test sql3 ==
          "INSERT INTO `users` (`id`, `email`) VALUES (?, ?) ON CONFLICT (`id`) DO NOTHING"
end

@testset "SQLite - ON CONFLICT with Parameters" begin
    dialect = SQLiteDialect()

    # ON CONFLICT with parameter values
    q = insert_into(:users, [:id, :email, :name]) |>
        insert_values([[param(Int, :user_id), param(String, :user_email),
                 param(String, :user_name)]]) |>
        on_conflict_do_update([:email],
                              :name => param(String, :new_name))

    sql, params = compile(dialect, q)
    @test sql ==
          "INSERT INTO `users` (`id`, `email`, `name`) VALUES (?, ?, ?) ON CONFLICT (`email`) DO UPDATE SET `name` = ?"
    @test params == [:user_id, :user_email, :user_name, :new_name]

    # Mixed literals and parameters
    q2 = insert_into(:users, [:id, :email, :active]) |>
         insert_values([[param(Int, :user_id), param(String, :user_email), literal(true)]]) |>
         on_conflict_do_update([:email],
                               :active => literal(true),
                               :updated_at => func(:CURRENT_TIMESTAMP, SQLExpr[]))

    sql2, params2 = compile(dialect, q2)
    @test sql2 ==
          "INSERT INTO `users` (`id`, `email`, `active`) VALUES (?, ?, 1) ON CONFLICT (`email`) DO UPDATE SET `active` = 1, `updated_at` = CURRENT_TIMESTAMP()"
    @test params2 == [:user_id, :user_email]
end
