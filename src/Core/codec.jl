"""
# Type Conversion and CodecRegistry

This module defines the type conversion system for SQLSketch.

The CodecRegistry centralizes all database-to-Julia type conversion,
explicitly separating:
- SQL semantics (Dialect)
- Execution mechanics (Driver)
- Data representation and invariants (CodecRegistry)

## Design Principles

- Type conversion is **explicit and centralized**
- NULL handling follows a consistent global policy
- Backend-specific quirks are normalized at the codec layer
- Codecs enforce type invariants before struct construction

## Responsibilities

- Encode Julia values into database-compatible representations
- Decode database values into Julia types
- Enforce consistent NULL policy
- Normalize backend-specific quirks (especially for SQLite)
- Map rows into NamedTuples or structs

## Usage

```julia
registry = CodecRegistry()
register!(registry, Int, IntCodec())
register!(registry, String, StringCodec())

# Encode
encoded = encode(get_codec(registry, Int), 42)

# Decode
decoded = decode(get_codec(registry, String), "hello")

# Map row
row = (id=1, email="test@example.com")
mapped = map_row(registry, User, row)
```

See `docs/design.md` Section 12 for detailed design rationale.
"""

using Dates
using UUIDs

#-------------------------------------------------------------------------------
# Core Types
#-------------------------------------------------------------------------------

"""
Abstract base type for all codecs.

A Codec defines how to encode and decode a specific Julia type
to/from database representations.
"""
abstract type Codec end

"""
    encode(codec::Codec, value) -> database_value

Encode a Julia value into a database-compatible representation.

This function is called before sending values to the database.
"""
function encode end

"""
    decode(codec::Codec, db_value) -> julia_value

Decode a database value into a Julia value.

This function is called when reading values from the database.
"""
function decode end

"""
The CodecRegistry maintains a mapping from Julia types to codecs.

This centralizes all type conversion logic in a single, inspectable location.

# Fields
- `codecs::Dict{Type, Codec}` - Mapping from Julia types to codecs
"""
struct CodecRegistry
    codecs::Dict{Type, Codec}
end

"""
    CodecRegistry() -> CodecRegistry

Create a new CodecRegistry with default codecs registered.

Default codecs include:
- Basic types: Int, Float64, String, Bool
- Date/Time types: Date, DateTime
- UUID (as TEXT)
- Missing (NULL policy)
"""
function CodecRegistry()::CodecRegistry
    registry = CodecRegistry(Dict{Type, Codec}())

    # Register default codecs
    register!(registry, Int, IntCodec())
    register!(registry, Float64, Float64Codec())
    register!(registry, String, StringCodec())
    register!(registry, Bool, BoolCodec())
    register!(registry, Date, DateCodec())
    register!(registry, DateTime, DateTimeCodec())
    register!(registry, UUID, UUIDCodec())

    return registry
end

"""
    register!(registry::CodecRegistry, T::Type, codec::Codec) -> Nothing

Register a codec for a specific Julia type.

# Example
```julia
registry = CodecRegistry()
register!(registry, MyType, MyTypeCodec())
```
"""
function register!(registry::CodecRegistry, T::Type, codec::Codec)::Nothing
    registry.codecs[T] = codec
    return nothing
end

"""
    get_codec(registry::CodecRegistry, T::Type) -> Codec

Retrieve the codec for a specific Julia type.

Throws an error if no codec is registered for the type.

# Example
```julia
codec = get_codec(registry, Int)
encoded = encode(codec, 42)
```
"""
function get_codec(registry::CodecRegistry, T::Type)::Codec
    # Handle Union{T, Missing} by extracting T
    if T isa Union
        # Extract non-Missing type from Union
        types = Base.uniontypes(T)
        non_missing_types = filter(t -> t !== Missing, types)

        if length(non_missing_types) == 1
            base_type = non_missing_types[1]
            if haskey(registry.codecs, base_type)
                return registry.codecs[base_type]
            end
        end
    end

    # Direct lookup
    if haskey(registry.codecs, T)
        return registry.codecs[T]
    end

    error("No codec registered for type: $T")
end

#-------------------------------------------------------------------------------
# Default Codecs
#-------------------------------------------------------------------------------

"""
Codec for Int values.

SQLite: INTEGER
PostgreSQL: INTEGER, BIGINT
"""
struct IntCodec <: Codec end

encode(::IntCodec, value::Int)::Int = value
encode(::IntCodec, ::Missing) = missing
decode(::IntCodec, value::Int)::Int = value
decode(::IntCodec, ::Missing) = missing
decode(::IntCodec, value::Integer)::Int = Int(value)

"""
Codec for Float64 values.

SQLite: REAL
PostgreSQL: DOUBLE PRECISION
"""
struct Float64Codec <: Codec end

encode(::Float64Codec, value::Float64)::Float64 = value
encode(::Float64Codec, ::Missing) = missing
decode(::Float64Codec, value::Float64)::Float64 = value
decode(::Float64Codec, ::Missing) = missing
decode(::Float64Codec, value::Real)::Float64 = Float64(value)

