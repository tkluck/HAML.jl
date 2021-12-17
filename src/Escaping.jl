"""
    module HAML.Escaping

Contains helper functions for XSS-safe escaping of values
to be interpolated into different contexts.

[1] https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
"""
module Escaping

htmlesc(io::IO) = nothing

function htmlesc(io::IO, val, vals...)
    htmlesc(io, val)
    htmlesc(io, vals...)
end

const SCRATCHPADSIZE = 1024
const SCRATCHPADS = [zeros(UInt8, SCRATCHPADSIZE) for _ in Threads.nthreads()]

@inline function unsafe_set!(ptr, (val, significant_bytes))
    unsafe_store!(Ptr{UInt64}(ptr), val)
    ptr + significant_bytes
end

const var"&amp;" = htol(0x0000003b706d6126), 5
const var"&lt;" = htol(0x000000003b746c26), 4
const var"&gt;" = htol(0x000000003b746726), 4
const var"&quot;" = htol(0x00003b746f757126), 6
const var"&#39;" = htol(0x0000003b39332326), 5

function htmlesc(io::IO, val)
    # important: keep any function calls outside of the area where `buf` is in
    # use, just in case it recursively ends up calling htmlesc again
    stringval = val isa AbstractString ? val : string(val)

    buf = pointer(SCRATCHPADS[Threads.threadid()])
    ptr = buf

    for c in stringval
        if (ptr - buf) > SCRATCHPADSIZE - sizeof(UInt64) # we will at most write an UInt64 below
            unsafe_write(io, buf, ptr - buf)
            ptr = buf
        end
        # from:
        # https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html#rule-1-html-encode-before-inserting-untrusted-data-into-html-element-content
        c == '&'  && (ptr = unsafe_set!(ptr, var"&amp;"); continue)
        c == '<'  && (ptr = unsafe_set!(ptr, var"&lt;"); continue)
        c == '>'  && (ptr = unsafe_set!(ptr, var"&gt;"); continue)
        c == '"'  && (ptr = unsafe_set!(ptr, var"&quot;"); continue)
        c == '\'' && (ptr = unsafe_set!(ptr, var"&#39;"); continue)

        # Char is always big endian in Julia, and we need it in little endian here.
        # See also Base.write(::IO, ::Char).
        x = bswap(reinterpret(UInt32, c))
        unsafe_store!(Ptr{UInt32}(ptr), x)
        ptr += 1
        ptr += x != x & 0xff
        ptr += x != x & 0xffff
        ptr += x != x & 0xffffff
    end
    unsafe_write(io, buf, ptr - buf)
    nothing
end

htmlesc(vals...) = sprint(io -> htmlesc(io, vals...))

struct LiteralHTML{T <: AbstractString}
    html :: T
end

LiteralHTML(f::Function) = LiteralHTML(sprint(f))

Base.:*(x::LiteralHTML, y::LiteralHTML) = LiteralHTML(x.html * y.html)
Base.:*(x::AbstractString, y::LiteralHTML) = LiteralHTML(htmlesc(x, y))
Base.:*(x::LiteralHTML, y::AbstractString) = LiteralHTML(htmlesc(x, y))

function htmlesc(io::IO, val::LiteralHTML)
    print(io, val.html)
end

interpolate(io::IO, f, args...; kwds...) = htmlesc(io, f(args...; kwds...))
interpolate(io::IO, f::typeof(|>), arg, fn) = interpolate(io, fn, arg)
interpolate(io::IO, f::typeof(string), args...) = htmlesc(io, args...)

# Special-case speedups to elide string(...) allocations and character
# escaping.

# from julia Base:
# 2-digit decimal characters ("00":"99")
const _dec_d100 = UInt16[(0x30 + i % 10) << 0x8 + (0x30 + i ÷ 10) for i = 0:99]
const DIGITSCRATCHPADS = [zeros(UInt8, SCRATCHPADSIZE) for _ in Threads.nthreads()]

function htmlesc(io::IO, x::UInt)
    digitsbuf = DIGITSCRATCHPADS[Threads.threadid()]
    n = ndigits(x; base=100)
    @assert n <= SCRATCHPADSIZE

    digits!(@view(digitsbuf[1:n]), x; base=100)

    buf = pointer(SCRATCHPADS[Threads.threadid()])
    ptr = buf

    i = n
    if digitsbuf[i] >= 10
        unsafe_store!(Ptr{UInt16}(ptr), _dec_d100[digitsbuf[i] + 1])
        ptr += 2
    else
        unsafe_store!(Ptr{UInt8}(ptr), UInt8('0') + UInt8(digitsbuf[i]))
        ptr += 1
    end
    for i in n-1:-1:1
        unsafe_store!(Ptr{UInt16}(ptr), _dec_d100[digitsbuf[i] + 1])
        ptr += 2
    end
    unsafe_write(io, buf, ptr - buf)
    nothing
end

function htmlesc(io::IO, x::Int)
    if signbit(x)
        write(io, '-')
        htmlesc(io, ~reinterpret(UInt, x) + 1)
    else
        htmlesc(io, reinterpret(UInt, x))
    end
end

end # module
