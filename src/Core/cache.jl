"""
# Prepared Statement Cache

This module implements a thread-safe LRU cache for prepared statements.

## Design Principles

- Cache key is a hash of the Query AST
- Cache value is a prepared statement handle
- LRU eviction policy with configurable max size
- Thread-safe for concurrent access
- Independent of specific database drivers

## Architecture

```
PreparedStatementCache
  ├─ cache::OrderedDict{UInt64, CacheEntry}
  ├─ max_size::Int
  ├─ lock::ReentrantLock
  └─ stats::CacheStats
```

## Usage

```julia
cache = PreparedStatementCache(; max_size=100)

# Query hash as cache key
key = hash_query(query)

# Try to get from cache
entry = get_cached(cache, key)
if entry === nothing
    # Cache miss - prepare statement
    stmt = prepare_statement(conn, sql)
    put_cached!(cache, key, stmt, sql)
else
    # Cache hit - reuse statement
    stmt = entry.statement
end
```

See CLAUDE.md Phase 13 for design rationale.
"""

using SHA
using DataStructures: OrderedDict

"""
    CacheEntry

A single entry in the prepared statement cache.

# Fields

- `statement::Any`: The prepared statement handle (driver-specific)
- `sql::String`: The SQL string for this statement
- `access_count::Int`: Number of times this entry has been accessed
"""
mutable struct CacheEntry
    statement::Any
    sql::String
    access_count::Int
end

"""
    CacheStats

Statistics for cache performance monitoring.

# Fields

- `hits::Int`: Number of cache hits
- `misses::Int`: Number of cache misses
- `evictions::Int`: Number of LRU evictions
"""
mutable struct CacheStats
    hits::Int
    misses::Int
    evictions::Int
end

CacheStats()::CacheStats = CacheStats(0, 0, 0)

"""
    PreparedStatementCache

Thread-safe LRU cache for prepared statements.

# Fields

- `cache::OrderedDict{UInt64, CacheEntry}`: Ordered cache (LRU order)
- `max_size::Int`: Maximum number of entries
- `lock::ReentrantLock`: Lock for thread-safe access
- `stats::CacheStats`: Cache statistics

# Example

```julia
cache = PreparedStatementCache(; max_size=100)
key = hash_query(query)

# Get from cache
entry = get_cached(cache, key)

# Put in cache
put_cached!(cache, key, stmt, sql)

# Get statistics
stats = cache_stats(cache)
println("Hit rate: \$(stats.hits / (stats.hits + stats.misses))")
```
"""
mutable struct PreparedStatementCache
    cache::OrderedDict{UInt64,CacheEntry}
    max_size::Int
    lock::ReentrantLock
    stats::CacheStats
end

"""
    PreparedStatementCache(; max_size::Int=100) -> PreparedStatementCache

Create a new prepared statement cache with the specified maximum size.

# Arguments

- `max_size`: Maximum number of entries to cache (default: 100)

# Returns

A new `PreparedStatementCache` instance

# Example

```julia
cache = PreparedStatementCache(; max_size=100)
```
"""
function PreparedStatementCache(; max_size::Int = 100)::PreparedStatementCache
    return PreparedStatementCache(OrderedDict{UInt64,CacheEntry}(),
                                  max_size,
                                  ReentrantLock(),
                                  CacheStats())
end

"""
    hash_query(query::Query) -> UInt64

Generate a cache key from a Query AST.

Uses SHA256 to hash the string representation of the query AST.
This ensures that structurally identical queries produce the same key.

# Arguments

- `query`: The Query AST to hash

# Returns

A UInt64 hash value suitable for use as a cache key

# Example

```julia
q1 = from(:users) |> where(col(:users, :active) == literal(1))
q2 = from(:users) |> where(col(:users, :active) == literal(1))

hash1 = hash_query(q1)
hash2 = hash_query(q2)
@assert hash1 == hash2  # Structurally identical queries
```
"""
function hash_query(query::Query)::UInt64
    # Convert query to string representation
    query_str = string(query)

    # Compute SHA256 hash
    hash_bytes = sha256(query_str)

    # Convert first 8 bytes to UInt64
    return reinterpret(UInt64, hash_bytes[1:8])[1]
