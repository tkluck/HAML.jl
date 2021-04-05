"""
    module HAML.Escaping

Contains helper functions for XSS-safe escaping of values
to be interpolated into different contexts.

[1] https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
"""
module Escaping

import ..Hygiene: isexpr

htmlesc(io::IO) = nothing
function htmlesc(io::IO, val, vals...)
    for c in string(val)
        # from:
        # https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html#rule-1-html-encode-before-inserting-untrusted-data-into-html-element-content
        c == '&'  && (write(io, "&amp;"); continue)
        c == '<'  && (write(io, "&lt;"); continue)
        c == '>'  && (write(io, "&gt;"); continue)
        c == '"'  && (write(io, "&quot;"); continue)
        c == '\'' && (write(io, "&#39;"); continue)
        #c == '/'  && (write(io, "&#47;"); continue)
        write(io, c)
    end
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

end # module
