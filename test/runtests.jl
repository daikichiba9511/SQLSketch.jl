"""
# SQLSketch Test Suite

Main test runner for SQLSketch.jl
"""

using Test

@testset verbose = true "SQLSketch.jl" begin
    @testset "Expression AST (Core.expr)" begin
        include("core/expr_test.jl")
    end

    @testset "Query AST (Core.query)" begin
        include("core/query_test.jl")
    end

    @testset "Window Functions (Core.window)" begin
        include("core/window_test.jl")
    end

    @testset "Set Operations (Core.set_operations)" begin
        include("core/set_operations_test.jl")
    end

    @testset "UPSERT / ON CONFLICT (Core.upsert)" begin
        include("core/upsert_test.jl")
    end

    @testset "SQLite Dialect (Dialects.sqlite)" begin
        include("dialects/sqlite_test.jl")
    end

    @testset "PostgreSQL Dialect (Dialects.postgresql)" begin
        include("dialects/postgresql_test.jl")
    end

    @testset "MySQL Dialect (Dialects.mysql)" begin
        include("dialects/mysql_test.jl")
    end

    @testset "SQLite Driver (Drivers.sqlite)" begin
        include("drivers/sqlite_test.jl")
    end

    @testset "CodecRegistry (Core.codec)" begin
        include("core/codec_test.jl")
    end

    @testset "Metadata API (Core.metadata)" begin
        include("core/metadata_test.jl")
    end

    @testset "End-to-End Integration (integration)" begin
        include("integration/end_to_end_test.jl")
    end

    @testset "Transaction Management (Core.transaction)" begin
        include("core/transaction_test.jl")
    end

    @testset "Migration Runner (Core.migrations)" begin
        include("core/migrations_test.jl")
    end

    @testset "DDL (Core.ddl)" begin
        include("core/ddl_test.jl")
    end

    @testset "Connection Pool (Core.pool)" begin
        include("core/pool_test.jl")
    end

    @testset "Batch Operations (Core.batch)" begin
        include("core/batch_test.jl")
    end
end
