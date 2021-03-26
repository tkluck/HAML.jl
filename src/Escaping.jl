"""
    module HAML.Escaping

Contains helper functions for XSS-safe escaping of values
to be interpolated into different contexts.

[1] https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
"""
module Escaping

function htmlesc(io::IO, vals...)
    for val in vals
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
    end
end

htmlesc(vals...) = sprint(io -> htmlesc(io, vals...))

abstract type Context end

Base.print(ctx::Context, val) = error("Not implemented: print $(typeof(val)) to $(typeof(ctx))")

function Base.join(ctx::Context, strings, delim="")
    first = true
    for str in strings
        first ? (first = false) : print(ctx, delim)
        print(ctx, str)
    end
end

struct ElementContentContext{T} <: Context
    io :: T
end

Base.print(ctx::ElementContentContext, val) = htmlesc(ctx.io, val)

struct AttributeNameContext{T} <: Context
    io :: T
end

Base.print(ctx::AttributeNameContext, val) = htmlesc(ctx.io, replace(string(val), "_" => "-"))

struct LiteralHTML{T <: AbstractString}
    html :: T
end

LiteralHTML(f::Function) = LiteralHTML(sprint(f))

Base.print(ctx::ElementContentContext, val::LiteralHTML) = print(ctx.io, val.html)

end # module