"""
Codec for String values.

SQLite: TEXT
PostgreSQL: VARCHAR, TEXT
"""
struct StringCodec <: Codec end

encode(::StringCodec, value::String)::String = value
encode(::StringCodec, ::Missing) = missing
decode(::StringCodec, value::String)::String = value
decode(::StringCodec, ::Missing) = missing

"""
Codec for Bool values.

SQLite: INTEGER (0 or 1)
PostgreSQL: BOOLEAN
"""
struct BoolCodec <: Codec end

encode(::BoolCodec, value::Bool)::Int = value ? 1 : 0
encode(::BoolCodec, ::Missing) = missing
function decode(::BoolCodec, value::Int)::Bool
    if value == 0
        return false
    elseif value == 1
        return true
    else
        error("Invalid boolean value: $value (expected 0 or 1)")
    end
end
decode(::BoolCodec, ::Missing) = missing
decode(::BoolCodec, value::Bool)::Bool = value

"""
Codec for Date values.

SQLite: TEXT (ISO 8601 format: YYYY-MM-DD)
PostgreSQL: DATE
"""
struct DateCodec <: Codec end

encode(::DateCodec, value::Date)::String = Dates.format(value, "yyyy-mm-dd")
encode(::DateCodec, ::Missing) = missing
decode(::DateCodec, value::String)::Date = Date(value, "yyyy-mm-dd")
decode(::DateCodec, ::Missing) = missing
decode(::DateCodec, value::Date)::Date = value

"""
Codec for DateTime values.

SQLite: TEXT (ISO 8601 format: YYYY-MM-DD HH:MM:SS)
PostgreSQL: TIMESTAMP
"""
struct DateTimeCodec <: Codec end

function encode(::DateTimeCodec, value::DateTime)::String
    return Dates.format(value, "yyyy-mm-dd HH:MM:SS")
end
encode(::DateTimeCodec, ::Missing) = missing
function decode(::DateTimeCodec, value::String)::DateTime
    return DateTime(value, "yyyy-mm-dd HH:MM:SS")
end
decode(::DateTimeCodec, ::Missing) = missing
decode(::DateTimeCodec, value::DateTime)::DateTime = value

"""
Codec for UUID values.

SQLite: TEXT (36-character hyphenated string)
PostgreSQL: UUID (native type)
"""
struct UUIDCodec <: Codec end

encode(::UUIDCodec, value::UUID)::String = string(value)
encode(::UUIDCodec, ::Missing) = missing
decode(::UUIDCodec, value::String)::UUID = UUID(value)
decode(::UUIDCodec, ::Missing) = missing
decode(::UUIDCodec, value::UUID)::UUID = value

#-------------------------------------------------------------------------------
# Row Mapping
#-------------------------------------------------------------------------------

"""
    map_row(registry::CodecRegistry, ::Type{NamedTuple}, row) -> NamedTuple

Map a database row to a NamedTuple, applying type conversion via codecs.

# Example
```julia
row = (id=1, email="test@example.com")
result = map_row(registry, NamedTuple, row)
# → (id=1, email="test@example.com")
```
"""
function map_row(registry::CodecRegistry, ::Type{NamedTuple}, row)::NamedTuple
    # NamedTuple is already in the right format
    if row isa NamedTuple
        return row
    end

    error("Cannot convert row of type $(typeof(row)) to NamedTuple")
end

"""
    map_row(registry::CodecRegistry, ::Type{T}, row) -> T where T

Map a database row to a struct of type T, applying type conversion via codecs.

# Example
```julia
struct User
    id::Int
    email::String
end

row = (id=1, email="test@example.com")
user = map_row(registry, User, row)
# → User(1, "test@example.com")
```

# Requirements
- Field names in the row must match field names in the struct
- Field types must have registered codecs
- Fields are passed to the constructor in the order they are defined in the struct
"""
function map_row(registry::CodecRegistry, ::Type{T}, row)::T where {T}
    # Get field names and types from the target struct
    field_names = fieldnames(T)
    field_types = fieldtypes(T)

    # Build a list of decoded values in the correct order
    values = []

    for (name, type) in zip(field_names, field_types)
        # Get the raw value from the row
        if !haskey(row, name)
            error("Missing field '$name' in row for type $T")
        end

        raw_value = getproperty(row, name)

        # Decode the value using the appropriate codec
        if raw_value === missing
            # Handle missing values
            if type >: Missing
                push!(values, missing)
            else
                error("Field '$name' in type $T does not allow missing values, but received missing")
            end
        else
            codec = get_codec(registry, type)
            push!(values, decode(codec, raw_value))
        end
    end

    # Construct the struct using positional arguments
    try
        return T(values...)
    catch e
        error("Failed to construct $T from row: $e")
    end
end

#-------------------------------------------------------------------------------
# Exports
#-------------------------------------------------------------------------------

export Codec, CodecRegistry
export encode, decode
export register!, get_codec
export map_row

# Export default codecs
export IntCodec, Float64Codec, StringCodec, BoolCodec
export DateCodec, DateTimeCodec, UUIDCodec
