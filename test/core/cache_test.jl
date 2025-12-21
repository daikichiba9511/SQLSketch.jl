# Tests for PreparedStatementCache (Core/cache.jl)

using Test
using SQLSketch

# Access internal APIs for testing
using SQLSketch.Core: PreparedStatementCache, hash_query, get_cached, put_cached!
using SQLSketch.Core: clear_cache!, cache_stats, cache_size

@testset "PreparedStatementCache" begin
    @testset "Cache creation and basic operations" begin
        cache = PreparedStatementCache(; max_size = 3)
        @test cache_size(cache) == 0
        @test cache.max_size == 3

        # Test hash_query
        q1 = from(:users) |> where(col(:users, :active) == literal(1))
        q2 = from(:posts) |> where(col(:posts, :published) == literal(1))
        q3 = from(:users) |> where(col(:users, :active) == literal(1))  # Same as q1

        hash1 = hash_query(q1)
        hash2 = hash_query(q2)
        hash3 = hash_query(q3)

        @test hash1 == hash3  # Identical queries have same hash
        @test hash1 != hash2  # Different queries have different hashes
    end

    @testset "Cache operations" begin
        cache = PreparedStatementCache(; max_size = 3)

        # Put and get
        put_cached!(cache, UInt64(1), "stmt1", "SELECT 1")
        put_cached!(cache, UInt64(2), "stmt2", "SELECT 2")

        @test cache_size(cache) == 2

        entry1 = get_cached(cache, UInt64(1))
        @test entry1 !== nothing
        @test entry1.sql == "SELECT 1"
        @test entry1.statement == "stmt1"

        # Cache miss
        entry_miss = get_cached(cache, UInt64(999))
        @test entry_miss === nothing

        # Stats
        stats = cache_stats(cache)
        @test stats.hits == 1
        @test stats.misses == 1
        @test stats.evictions == 0
    end

    @testset "LRU eviction" begin
        cache = PreparedStatementCache(; max_size = 3)

        # Fill cache
        put_cached!(cache, UInt64(1), "stmt1", "SELECT 1")
        put_cached!(cache, UInt64(2), "stmt2", "SELECT 2")
        put_cached!(cache, UInt64(3), "stmt3", "SELECT 3")
        @test cache_size(cache) == 3

        # Access entry 1 to make it recently used
        get_cached(cache, UInt64(1))

        # Add 4th entry - should evict key 2 (least recently used)
        put_cached!(cache, UInt64(4), "stmt4", "SELECT 4")
        @test cache_size(cache) == 3

        # Verify key 2 was evicted
        @test get_cached(cache, UInt64(2)) === nothing

        # Verify key 1 is still there (recently used)
        @test get_cached(cache, UInt64(1)) !== nothing

        # Check eviction count
        stats = cache_stats(cache)
        @test stats.evictions == 1
    end

    @testset "Clear cache" begin
        cache = PreparedStatementCache(; max_size = 10)

        put_cached!(cache, UInt64(1), "stmt1", "SELECT 1")
        put_cached!(cache, UInt64(2), "stmt2", "SELECT 2")
        @test cache_size(cache) == 2

        clear_cache!(cache)
        @test cache_size(cache) == 0
        @test get_cached(cache, UInt64(1)) === nothing
    end

    @testset "Thread safety (basic)" begin
        cache = PreparedStatementCache(; max_size = 100)

        # Concurrent access from multiple "threads" (simulated with tasks)
        tasks = Task[]
        for i in 1:10
            task = @async begin
                for j in 1:10
                    key = UInt64(i * 10 + j)
                    put_cached!(cache, key, "stmt_$key", "SELECT $key")
                    get_cached(cache, key)
                end
            end
            push!(tasks, task)
        end

        # Wait for all tasks
        for task in tasks
            wait(task)
        end

        # All operations should complete without error
        @test cache_size(cache) <= 100
    end
end
