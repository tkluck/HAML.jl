"""
    module HAML.Escaping

Contains helper functions for XSS-safe escaping of values
to be interpolated into different contexts.

[1] https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
"""
module Escaping

htmlesc(val) = sprint(val) do io, val
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

abstract type Context end

encode(ctx::Context, val) = error()
encode(ctx::Context, val, vals...) = encode(ctx, val) * encode(ctx, vals...)

struct ElementContentContext <: Context end
encode(ctx::ElementContentContext, val) = htmlesc(val)

struct AttributeNameContext <: Context end
encode(ctx::AttributeNameContext, val) = htmlesc(replace(string(val), "_" => "-"))

struct AttributeValueContext <: Context
    attr :: Symbol
end
encode(ctx::AttributeValueContext) = nothing
encode(ctx::AttributeValueContext, val) = htmlesc(val)
encode(ctx::AttributeValueContext, val::Nothing) = nothing
encode(ctx::AttributeValueContext, val::Bool) = val ? string(ctx.attr) : nothing
encode(ctx::AttributeValueContext, vals...) = if ctx.attr == :class
    join((encode(ctx, v) for v in vals), " ")
elseif ctx.attr == :id
    join((encode(ctx, v) for v in vals), "-")
else
    encode(ctx, last(val))
end

struct LiteralHTML{T <: AbstractString}
    html :: T
end

encode(::ElementContentContext, val::LiteralHTML) = val.html

end # module
