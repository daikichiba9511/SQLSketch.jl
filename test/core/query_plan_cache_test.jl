"""
Tests for Query Plan Cache (Phase 13.5)

This module tests AST-based query plan caching with LRU eviction.
"""

using Test
using SQLSketch
using SQLSketch.Core
using SQLSketch.Core.QueryPlanCache

# Resolve Base conflicts by using qualified names
const SQ = SQLSketch

@testset "Query Plan Cache" begin
    @testset "Basic cache operations" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        # Simple query
        query = from(:users) |> where(col(:users, :id) == param(Int, :id))

        # First compilation - cache miss
        sql1, params1 = compile_with_cache(cache, dialect, query)
        @test sql1 == "SELECT * FROM `users` WHERE (`users`.`id` = ?)"
        @test params1 == [:id]

        stats = cache_stats(cache)
        @test stats.hits == 0
        @test stats.misses == 1
        @test stats.size == 1
        @test stats.hit_rate == 0.0

        # Second compilation - cache hit
        sql2, params2 = compile_with_cache(cache, dialect, query)
        @test sql2 == sql1
        @test params2 == params1

        stats = cache_stats(cache)
        @test stats.hits == 1
        @test stats.misses == 1
        @test stats.size == 1
        @test stats.hit_rate == 0.5
    end

    @testset "Different queries cache separately" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        # Query 1
        q1 = from(:users) |> where(col(:users, :id) == param(Int, :id))
        sql1, _ = compile_with_cache(cache, dialect, q1)

        # Query 2 - different structure
        q2 = from(:users) |> where(col(:users, :email) == param(String, :email))
        sql2, _ = compile_with_cache(cache, dialect, q2)

        @test sql1 != sql2

        stats = cache_stats(cache)
        @test stats.misses == 2
        @test stats.size == 2
    end

    @testset "Same structure with different parameter values reuses cache" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        # Same query structure, different parameter names
        q1 = from(:users) |> where(col(:users, :id) == param(Int, :user_id))
        q2 = from(:users) |> where(col(:users, :id) == param(Int, :id))

        sql1, params1 = compile_with_cache(cache, dialect, q1)
        sql2, params2 = compile_with_cache(cache, dialect, q2)

        # Different parameter names mean different AST structure
        # So we expect 2 cache entries
        @test params1 == [:user_id]
        @test params2 == [:id]

        stats = cache_stats(cache)
        @test stats.misses == 2
        @test stats.size == 2
    end

    @testset "LRU eviction when cache is full" begin
        cache = QueryPlanCache(max_size = 3)
        dialect = SQLiteDialect()

        # Fill cache with 3 queries
        q1 = from(:users) |> where(col(:users, :id) == literal(1))
        q2 = from(:users) |> where(col(:users, :id) == literal(2))
        q3 = from(:users) |> where(col(:users, :id) == literal(3))

        compile_with_cache(cache, dialect, q1)
        compile_with_cache(cache, dialect, q2)
        compile_with_cache(cache, dialect, q3)

        @test cache_stats(cache).size == 3

        # Access q1 and q2 to make them more recently used than q3
        compile_with_cache(cache, dialect, q1)
        compile_with_cache(cache, dialect, q2)

        # Add a 4th query - should evict q3 (LRU)
        q4 = from(:users) |> where(col(:users, :id) == literal(4))
        compile_with_cache(cache, dialect, q4)

        @test cache_stats(cache).size == 3

        # q1 and q2 should still be in cache (cache hits)
        stats_before = cache_stats(cache)
        compile_with_cache(cache, dialect, q1)
        compile_with_cache(cache, dialect, q2)
        stats_after = cache_stats(cache)

        @test stats_after.hits == stats_before.hits + 2

        # q3 should have been evicted (cache miss)
        stats_before = cache_stats(cache)
        compile_with_cache(cache, dialect, q3)
        stats_after = cache_stats(cache)

        @test stats_after.misses == stats_before.misses + 1
    end

    @testset "Complex queries cache correctly" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        # Complex query with join
        query = from(:users) |>
                left_join(:posts, col(:users, :id) == col(:posts, :user_id)) |>
                where(col(:posts, :published) == literal(true)) |>
                select(NamedTuple, col(:users, :name), col(:posts, :title)) |>
                order_by(col(:posts, :created_at); desc = true) |>
                limit(10)

        # First compilation
        sql1, params1 = compile_with_cache(cache, dialect, query)

        # Second compilation - cache hit
        sql2, params2 = compile_with_cache(cache, dialect, query)

        @test sql1 == sql2
        @test params1 == params2

        stats = cache_stats(cache)
        @test stats.hits == 1
        @test stats.misses == 1
    end

    @testset "CTE queries cache correctly" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        # Query with CTE
        active_users = cte(:active_users,
                           from(:users) |> where(col(:users, :active) == literal(true)))

        query = with([active_users], from(:active_users))

        # First compilation
        sql1, params1 = compile_with_cache(cache, dialect, query)

        # Second compilation - cache hit
        sql2, params2 = compile_with_cache(cache, dialect, query)

        @test sql1 == sql2

        stats = cache_stats(cache)
        @test stats.hits == 1
        @test stats.misses == 1
    end

    @testset "clear_cache! resets everything" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        # Add some queries
        q1 = from(:users)
        q2 = from(:posts)

        compile_with_cache(cache, dialect, q1)
        compile_with_cache(cache, dialect, q2)

        @test cache_stats(cache).size == 2

        # Clear cache
        clear_cache!(cache)

        stats = cache_stats(cache)
        @test stats.size == 0
        @test stats.hits == 0
        @test stats.misses == 0
        @test stats.hit_rate == 0.0

        # Queries should be cache misses again
        compile_with_cache(cache, dialect, q1)
        @test cache_stats(cache).misses == 1
    end

    @testset "Cache key generation for different query types" begin
        cache = QueryPlanCache(max_size = 20)
        dialect = SQLiteDialect()

        # SELECT query
        q_select = from(:users) |> select(NamedTuple, col(:users, :id))
        compile_with_cache(cache, dialect, q_select)

        # INSERT query
        q_insert = insert_into(:users, [:email]) |> insert_values([[param(String, :email)]])
        compile_with_cache(cache, dialect, q_insert)

        # UPDATE query
        q_update = update(:users) |> set_values(:email => param(String, :email)) |>
                   where(col(:users, :id) == param(Int, :id))
        compile_with_cache(cache, dialect, q_update)

        # DELETE query
        q_delete = delete_from(:users) |> where(col(:users, :id) == param(Int, :id))
        compile_with_cache(cache, dialect, q_delete)

        # All should cache separately
        stats = cache_stats(cache)
        @test stats.size == 4
        @test stats.misses == 4
    end

    @testset "Thread safety (basic test)" begin
        cache = QueryPlanCache(max_size = 100)
        dialect = SQLiteDialect()

        # Create multiple queries
        queries = [from(:users) |> where(col(:users, :id) == literal(i))
                   for i in 1:10]

        # Access cache from multiple tasks concurrently
        tasks = [Threads.@spawn begin
                     for query in queries
                         compile_with_cache(cache, dialect, query)
                     end
                 end
                 for _ in 1:4]

        # Wait for all tasks
        for task in tasks
            wait(task)
        end

        # Cache should still be consistent
        stats = cache_stats(cache)
        @test stats.size <= 10
        @test stats.hits + stats.misses == 40  # 10 queries * 4 threads
    end

    @testset "Hit rate calculation" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        q = from(:users)

        # 1 miss
        compile_with_cache(cache, dialect, q)
        @test cache_stats(cache).hit_rate == 0.0

        # 9 hits
        for _ in 1:9
            compile_with_cache(cache, dialect, q)
        end

        @test cache_stats(cache).hit_rate == 0.9
    end

    @testset "Cache with window functions" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        query = from(:employees) |>
                select(NamedTuple,
                       col(:employees, :name),
                       row_number(over(partition_by = [col(:employees, :department)])))

        sql1, _ = compile_with_cache(cache, dialect, query)
        sql2, _ = compile_with_cache(cache, dialect, query)

        @test sql1 == sql2
        @test cache_stats(cache).hits == 1
    end

    @testset "Cache with set operations" begin
        cache = QueryPlanCache(max_size = 10)
        dialect = SQLiteDialect()

        q1 = from(:users) |> select(NamedTuple, col(:users, :email))
        q2 = from(:legacy_users) |> select(NamedTuple, col(:legacy_users, :email))
        query = SQ.Core.union_distinct(q1, q2)

        sql1, _ = compile_with_cache(cache, dialect, query)
        sql2, _ = compile_with_cache(cache, dialect, query)

        @test sql1 == sql2
        @test cache_stats(cache).hits == 1
    end
end
