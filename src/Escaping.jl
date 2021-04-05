"""
    module HAML.Escaping

Contains helper functions for XSS-safe escaping of values
to be interpolated into different contexts.

[1] https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
"""
module Escaping

import ..Hygiene: isexpr

const SCRATCHPADSIZE = 1024
const SCRATCHPADS = [zeros(UInt8, SCRATCHPADSIZE) for _ in Threads.nthreads()]

@inline function unsafe_set!(ptr, val::UInt64, significant_bytes)
    unsafe_store!(Ptr{UInt64}(ptr), val)
    ptr + significant_bytes
end

htmlesc(io::IO) = nothing

function htmlesc(io::IO, val, vals...)
    stringval = string(val)

    buf = pointer(SCRATCHPADS[Threads.threadid()])
    ptr = buf

    for c in stringval
        if (ptr - buf) > SCRATCHPADSIZE - 8 # we will at most write an UInt64 below
            unsafe_write(io, buf, ptr - buf)
            ptr = buf
        end
        # from:
        # https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html#rule-1-html-encode-before-inserting-untrusted-data-into-html-element-content
        c == '&'  && (ptr = unsafe_set!(ptr, htol(0x0000003b706d6126), 5 #= "&amp;"  =#); continue)
        c == '<'  && (ptr = unsafe_set!(ptr, htol(0x000000003b746c26), 4 #= "&lt;"   =#); continue)
        c == '>'  && (ptr = unsafe_set!(ptr, htol(0x000000003b746726), 4 #= "&gt;"   =#); continue)
        c == '"'  && (ptr = unsafe_set!(ptr, htol(0x00003b746f757126), 6 #= "&quot;" =#); continue)
        c == '\'' && (ptr = unsafe_set!(ptr, htol(0x0000003b39332326), 5 #= "&#39;"  =#); continue)

        # Char is always big endian in Julia, and we need it in little endian here.
        # See also Base.write(::IO, ::Char).
        x = bswap(reinterpret(UInt32, c))
        unsafe_store!(Ptr{UInt32}(ptr), x)
        ptr += max(1, div(32 - leading_zeros(x), 8, RoundUp))
    end
    unsafe_write(io, buf, ptr - buf)

    htmlesc(io, vals...)
end

htmlesc(vals...) = sprint(io -> htmlesc(io, vals...))

struct LiteralHTML{T <: AbstractString}
    html :: T
end

LiteralHTML(f::Function) = LiteralHTML(sprint(f))

Base.:*(x::LiteralHTML, y::LiteralHTML) = LiteralHTML(x.html * y.html)
Base.:*(x::AbstractString, y::LiteralHTML) = LiteralHTML(htmlesc(x, y))
Base.:*(x::LiteralHTML, y::AbstractString) = LiteralHTML(htmlesc(x, y))

function htmlesc(io::IO, val::LiteralHTML, vals...)
    print(io, val.html)
    htmlesc(io, vals...)
end

interpolate(io::IO, f, args...; kwds...) = htmlesc(io, f(args...; kwds...))
interpolate(io::IO, f::typeof(|>), arg, fn) = interpolate(io, fn, arg)
interpolate(io::IO, f::typeof(string), args...) = htmlesc(io, args...)

# Special-case speedups to elide string(...) allocations and character
# escaping.

# from julia Base:
# 2-digit decimal characters ("00":"99")
const _dec_d100 = UInt16[(0x30 + i % 10) << 0x8 + (0x30 + i ÷ 10) for i = 0:99]

function htmlesc(io::IO, x::UInt, vals...)
    buffer = SCRATCHPADS[Threads.threadid()]
    n = ndigits(x; base=100)
    @assert n <= SCRATCHPADSIZE

    digits!(@view(buffer[1:n]), x; base=100)

    i = n
    if buffer[i] >= 10
        write(io, _dec_d100[buffer[i] + 1])
    else
        write(io, '0' + buffer[i])
    end
    for i in n-1:-1:1
        write(io, _dec_d100[buffer[i] + 1])
    end
    htmlesc(io, vals...)
end

function htmlesc(io::IO, x::Int, vals...)
    if signbit(x)
        write(io, '-')
        htmlesc(io, ~reinterpret(UInt, x) + 1, vals...)
    else
        htmlesc(io, reinterpret(UInt, x), vals...)
    end
end

end # module
