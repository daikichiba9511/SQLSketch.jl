"""
Tests for CodecRegistry and type conversion.

This test suite validates:
- Codec interface and registry
- Encode/decode for all default codecs
- NULL/Missing handling
- Row mapping to NamedTuple and structs
- Error handling and edge cases
"""

using Test
using SQLSketch
using SQLSketch.Core
using Dates
using UUIDs

@testset "CodecRegistry Tests" begin
    @testset "CodecRegistry Construction" begin
        registry = CodecRegistry()
        @test registry isa CodecRegistry
        @test haskey(registry.codecs, Int)
        @test haskey(registry.codecs, Float64)
        @test haskey(registry.codecs, String)
        @test haskey(registry.codecs, Bool)
        @test haskey(registry.codecs, Date)
        @test haskey(registry.codecs, DateTime)
        @test haskey(registry.codecs, UUID)
    end

    @testset "register! and get_codec" begin
        registry = CodecRegistry()

        # Test get_codec for default codecs
        @test get_codec(registry, Int) isa IntCodec
        @test get_codec(registry, Float64) isa Float64Codec
        @test get_codec(registry, String) isa StringCodec
        @test get_codec(registry, Bool) isa BoolCodec
        @test get_codec(registry, Date) isa DateCodec
        @test get_codec(registry, DateTime) isa DateTimeCodec
        @test get_codec(registry, UUID) isa UUIDCodec

        # Test get_codec error for unregistered type
        @test_throws ErrorException get_codec(registry, BigInt)
    end

    @testset "get_codec with Union{T, Missing}" begin
        registry = CodecRegistry()

        # Test Union{Int, Missing}
        codec = get_codec(registry, Union{Int, Missing})
        @test codec isa IntCodec

        # Test Union{String, Missing}
        codec = get_codec(registry, Union{String, Missing})
        @test codec isa StringCodec

        # Test Union{Date, Missing}
        codec = get_codec(registry, Union{Date, Missing})
        @test codec isa DateCodec
    end
end

@testset "IntCodec Tests" begin
    codec = IntCodec()

    @testset "encode" begin
        @test encode(codec, 42) === 42
        @test encode(codec, 0) === 0
        @test encode(codec, -100) === -100
        @test ismissing(encode(codec, missing))
    end

    @testset "decode" begin
        @test decode(codec, 42) === 42
        @test decode(codec, 0) === 0
        @test decode(codec, -100) === -100
        @test ismissing(decode(codec, missing))

        # Test Integer → Int conversion
        @test decode(codec, Int8(10)) === 10
        @test decode(codec, Int64(100)) === 100
    end
end

@testset "Float64Codec Tests" begin
    codec = Float64Codec()

    @testset "encode" begin
        @test encode(codec, 3.14) === 3.14
        @test encode(codec, 0.0) === 0.0
        @test encode(codec, -1.5) === -1.5
        @test ismissing(encode(codec, missing))
    end

    @testset "decode" begin
        @test decode(codec, 3.14) === 3.14
        @test decode(codec, 0.0) === 0.0
        @test decode(codec, -1.5) === -1.5
        @test ismissing(decode(codec, missing))

        # Test Real → Float64 conversion
        @test decode(codec, 42) === 42.0
        @test decode(codec, Float32(1.5)) === 1.5
    end
end

@testset "StringCodec Tests" begin
    codec = StringCodec()

    @testset "encode" begin
        @test encode(codec, "hello") === "hello"
        @test encode(codec, "") === ""
        @test ismissing(encode(codec, missing))
    end

    @testset "decode" begin
        @test decode(codec, "hello") === "hello"
        @test decode(codec, "") === ""
        @test ismissing(decode(codec, missing))
    end
end

@testset "BoolCodec Tests" begin
    codec = BoolCodec()

    @testset "encode" begin
        @test encode(codec, true) === 1
        @test encode(codec, false) === 0
        @test ismissing(encode(codec, missing))
    end

    @testset "decode" begin
        @test decode(codec, 1) === true
        @test decode(codec, 0) === false
        @test decode(codec, true) === true
        @test decode(codec, false) === false
        @test ismissing(decode(codec, missing))

        # Test invalid values
        @test_throws ErrorException decode(codec, 2)
        @test_throws ErrorException decode(codec, -1)
    end
end

@testset "DateCodec Tests" begin
    codec = DateCodec()

    @testset "encode" begin
        d = Date(2025, 12, 19)
        @test encode(codec, d) === "2025-12-19"
        @test ismissing(encode(codec, missing))
    end

    @testset "decode" begin
        @test decode(codec, "2025-12-19") === Date(2025, 12, 19)
        @test decode(codec, Date(2025, 12, 19)) === Date(2025, 12, 19)
        @test ismissing(decode(codec, missing))
    end

    @testset "round-trip" begin
        d = Date(2025, 12, 19)
        encoded = encode(codec, d)
        decoded = decode(codec, encoded)
        @test decoded === d
    end
end

@testset "DateTimeCodec Tests" begin
    codec = DateTimeCodec()

    @testset "encode" begin
        dt = DateTime(2025, 12, 19, 10, 30, 45)
        @test encode(codec, dt) === "2025-12-19 10:30:45"
        @test ismissing(encode(codec, missing))
    end

    @testset "decode" begin
        @test decode(codec, "2025-12-19 10:30:45") === DateTime(2025, 12, 19, 10, 30, 45)
        @test decode(codec, DateTime(2025, 12, 19, 10, 30, 45)) === DateTime(2025, 12, 19, 10, 30, 45)
        @test ismissing(decode(codec, missing))
    end

    @testset "round-trip" begin
        dt = DateTime(2025, 12, 19, 10, 30, 45)
        encoded = encode(codec, dt)
        decoded = decode(codec, encoded)
        @test decoded === dt
    end
