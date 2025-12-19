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

# TODO: Implement CodecRegistry
# This is Phase 5 of the roadmap

"""
Abstract base type for all codecs.

A Codec defines how to encode and decode a specific Julia type
to/from database representations.
"""
abstract type Codec end

"""
The CodecRegistry maintains a mapping from Julia types to codecs.

This centralizes all type conversion logic in a single, inspectable location.
"""
struct CodecRegistry
    # TODO: Implement registry storage (Dict{Type, Codec})
end

# Placeholder functions - to be completed in Phase 5

# TODO: Implement CodecRegistry()
# TODO: Implement register!(registry::CodecRegistry, T::Type, codec::Codec)
# TODO: Implement get_codec(registry::CodecRegistry, T::Type) -> Codec
# TODO: Implement encode(codec::Codec, value) -> db_value
# TODO: Implement decode(codec::Codec, db_value) -> julia_value
# TODO: Implement map_row(registry::CodecRegistry, ::Type{NamedTuple}, row) -> NamedTuple
# TODO: Implement map_row(registry::CodecRegistry, ::Type{T}, row) -> T

# TODO: Implement default codecs:
# - IntCodec
# - Float64Codec
# - StringCodec
# - BoolCodec
# - DateCodec
# - DateTimeCodec
# - UUIDCodec
# - MissingCodec (NULL policy)
