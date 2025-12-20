"""
# PostgreSQL-Specific Codecs

PostgreSQL-specific type codecs for advanced types like JSONB, ARRAY, and native UUID.

This module extends the core codec system with PostgreSQL-specific types that
are not available in SQLite.

## Supported Types

- Native UUID (PostgreSQL UUID type)
- JSONB (PostgreSQL binary JSON)
- ARRAY types (PostgreSQL arrays)
- HSTORE (PostgreSQL key-value store)

## Usage

```julia
using SQLSketch
using SQLSketch.Codecs.PostgreSQL

# Create registry with PostgreSQL-specific codecs
registry = PostgreSQLCodecRegistry()

# JSONB encoding/decoding
data = Dict("name" => "Alice", "age" => 30)
encoded = encode(get_codec(registry, Dict{String, Any}), data)

# Array encoding/decoding
arr = [1, 2, 3, 4, 5]
encoded = encode(get_codec(registry, Vector{Int}), arr)
```

See `docs/design.md` Section 11 for detailed design rationale.
"""

using ...Core: Codec, CodecRegistry
import ...Core: encode, decode, register!, get_codec
using UUIDs
using JSON3
using Dates: Date, DateTime

#-------------------------------------------------------------------------------
# PostgreSQL-Specific Codecs
#-------------------------------------------------------------------------------

"""
PostgreSQL native UUID codec.

Unlike SQLite which stores UUIDs as TEXT, PostgreSQL has a native UUID type
that LibPQ.jl handles automatically. This codec primarily handles conversion
between Julia UUID and the wire format.

PostgreSQL: UUID (native type, 16 bytes)
"""
struct PostgreSQLUUIDCodec <: Codec end

encode(::PostgreSQLUUIDCodec, value::UUID)::UUID = value
encode(::PostgreSQLUUIDCodec, ::Missing) = missing
decode(::PostgreSQLUUIDCodec, value::UUID)::UUID = value
decode(::PostgreSQLUUIDCodec, ::Missing) = missing
decode(::PostgreSQLUUIDCodec, value::String)::UUID = UUID(value)

"""
PostgreSQL JSONB codec.

JSONB is PostgreSQL's binary JSON format, which is more efficient than TEXT-based JSON.
LibPQ.jl handles JSONB serialization/deserialization automatically.

PostgreSQL: JSONB
"""
struct JSONBCodec <: Codec end

function encode(::JSONBCodec, value::Dict{String, Any})::String
    return JSON3.write(value)
end

function encode(::JSONBCodec, value::Vector{Any})::String
    return JSON3.write(value)
end

function encode(::JSONBCodec, value::Any)::String
    return JSON3.write(value)
end

encode(::JSONBCodec, ::Missing) = missing

function decode(::JSONBCodec, value::String)::Dict{String, Any}
    return JSON3.read(value, Dict{String, Any})
end

decode(::JSONBCodec, ::Missing) = missing

# LibPQ.jl may return already-parsed JSON
function decode(::JSONBCodec, value::Dict{String, Any})::Dict{String, Any}
    return value
end

function decode(::JSONBCodec, value::Vector{Any})::Vector{Any}
    return value
end

"""
PostgreSQL Array codec.

PostgreSQL supports multi-dimensional arrays natively. This codec handles
conversion between Julia Vector types and PostgreSQL ARRAY types.

PostgreSQL: ARRAY types (INTEGER[], TEXT[], etc.)
"""
struct ArrayCodec{T} <: Codec
    element_codec::Codec
end

function encode(codec::ArrayCodec{T}, value::Vector{T})::Vector where {T}
    return [encode(codec.element_codec, elem) for elem in value]
end

encode(::ArrayCodec{T}, ::Missing) where {T} = missing

function decode(codec::ArrayCodec{T}, value::Vector)::Vector{T} where {T}
    return [decode(codec.element_codec, elem) for elem in value]
end

decode(::ArrayCodec{T}, ::Missing) where {T} = missing

"""
PostgreSQL Text Array codec.

Specialization for TEXT[] arrays, which are commonly used in PostgreSQL.

PostgreSQL: TEXT[]
"""
struct TextArrayCodec <: Codec end

encode(::TextArrayCodec, value::Vector{String})::Vector{String} = value
encode(::TextArrayCodec, ::Missing) = missing
decode(::TextArrayCodec, value::Vector{String})::Vector{String} = value
decode(::TextArrayCodec, value::Vector{Any})::Vector{String} = String[string(v) for v in value]
decode(::TextArrayCodec, ::Missing) = missing