end

@testset "UUIDCodec Tests" begin
    codec = UUIDCodec()

    @testset "encode" begin
        u = uuid4()
        encoded = encode(codec, u)
        @test encoded isa String
        @test length(encoded) === 36  # UUID string format
        @test ismissing(encode(codec, missing))
    end

    @testset "decode" begin
        u = uuid4()
        s = string(u)
        @test decode(codec, s) === u
        @test decode(codec, u) === u
        @test ismissing(decode(codec, missing))
    end

    @testset "round-trip" begin
        u = uuid4()
        encoded = encode(codec, u)
        decoded = decode(codec, encoded)
        @test decoded === u
    end
end

@testset "map_row for NamedTuple" begin
    registry = CodecRegistry()

    @testset "Simple NamedTuple" begin
        row = (id=1, email="test@example.com")
        result = map_row(registry, NamedTuple, row)
        @test result === row
    end

    @testset "NamedTuple with various types" begin
        row = (
            id=42,
            name="Alice",
            score=95.5,
            active=true,
        )
        result = map_row(registry, NamedTuple, row)
        @test result === row
    end

    @testset "Error on non-NamedTuple" begin
        @test_throws ErrorException map_row(registry, NamedTuple, [1, 2, 3])
        @test_throws ErrorException map_row(registry, NamedTuple, Dict(:id => 1))
    end
end

@testset "map_row for Structs" begin
    registry = CodecRegistry()

    struct User
        id::Int
        email::String
    end

    struct Product
        id::Int
        name::String
        price::Float64
        active::Bool
    end

    struct OptionalFields
        id::Int
        name::Union{String, Missing}
    end

    @testset "Simple struct" begin
        row = (id=1, email="test@example.com")
        user = map_row(registry, User, row)
        @test user isa User
        @test user.id === 1
        @test user.email === "test@example.com"
    end

    @testset "Struct with multiple types" begin
        row = (id=1, name="Widget", price=19.99, active=true)
        product = map_row(registry, Product, row)
        @test product isa Product
        @test product.id === 1
        @test product.name === "Widget"
        @test product.price === 19.99
        @test product.active === true
    end

    @testset "Struct with Union{T, Missing}" begin
        row1 = (id=1, name="Alice")
        obj1 = map_row(registry, OptionalFields, row1)
        @test obj1.id === 1
        @test obj1.name === "Alice"

        row2 = (id=2, name=missing)
        obj2 = map_row(registry, OptionalFields, row2)
        @test obj2.id === 2
        @test ismissing(obj2.name)
    end

    @testset "Error on missing required field" begin
        row = (id=1,)  # Missing 'email' - note the trailing comma for single-element NamedTuple
        @test_throws ErrorException map_row(registry, User, row)
    end

    @testset "Error on missing in non-optional field" begin
        row = (id=1, email=missing)
        @test_throws ErrorException map_row(registry, User, row)
    end
end

@testset "Integration: encode/decode round-trip" begin
    registry = CodecRegistry()

    @testset "Int round-trip" begin
        codec = get_codec(registry, Int)
        value = 42
        @test decode(codec, encode(codec, value)) === value
    end

    @testset "Float64 round-trip" begin
        codec = get_codec(registry, Float64)
        value = 3.14159
        @test decode(codec, encode(codec, value)) === value
    end

    @testset "String round-trip" begin
        codec = get_codec(registry, String)
        value = "Hello, World!"
        @test decode(codec, encode(codec, value)) === value
    end

    @testset "Bool round-trip" begin
        codec = get_codec(registry, Bool)
        @test decode(codec, encode(codec, true)) === true
        @test decode(codec, encode(codec, false)) === false
    end

    @testset "Date round-trip" begin
        codec = get_codec(registry, Date)
        value = Date(2025, 12, 19)
        @test decode(codec, encode(codec, value)) === value
    end

    @testset "DateTime round-trip" begin
        codec = get_codec(registry, DateTime)
        value = DateTime(2025, 12, 19, 10, 30, 45)
        @test decode(codec, encode(codec, value)) === value
    end

    @testset "UUID round-trip" begin
        codec = get_codec(registry, UUID)
        value = uuid4()
        @test decode(codec, encode(codec, value)) === value
    end

    @testset "Missing round-trip" begin
        codec = get_codec(registry, Int)
        @test ismissing(decode(codec, encode(codec, missing)))
    end
end

@testset "Edge Cases and Error Handling" begin
    registry = CodecRegistry()

    @testset "BoolCodec with invalid values" begin
        codec = BoolCodec()
        @test_throws ErrorException decode(codec, 99)
        @test_throws ErrorException decode(codec, -1)
    end

    @testset "Date codec with invalid format" begin
        codec = DateCodec()
        @test_throws Exception decode(codec, "not-a-date")
        @test_throws Exception decode(codec, "2025/12/19")  # Wrong separator
    end

    @testset "DateTime codec with invalid format" begin
        codec = DateTimeCodec()
        @test_throws Exception decode(codec, "not-a-datetime")
    end

    @testset "UUID codec with invalid format" begin
        codec = UUIDCodec()
        @test_throws Exception decode(codec, "not-a-uuid")
        @test_throws Exception decode(codec, "12345")
    end

    @testset "get_codec with unregistered type" begin
        @test_throws ErrorException get_codec(registry, BigInt)
        @test_throws ErrorException get_codec(registry, Vector{Int})
    end

    @testset "map_row with field type mismatch" begin
        struct TypedStruct
            id::Int
            name::String
        end

        # This should work because decode handles type conversion
        row = (id=Int8(1), name="test")
        obj = map_row(registry, TypedStruct, row)
        @test obj.id === 1
        @test obj.name === "test"
    end
end
