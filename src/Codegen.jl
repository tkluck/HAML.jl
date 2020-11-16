"""
   module HAML.Codegen

Contains functions for turning a HAML/Julia expression tree into
a pure Julia expression tree. This means it takes care of:

 - Evaluate any macro definitions into the correct module to make them
 available for the rest of tree

 - Expand any macros in the correct module, taking care of hygiene: inside of
 of `:escape` nodes the macros should be looked up in the user's module

 - Expand lexically-scoped indentation to string literals

 - Join any adjacent `:hamloutput` nodes and apply as many string
 concatenations as possible at compile time

 - Replace `:hamloutput` and `:hamlio` nodes by either a string concatenation
 mechanism or a `write(io, ...)` operation

All but the last operation are the responsibility of
`generate_haml_writer_codeblock`; the last operation happens in
`replace_output_nodes`.
"""
module Codegen

import Markdown: htmlesc

import ..Hygiene: expand_macros_hygienic, replace_expression_nodes_unescaped, hasnode, mapexpr, isexpr
import ..Hygiene: mapesc, make_hygienic
import ..Parse: @nolinenodes
import ..SourceTools: Source

module InternalNamespace

import ...Escaping: encode, ElementContentContext
import ...Helpers: @output, @htmlesc, @indent, @nextline, @indentation, @indented

macro hygienic(expr)
    return expr
end

end # module InternalNamespace

isstringexpr(val) = isexpr(:string, val)

concatindent(a, b) = if isstringexpr(a) && isstringexpr(b)
    Expr(:string, a.args..., b.args...)
elseif isstringexpr(a)
    Expr(:string, a.args..., b)
elseif isstringexpr(b)
    Expr(:string, a, b.args...)
else
    Expr(:string, a, b)
end
concatindent(a::AbstractString, b::AbstractString) = a * b

function materialize_indentation(expr, cur="")
    expr = replace_expression_nodes_unescaped(:hamlindentation, expr) do args...
        Expr(:hamlindentation, args...)
    end
    if !hasnode(:hamlindented, expr) && !hasnode(:hamlindentation, expr)
        return expr
    elseif expr isa Expr && expr.head == :hamlindented
        return materialize_indentation(expr.args[2], concatindent(cur, expr.args[1]))
    elseif expr isa Expr && expr.head == :hamlindentation
        return cur
    elseif expr isa Expr
        return mapexpr(a -> materialize_indentation(a, cur), expr)
    else
        return expr
    end
end

isoutput(expr) = expr isa Expr && expr.head == :hamloutput

extendoutput!(output) = output

function extendoutput!(output, x, xs...)
    if !isempty(output) && output[end] isa AbstractString && x isa AbstractString
        output[end] *= x
    else
        push!(output, x)
    end
    extendoutput!(output, xs...)
end

function merge_outputs(expr)
    if expr isa Expr && expr.head == :block
        prev = nothing
        args = []
        for a in expr.args
            a = merge_outputs(a)
            if isoutput(prev) && isoutput(a)
                extendoutput!(prev.args, a.args...)
            elseif isoutput(a)
                prev = Expr(:hamloutput)
                extendoutput!(prev.args, a.args...)
                push!(args, prev)
            else
                prev = a
                push!(args, prev)
            end
        end
        if length(args) == 1 && isoutput(args[1])
            return args[1]
        else
            return Expr(:block, args...)
        end
    elseif expr isa Expr && expr.head == :escape
        arg = merge_outputs(expr.args[1])
        if isoutput(arg)
            return Expr(:hamloutput, map(esc, arg.args)...)
        else
            return Expr(:escape, arg)
        end
    elseif expr isa Expr
        return mapexpr(merge_outputs, expr)
    else
        return expr
    end
end

function extract_toplevel_macro_defs!(code)
    res = []
    if isexpr(:block, code)
        for a in code.args
            isexpr(:macro, a) && push!(res, a)
        end
        filter!(a -> !isexpr(:macro, a), code.args)
    end
    return res
end

function generate_haml_writer_codeblock(usermod, source, extraindent="")
    code = Meta.parse(source)
    macros = extract_toplevel_macro_defs!(code)
    for m in macros
        m.args[2] = mapesc(m.args[2]) do a
            Expr(:$, a)
        end
        m.args[2] = Expr(:block, Expr(:quote, m.args[2]))
        macroname = Symbol("@", m.args[1].args[1])
        m.args[1].args[1] = gensym(m.args[1].args[1])
        macroinstance = Base.eval(InternalNamespace, m)
        Base.eval(usermod, :( const $macroname = $macroinstance ))
    end
    code = expand_macros_hygienic(InternalNamespace, usermod, code)
    code = Expr(:hamlindented, extraindent, code)
    code = materialize_indentation(code)
    code = merge_outputs(code)
    return code
end

function replace_output_nodes(code, io)
    code = replace_expression_nodes_unescaped(:hamloutput, code) do esc, args...
        write_statements = map(args) do a
            # each in its own statement; no need to put everything on the
            # stack before starting sending stuff out on the io. (By this
            # time, static strings have already been concatenated.)
            :( write($io, $(esc(a))) )
        end
        Expr(:block, write_statements...)
    end
    code = replace_expression_nodes_unescaped(:hamlio, code) do esc
        io
    end
    return code
end

"""
    @haml_str(source)
    haml"..."

Include HAML source code into Julia source. The code will be
executed in the context (module / function) where it appears
and has access to the same variables.

# Example
```jldoctest
julia> using HAML

julia> haml"%p Hello, world"
"<p>Hello, world</p>"
```
"""
macro haml_str(source)
    # FIXME: off-by-one because triple-quoted haml""" has its
    # first character on the next line.
    loc = LineNumberNode(__source__.line + 1, __source__.file)
    code = generate_haml_writer_codeblock(__module__, Source(loc, source))

    if isoutput(code) && !hasnode(:hamlio, code)
        if length(code.args) == 1 && code.args[1] isa String
            return code.args[1]
        else
            code = Expr(:string, code.args...)
        end
    else
        code = replace_output_nodes(code, :io)
        code = @nolinenodes quote
            io = IOBuffer()
            $code
            String(take!(io))
        end
    end

    code = make_hygienic(InternalNamespace, code)
    return esc(code)
end



end # module