"""
PostgreSQL Integer Array codec.

Specialization for INTEGER[] arrays.

PostgreSQL: INTEGER[]
"""
struct IntArrayCodec <: Codec end

encode(::IntArrayCodec, value::Vector{Int})::Vector{Int} = value
encode(::IntArrayCodec, ::Missing) = missing
decode(::IntArrayCodec, value::Vector{Int})::Vector{Int} = value
decode(::IntArrayCodec, value::Vector{<:Integer})::Vector{Int} = Int[Int(v) for v in value]
decode(::IntArrayCodec, ::Missing) = missing

"""
PostgreSQL Boolean codec (native BOOLEAN type).

Unlike SQLite which uses INTEGER (0/1), PostgreSQL has a native BOOLEAN type.
LibPQ.jl handles this automatically, but we provide this codec for consistency.

PostgreSQL: BOOLEAN
"""
struct PostgreSQLBoolCodec <: Codec end

encode(::PostgreSQLBoolCodec, value::Bool)::Bool = value
encode(::PostgreSQLBoolCodec, ::Missing) = missing
decode(::PostgreSQLBoolCodec, value::Bool)::Bool = value
decode(::PostgreSQLBoolCodec, ::Missing) = missing

"""
PostgreSQL Date codec (native DATE type).

PostgreSQL has native DATE type support. LibPQ.jl can handle Date objects directly.

PostgreSQL: DATE
"""
struct PostgreSQLDateCodec <: Codec end

function encode(::PostgreSQLDateCodec, value::Date)::Date
    return value
end

encode(::PostgreSQLDateCodec, ::Missing) = missing

function decode(::PostgreSQLDateCodec, value::Date)::Date
    return value
end

decode(::PostgreSQLDateCodec, ::Missing) = missing

# Handle string representation if LibPQ returns it as string
function decode(::PostgreSQLDateCodec, value::String)::Date
    return Date(value, "yyyy-mm-dd")
end

"""
PostgreSQL DateTime codec (native TIMESTAMP type).

PostgreSQL has native TIMESTAMP type support. LibPQ.jl can handle DateTime objects directly.

PostgreSQL: TIMESTAMP, TIMESTAMPTZ
"""
struct PostgreSQLDateTimeCodec <: Codec end

function encode(::PostgreSQLDateTimeCodec, value::DateTime)::DateTime
    return value
end

encode(::PostgreSQLDateTimeCodec, ::Missing) = missing

function decode(::PostgreSQLDateTimeCodec, value::DateTime)::DateTime
    return value
end

decode(::PostgreSQLDateTimeCodec, ::Missing) = missing

# Handle string representation if LibPQ returns it as string
function decode(::PostgreSQLDateTimeCodec, value::String)::DateTime
    # PostgreSQL returns timestamps in ISO 8601 format
    return DateTime(value)
end

#-------------------------------------------------------------------------------
# PostgreSQL CodecRegistry Factory
#-------------------------------------------------------------------------------

"""
    PostgreSQLCodecRegistry() -> CodecRegistry

Create a CodecRegistry with PostgreSQL-specific codecs registered.

This registry includes:
- All default codecs from Core.CodecRegistry
- PostgreSQL native UUID (replaces TEXT-based UUID)
- PostgreSQL native BOOLEAN (replaces INTEGER-based Bool)
- PostgreSQL native DATE/TIMESTAMP (replaces TEXT-based)
- JSONB support
- Array type support

# Example

```julia
registry = PostgreSQLCodecRegistry()

# Use with PostgreSQL-specific types
data = Dict("key" => "value")
codec = get_codec(registry, Dict{String, Any})
encoded = encode(codec, data)
```
"""
function PostgreSQLCodecRegistry()::CodecRegistry
    # Start with base registry
    registry = CodecRegistry()

    # Override default codecs with PostgreSQL-native versions
    register!(registry, UUID, PostgreSQLUUIDCodec())
    register!(registry, Bool, PostgreSQLBoolCodec())
    register!(registry, Date, PostgreSQLDateCodec())
    register!(registry, DateTime, PostgreSQLDateTimeCodec())

    # Register PostgreSQL-specific types
    register!(registry, Dict{String, Any}, JSONBCodec())
    register!(registry, Vector{String}, TextArrayCodec())
    register!(registry, Vector{Int}, IntArrayCodec())

    return registry
end

#-------------------------------------------------------------------------------
# Exports
#-------------------------------------------------------------------------------

export PostgreSQLCodecRegistry
export PostgreSQLUUIDCodec, JSONBCodec, ArrayCodec
export TextArrayCodec, IntArrayCodec
export PostgreSQLBoolCodec, PostgreSQLDateCodec, PostgreSQLDateTimeCodec
