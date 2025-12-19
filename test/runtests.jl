"""
# SQLSketch Test Suite

Main test runner for SQLSketch.jl
"""

using Test

@testset "SQLSketch.jl" begin
    # Phase 1: Expression AST
    include("core/expr_test.jl")

    # Phase 2: Query AST
    include("core/query_test.jl")

    # Phase 3: Dialects
    include("dialects/sqlite_test.jl")

    # Phase 4: Drivers
    include("drivers/sqlite_test.jl")

    # Phase 5: Codecs
    include("core/codec_test.jl")

    # Phase 6: End-to-end Integration
    # include("integration/end_to_end_test.jl")

    # Phase 7: Transactions
    # include("core/transaction_test.jl")

    # Phase 8: Migrations
    # include("core/migrations_test.jl")
end
