"""
# MySQL-specific Codecs

Type conversion codecs for MySQL/MariaDB data types.

This module provides codecs for MySQL-specific types that differ from
the standard SQLite behavior.

## Type Mappings

- `TINYINT(1)` ↔ `Bool`
- `DATETIME` ↔ `DateTime`
- `DATE` ↔ `Date`
- `CHAR(36)` ↔ `UUID`
- `JSON` ↔ `Dict`/`Vector`
- `BLOB` ↔ `Vector{UInt8}`

## Usage

```julia
using SQLSketch
using SQLSketch.Codecs.MySQL

# Register MySQL codecs
registry = CodecRegistry()
register!(registry, Bool, MySQL.BoolCodec())
register!(registry, DateTime, MySQL.DateTimeCodec())
```
"""

using Dates: Date, DateTime
using UUIDs: UUID
using JSON3
import ...Core: Codec, encode, decode, register!

"""
    BoolCodec()

MySQL boolean codec (TINYINT(1) ↔ Bool).

MySQL stores booleans as TINYINT(1), where:

  - 0 = false
  - 1 (or any non-zero) = true

# Example

```julia
codec = BoolCodec()
encode(codec, true)   # → 1
decode(codec, Bool, 1)  # → true
```
"""
struct BoolCodec <: Codec
end

function encode(codec::BoolCodec, value::Bool)::Int
    return value ? 1 : 0
end

function decode(codec::BoolCodec, ::Type{Bool}, value)::Bool
    if value isa Bool
        return value
    elseif value isa Integer
        return value != 0
    elseif value === missing || value === nothing
        return false  # Default to false for NULL
    else
        error("Cannot decode $value to Bool")
    end
end

"""
    DateCodec()

MySQL DATE codec (DATE ↔ Date).

# Example

```julia
codec = DateCodec()
encode(codec, Date(2024, 1, 15))  # → "2024-01-15"
decode(codec, Date, "2024-01-15") # → Date(2024, 1, 15)
```
"""
struct DateCodec <: Codec
end

function encode(codec::DateCodec, value::Date)::String
    return Dates.format(value, "yyyy-mm-dd")
end

function decode(codec::DateCodec, ::Type{Date}, value)::Date
    if value isa Date
        return value
    elseif value isa AbstractString
        return Date(value, "yyyy-mm-dd")
    elseif value === missing || value === nothing
        error("Cannot decode NULL to Date")
    else
        error("Cannot decode $value to Date")
    end
end

"""
    DateTimeCodec()

MySQL DATETIME codec (DATETIME ↔ DateTime).

# Example

```julia
codec = DateTimeCodec()
encode(codec, DateTime(2024, 1, 15, 10, 30, 45))  # → "2024-01-15 10:30:45"
decode(codec, DateTime, "2024-01-15 10:30:45")    # → DateTime(2024, 1, 15, 10, 30, 45)
```
"""
struct DateTimeCodec <: Codec
end

function encode(codec::DateTimeCodec, value::DateTime)::String
    return Dates.format(value, "yyyy-mm-dd HH:MM:SS")
end

function decode(codec::DateTimeCodec, ::Type{DateTime}, value)::DateTime
    if value isa DateTime
        return value
    elseif value isa AbstractString
        return DateTime(value, "yyyy-mm-dd HH:MM:SS")
    elseif value === missing || value === nothing
        error("Cannot decode NULL to DateTime")
    else
        error("Cannot decode $value to DateTime")
    end
end

"""
    UUIDCodec()

MySQL UUID codec (CHAR(36) ↔ UUID).

MySQL stores UUIDs as CHAR(36) strings.

# Example

```julia
codec = UUIDCodec()
uuid = UUID("550e8400-e29b-41d4-a716-446655440000")
encode(codec, uuid)  # → "550e8400-e29b-41d4-a716-446655440000"
decode(codec, UUID, "550e8400-e29b-41d4-a716-446655440000")  # → UUID(...)
```
"""
struct UUIDCodec <: Codec
end

function encode(codec::UUIDCodec, value::UUID)::String
    return string(value)
end

function decode(codec::UUIDCodec, ::Type{UUID}, value)::UUID
    if value isa UUID
        return value
    elseif value isa AbstractString
        return UUID(value)
    elseif value === missing || value === nothing
        error("Cannot decode NULL to UUID")
    else
        error("Cannot decode $value to UUID")
    end
