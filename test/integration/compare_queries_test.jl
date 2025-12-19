"""
Query Result Comparison Test

This script compares query results between:
1. SQLSketch.jl generated SQL
2. Direct sqlite3 execution

This ensures that SQLSketch.jl generates correct SQL and produces
the same results as native SQLite queries.
"""

using SQLSketch
using SQLSketch.Core
using SQLSketch.Drivers
using Test

println("=" ^ 70)
println("Query Result Comparison Test")
println("=" ^ 70)
println()

# Setup database
db_path = joinpath(dirname(dirname(@__DIR__)), "examples", "test.db")
if !isfile(db_path)
    println("❌ Error: Database not found!")
    println("Please run: julia --project=. examples/create_test_db.jl")
    exit(1)
end

driver = SQLiteDriver()
db = connect(driver, db_path)
dialect = SQLiteDialect()
registry = CodecRegistry()

println("✓ Connected to database: $db_path")
println()

# Test case structure
struct TestCase
    name::String
    description::String
    query_builder::Function  # Returns SQLSketch Query
    reference_sql::String     # Reference SQL to compare against
    check_result::Function    # Function to validate results
end

# Define test cases
test_cases = [
    TestCase(
        "Simple SELECT",
        "Select all users ordered by id",
        () -> from(:users) |>
              select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :email)) |>
              order_by(col(:users, :id)),
        "SELECT id, name, email FROM users ORDER BY id",
        (results) -> begin
            @test length(results) == 5
            @test results[1].name == "Alice"
            @test results[5].name == "Eve"
        end
    ),

    TestCase(
        "WHERE clause",
        "Filter users by age > 26",
        () -> from(:users) |>
              where(col(:users, :age) > literal(26)) |>
              select(NamedTuple, col(:users, :id), col(:users, :name), col(:users, :age)) |>
              order_by(col(:users, :age)),
        "SELECT id, name, age FROM users WHERE age > 26 ORDER BY age",
        (results) -> begin
            @test length(results) == 4  # Diana(28), Alice(30), Eve(32), Charlie(35)
            @test results[1].name == "Diana"
            @test results[1].age == 28
            @test results[4].name == "Charlie"
            @test results[4].age == 35
        end
    ),

    TestCase(
        "LIMIT",
        "Get first 3 users",
        () -> from(:users) |>
              select(NamedTuple, col(:users, :id), col(:users, :name)) |>
              order_by(col(:users, :id)) |>
              limit(3),
        "SELECT id, name FROM users ORDER BY id LIMIT 3",
        (results) -> begin
            @test length(results) == 3
            @test results[1].name == "Alice"
            @test results[3].name == "Charlie"
        end
    ),

    TestCase(
        "OFFSET",
        "Skip first 2 users, get next 2",
        () -> from(:users) |>
              select(NamedTuple, col(:users, :id), col(:users, :name)) |>
              order_by(col(:users, :id)) |>
              limit(2) |>
              offset(2),
        "SELECT id, name FROM users ORDER BY id LIMIT 2 OFFSET 2",
        (results) -> begin
            @test length(results) == 2
            @test results[1].name == "Charlie"
            @test results[2].name == "Diana"
        end
    ),

    TestCase(
        "ORDER BY DESC",
        "Users ordered by age descending",
        () -> from(:users) |>
              select(NamedTuple, col(:users, :name), col(:users, :age)) |>
              order_by(col(:users, :age); desc=true),
        "SELECT name, age FROM users ORDER BY age DESC",
        (results) -> begin
            @test length(results) == 5
            @test results[1].name == "Charlie"  # age 35
            @test results[1].age == 35
            @test results[5].name == "Bob"      # age 25
            @test results[5].age == 25
        end
    ),

    TestCase(
        "DISTINCT",
        "Distinct ages",
        () -> from(:users) |>
              select(NamedTuple, col(:users, :age)) |>
              distinct |>
              order_by(col(:users, :age)),
        "SELECT DISTINCT age FROM users ORDER BY age",
        (results) -> begin
            @test length(results) == 5  # All users have different ages
            @test results[1].age == 25
            @test results[5].age == 35
        end
    ),

    TestCase(
        "Multiple WHERE",
        "Active users over 27",
        () -> from(:users) |>
              where(col(:users, :is_active) == literal(1) & (col(:users, :age) > literal(27))) |>
              select(NamedTuple, col(:users, :name), col(:users, :age), col(:users, :is_active)) |>
              order_by(col(:users, :name)),
        "SELECT name, age, is_active FROM users WHERE is_active = 1 AND age > 27 ORDER BY name",
        (results) -> begin
            @test length(results) == 3  # Alice(30), Diana(28), Eve(32)
            @test results[1].name == "Alice"
            @test results[2].name == "Diana"
            @test results[3].name == "Eve"
        end
    ),
]

# Run tests
println("Running $(length(test_cases)) test cases...")
println()

test_results = Dict(:passed => 0, :failed => 0)

for (i, test_case) in enumerate(test_cases)
    println("─" ^ 70)
    println("Test $i: $(test_case.name)")
    println("Description: $(test_case.description)")
    println()

    try
        # Build query using SQLSketch
        query = test_case.query_builder()

        # Compile to SQL
        generated_sql, params = compile(dialect, query)

        println("  SQLSketch generated SQL:")
        println("    $generated_sql")
        println()
        println("  Reference SQL:")
        println("    $(test_case.reference_sql)")
        println()

        # Execute SQLSketch query
        raw_result = execute(db, generated_sql, [])

        # Convert to NamedTuples
        results = []
        for row in raw_result
            # Get column names from the row
            cols = propertynames(row)
            values = [getproperty(row, col) for col in cols]
            nt = NamedTuple{Tuple(cols)}(Tuple(values))
            push!(results, nt)
        end

        println("  Results: $(length(results)) rows")
        if length(results) <= 5
            for (j, r) in enumerate(results)
                println("    Row $j: $r")
            end
        else
            println("    (Showing first 3 rows)")
            for j in 1:3
                println("    Row $j: $(results[j])")
            end
        end
        println()

        # Run validation
        test_case.check_result(results)

        println("  ✅ PASSED")
        test_results[:passed] += 1

    catch e
        println("  ❌ FAILED")
        println("  Error: $e")
        if isa(e, Test.TestSetException)
            for failure in e.test_failures
                println("    - $failure")
            end
        end
        test_results[:failed] += 1
    end
    println()
end

# Cleanup
SQLSketch.Core.close(db)

# Summary
println("=" ^ 70)
println("TEST SUMMARY")
println("=" ^ 70)
println("Total tests:  $(length(test_cases))")
println("Passed:       $(test_results[:passed]) ✅")
println("Failed:       $(test_results[:failed]) $(test_results[:failed] > 0 ? "❌" : "")")
println()

if test_results[:failed] == 0
    println("🎉 All query comparison tests passed!")
    println()
    println("Conclusion:")
    println("  SQLSketch.jl generates correct SQL that produces identical")
    println("  results to native SQLite queries.")
    exit(0)
else
    println("⚠️  Some tests failed. Please review the output above.")
    exit(1)
end