end

"""
    get_cached(cache::PreparedStatementCache, key::UInt64) -> Union{CacheEntry, Nothing}

Retrieve a cached entry by key.

Thread-safe. Updates access order for LRU tracking.

# Arguments

- `cache`: The cache to query
- `key`: The cache key (from `hash_query`)

# Returns

- `CacheEntry` if found (cache hit)
- `Nothing` if not found (cache miss)

# Example

```julia
key = hash_query(query)
entry = get_cached(cache, key)
if entry !== nothing
    # Cache hit
    stmt = entry.statement
else
    # Cache miss
    stmt = prepare_statement(conn, sql)
    put_cached!(cache, key, stmt, sql)
end
```
"""
function get_cached(cache::PreparedStatementCache,
                    key::UInt64)::Union{CacheEntry,Nothing}
    lock(cache.lock) do
        if haskey(cache.cache, key)
            # Cache hit - move to end (most recently used)
            entry = cache.cache[key]
            delete!(cache.cache, key)
            cache.cache[key] = entry
            entry.access_count += 1
            cache.stats.hits += 1
            return entry
        else
            # Cache miss
            cache.stats.misses += 1
            return nothing
        end
    end
end

"""
    put_cached!(cache::PreparedStatementCache, key::UInt64,
                statement::Any, sql::String) -> Nothing

Add or update a cache entry.

Thread-safe. Evicts least recently used entry if cache is full.

# Arguments

- `cache`: The cache to update
- `key`: The cache key (from `hash_query`)
- `statement`: The prepared statement handle
- `sql`: The SQL string for this statement

# Example

```julia
key = hash_query(query)
stmt = prepare_statement(conn, sql)
put_cached!(cache, key, stmt, sql)
```
"""
function put_cached!(cache::PreparedStatementCache,
                     key::UInt64,
                     statement::Any,
                     sql::String)::Nothing
    lock(cache.lock) do
        # Check if cache is full
        if length(cache.cache) >= cache.max_size && !haskey(cache.cache, key)
            # Evict least recently used (first entry)
            first_key = first(keys(cache.cache))
            delete!(cache.cache, first_key)
            cache.stats.evictions += 1
        end

        # Add new entry (or update existing)
        cache.cache[key] = CacheEntry(statement, sql, 0)
    end

    return nothing
end

"""
    clear_cache!(cache::PreparedStatementCache) -> Nothing

Clear all entries from the cache.

Thread-safe.

# Arguments

- `cache`: The cache to clear

# Example

```julia
clear_cache!(cache)
```
"""
function clear_cache!(cache::PreparedStatementCache)::Nothing
    lock(cache.lock) do
        empty!(cache.cache)
    end
    return nothing
end

"""
    cache_stats(cache::PreparedStatementCache) -> CacheStats

Get cache statistics.

Returns a copy of the current stats (thread-safe).

# Arguments

- `cache`: The cache to query

# Returns

`CacheStats` with current hit/miss/eviction counts

# Example

```julia
stats = cache_stats(cache)
total = stats.hits + stats.misses
hit_rate = total > 0 ? stats.hits / total : 0.0
println("Hit rate: \$(round(hit_rate * 100, digits=2))%")
println("Evictions: \$(stats.evictions)")
```
"""
function cache_stats(cache::PreparedStatementCache)::CacheStats
    lock(cache.lock) do
        return CacheStats(cache.stats.hits, cache.stats.misses, cache.stats.evictions)
    end
end

"""
    cache_size(cache::PreparedStatementCache) -> Int

Get the current number of entries in the cache.

Thread-safe.

# Arguments

- `cache`: The cache to query

# Returns

Number of entries currently in the cache

# Example

```julia
size = cache_size(cache)
println("Cache occupancy: \$size / \$(cache.max_size)")
```
"""
function cache_size(cache::PreparedStatementCache)::Int
    lock(cache.lock) do
        return length(cache.cache)
    end
end
