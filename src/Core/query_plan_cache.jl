#
# Query Plan Caching
#
# Cache compiled SQL queries based on AST structure to avoid repeated compilation.
#
# This module provides:
# - AST-based cache key generation
# - LRU eviction policy
# - Thread-safe cache access
# - Integration with the compilation pipeline
#
module QueryPlanCache

# Import from parent Core module
import ..Query, ..Dialect, ..compile
using Base: @lock

export QueryPlanCache, compile_with_cache, clear_cache!, cache_stats

"""
    CacheEntry

Stores a compiled query plan with metadata.
"""
struct CacheEntry
    sql::String
    param_order::Vector{Symbol}
    last_used::Float64  # Timestamp for LRU eviction
end

"""
    QueryPlanCache

Thread-safe LRU cache for compiled query plans.

# Fields
- `max_size::Int`: Maximum number of cached plans
- `cache::Dict{UInt64, CacheEntry}`: Cache storage (keyed by AST hash)
- `hits::Ref{Int}`: Cache hit counter
- `misses::Ref{Int}`: Cache miss counter
- `lock::ReentrantLock`: Thread safety lock

# Example

```julia
cache = QueryPlanCache(max_size=100)
sql, params = compile_with_cache(cache, dialect, query)
```
"""
mutable struct QueryPlanCache
    max_size::Int
    cache::Dict{UInt64, CacheEntry}
    hits::Ref{Int}
    misses::Ref{Int}
    lock::ReentrantLock

    function QueryPlanCache(; max_size::Int=200)
        @assert max_size > 0 "max_size must be positive"
        new(max_size, Dict{UInt64, CacheEntry}(), Ref(0), Ref(0), ReentrantLock())
    end
end

"""
    cache_key(query::Query) -> UInt64

Generate a cache key based on the structural hash of the query AST.

The cache key is based on the query structure, not parameter values.
This allows different parameter values to reuse the same compiled SQL.
"""
function cache_key(query::Query)::UInt64
    return hash(query)
end

"""
    compile_with_cache(cache::QueryPlanCache, dialect::Dialect, query::Query) -> (String, Vector{Symbol})

Compile a query using the cache.

If the query has been compiled before, returns the cached result (cache hit).
Otherwise, compiles the query and stores it in the cache (cache miss).

# Arguments
- `cache::QueryPlanCache`: The query plan cache
- `dialect::Dialect`: The SQL dialect to use for compilation
- `query::Query`: The query to compile

# Returns
- `(sql::String, param_order::Vector{Symbol})`: Compiled SQL and parameter order

# Example

```julia
cache = QueryPlanCache()
dialect = SQLiteDialect()
query = from(:users) |> where(col(:users, :id) == param(Int, :id))

sql, params = compile_with_cache(cache, dialect, query)
# → ("SELECT * FROM `users` WHERE `users`.`id` = ?", [:id])
```
"""
function compile_with_cache(cache::QueryPlanCache, dialect::Dialect, query::Query)::Tuple{String, Vector{Symbol}}
    key = cache_key(query)

    @lock cache.lock begin
        # Check cache
        if haskey(cache.cache, key)
            entry = cache.cache[key]
            # Update LRU timestamp
            cache.cache[key] = CacheEntry(entry.sql, entry.param_order, time())
            cache.hits[] += 1
            return (entry.sql, entry.param_order)
        end

        # Cache miss - compile query
        cache.misses[] += 1
        sql, param_order = compile(dialect, query)

        # Store in cache
        entry = CacheEntry(sql, param_order, time())
        cache.cache[key] = entry

        # Evict LRU entry if cache is full
        if length(cache.cache) > cache.max_size
            evict_lru!(cache)
        end

        return (sql, param_order)
    end
end

"""
    evict_lru!(cache::QueryPlanCache) -> Nothing

Evict the least recently used entry from the cache.

This is called automatically when the cache exceeds max_size.
"""
function evict_lru!(cache::QueryPlanCache)::Nothing
    if isempty(cache.cache)
        return nothing
    end

    # Find LRU entry
    lru_key = nothing
    lru_time = Inf

    for (key, entry) in cache.cache
        if entry.last_used < lru_time
            lru_time = entry.last_used
            lru_key = key
        end
    end

    # Delete LRU entry
    if lru_key !== nothing
        delete!(cache.cache, lru_key)
    end

    return nothing
end

"""
    clear_cache!(cache::QueryPlanCache) -> Nothing

Clear all entries from the cache and reset statistics.

# Example

```julia
clear_cache!(cache)
stats = cache_stats(cache)
# → (hits=0, misses=0, size=0, max_size=200)
```
"""
function clear_cache!(cache::QueryPlanCache)::Nothing
    @lock cache.lock begin
        empty!(cache.cache)
        cache.hits[] = 0
        cache.misses[] = 0
    end
    return nothing
end

"""
    cache_stats(cache::QueryPlanCache) -> NamedTuple

Get cache statistics.

# Returns
- `(hits::Int, misses::Int, size::Int, max_size::Int, hit_rate::Float64)`

# Example

```julia
stats = cache_stats(cache)
println("Hit rate: \$(stats.hit_rate * 100)%")
```
"""
function cache_stats(cache::QueryPlanCache)::NamedTuple
    @lock cache.lock begin
        hits = cache.hits[]
        misses = cache.misses[]
        total = hits + misses
        hit_rate = total > 0 ? hits / total : 0.0

        return (
            hits = hits,
            misses = misses,
            size = length(cache.cache),
            max_size = cache.max_size,
            hit_rate = hit_rate
        )
    end
end

end # module QueryPlanCache
