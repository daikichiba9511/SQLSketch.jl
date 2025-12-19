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

    @testset "SQLite Dialect (Dialects.sqlite)" begin
        include("dialects/sqlite_test.jl")
    end

    @testset "SQLite Driver (Drivers.sqlite)" begin
        include("drivers/sqlite_test.jl")
    end

    @testset "CodecRegistry (Core.codec)" begin
        include("core/codec_test.jl")
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
end