end

"""
    JSONCodec()

MySQL JSON codec (JSON ↔ Dict/Vector).

MySQL 5.7+ supports native JSON type.

This codec handles:

  - Dict{String, Any} for JSON objects
  - Vector{Any} for JSON arrays
  - Nested JSON structures

# Example

```julia
codec = JSONCodec()

# JSON object
data = Dict("name" => "Alice", "age" => 30)
encoded = encode(codec, data)  # → "{\"name\":\"Alice\",\"age\":30}"
decoded = decode(codec, Dict{String, Any}, encoded)  # → Dict("name" => "Alice", ...)

# JSON array
arr = [1, 2, 3, "hello"]
encoded_arr = encode(codec, arr)  # → "[1,2,3,\"hello\"]"
decoded_arr = decode(codec, Vector{Any}, encoded_arr)  # → [1, 2, 3, "hello"]
```
"""
struct JSONCodec <: Codec
end

function encode(codec::JSONCodec, value::Union{AbstractDict, AbstractVector})::String
    return JSON3.write(value)
end

function decode(codec::JSONCodec, ::Type{T}, value) where {T}
    if value isa T
        return value
    elseif value isa AbstractString
        # Parse JSON string
        parsed = JSON3.read(value)
        # Convert to target type
        if T <: AbstractDict
            return Dict{String, Any}(parsed)
        elseif T <: AbstractVector
            # Use collect to convert JSON3.Array to Vector{Any}
            return collect(Any, parsed)
        else
            return convert(T, parsed)
        end
    elseif value === missing || value === nothing
        # Return empty container
        if T <: AbstractDict
            return Dict{String, Any}()
        elseif T <: AbstractVector
            return Vector{Any}()
        else
            error("Cannot decode NULL to $T")
        end
    else
        error("Cannot decode $value ($(typeof(value))) to $T")
    end
end

"""
    BlobCodec()

MySQL BLOB codec (BLOB ↔ Vector{UInt8}).

# Example

```julia
codec = BlobCodec()
data = UInt8[0x48, 0x65, 0x6c, 0x6c, 0x6f]
encode(codec, data)  # → UInt8[0x48, 0x65, 0x6c, 0x6c, 0x6f]
decode(codec, Vector{UInt8}, data)  # → UInt8[0x48, 0x65, 0x6c, 0x6c, 0x6f]
```
"""
struct BlobCodec <: Codec
end

function encode(codec::BlobCodec, value::Vector{UInt8})::Vector{UInt8}
    return value
end

function decode(codec::BlobCodec, ::Type{Vector{UInt8}}, value)::Vector{UInt8}
    if value isa Vector{UInt8}
        return value
    elseif value isa AbstractVector
        return convert(Vector{UInt8}, value)
    elseif value === missing || value === nothing
        return UInt8[]
    else
        error("Cannot decode $value to Vector{UInt8}")
    end
end

"""
    register_mysql_codecs!(registry::CodecRegistry)

Register all MySQL-specific codecs into a codec registry.

This is a convenience function to register all MySQL codecs at once.

# Registered Codecs

  - `Bool` ↔ TINYINT(1)
  - `Date` ↔ DATE
  - `DateTime` ↔ DATETIME
  - `UUID` ↔ CHAR(36)
  - `Dict{String, Any}` ↔ JSON (objects)
  - `Vector{Any}` ↔ JSON (arrays)
  - `Vector{UInt8}` ↔ BLOB

# Example

```julia
using SQLSketch
using SQLSketch.Codecs.MySQL

registry = CodecRegistry()
MySQL.register_mysql_codecs!(registry)

# Now you can use JSON columns
data = Dict("name" => "Alice", "tags" => ["admin", "user"])
# INSERT INTO users (metadata) VALUES (?)
```
"""
function register_mysql_codecs!(registry)
    # Register MySQL-specific codecs (register! already imported at top)
    register!(registry, Bool, BoolCodec())
    register!(registry, Date, DateCodec())
    register!(registry, DateTime, DateTimeCodec())
    register!(registry, UUID, UUIDCodec())
    register!(registry, Dict{String, Any}, JSONCodec())
    register!(registry, Vector{Any}, JSONCodec())
    register!(registry, Vector{UInt8}, BlobCodec())

    return registry
end
