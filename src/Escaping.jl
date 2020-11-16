"""
    module HAML.Escaping

Contains helper functions for XSS-safe escaping of values
to be interpolated into different contexts.

[1] https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
"""
module Escaping

import Markdown: htmlesc

abstract type Context end

encode(ctx::Context, vals...) = error()

struct ElementContentContext <: Context end

encode(ctx::ElementContentContext, val) = htmlesc(string(val))
encode(ctx::ElementContentContext, val, vals...) = encode(ctx, val) * encode(ctx, vals...)

struct AttributeNameContext <: Context end
struct AttributeValueContext <: Context
    attribute :: Symbol
end

end # module
