module Codegen

import Base.Meta: parse, quot

import DataStructures: OrderedDict
import Markdown: htmlesc

import ..Hygiene: replace_macro_hygienic, deref
import ..Parse: @capture, @mustcapture, Source

include("Attributes.jl")
import .Attributes: mergeattributes, writeattributes

function filterlinenodes(expr)
    if expr isa Expr && expr.head == :block
        args = filter(e -> !(e isa LineNumberNode), expr.args)
        return Expr(expr.head, args...)
    elseif expr isa Expr && expr.head == :$
        return expr
    elseif expr isa Expr
        return Expr(expr.head, map(filterlinenodes, expr.args)...)
    else
        return expr
    end
end

macro nolinenodes(expr)
    @assert expr.head == :quote
    args = map(filterlinenodes, expr.args)
    return esc(Expr(:quote, args...))
end

indentlength(s) = mapreduce(c -> c == '\t' ? 8 : 1, +, s, init=0)
indentlength(::Nothing) = -1

function materialize_indentation(expr, cur="")
    if expr isa Expr && expr.head == :hamlindented
        return materialize_indentation(expr.args[2], cur * expr.args[1])
    elseif expr isa Indentation
        return cur
    elseif expr isa Expr
        args = map(a -> materialize_indentation(a, cur), expr.args)
        return Expr(expr.head, args...)
    else
        return expr
    end
end

extendoutput!(output) = output

function extendoutput!(output, x, xs...)
    if !isempty(output) && output[end] isa AbstractString && x isa AbstractString
        output[end] *= x
    else
        push!(output, x)
    end
    extendoutput!(output, xs...)
end

function extendblock!(block, expr)
    @assert block isa Expr && block.head == :block
    if expr isa Expr && expr.head == :block
        for e in expr.args
            extendblock!(block, e)
        end
        return
    elseif expr isa Expr && expr.head == :macrocall && expr.args[1] == Symbol("@output")
        prev = block.args[end]
        if prev isa Expr && prev.head == :macrocall && prev.args[1] == Symbol("@output")
            extendoutput!(prev.args, expr.args[3:end]...)
            return
        end
    end
    push!(block.args, expr)
end

function parse_tag_stanza!(code, curindent, source)
    @mustcapture source "Expecting a tag name" r"(?:%(?<tagname>[A-Za-z0-9]+)?)?"
    tagname = something(tagname, "div")

    attr = OrderedDict()
    while @capture source r"""
        (?=(?<openbracket>\())
        |
        (?:
            (?<sigil>\.|\#)
            (?<value>[A-Za-z0-9]+)
        )
    """x
        if !isnothing(openbracket)
            attr_expr = parse(source, greedy=false)
            if attr_expr.head == :(=) || attr_expr.head == :...
                attr_expr = :( ($attr_expr,) )
            elseif attr_expr.head == :call && attr_expr.args[1] == :(=>)
                attr_expr = :( ($attr_expr,) )
            end
            attr_expr.head == :tuple || error(source, "Expecting key=value expression")
            attr = mergeattributes(attr, attr_expr.args...)
        else
            if sigil == "."
                attr = mergeattributes(attr, :class => value)
            elseif sigil == "#"
                attr = mergeattributes(attr, :id    => value)
            else
                error(source, "Unknown sigil: $sigil")
            end
        end
    end

    attr = writeattributes(attr)

    @mustcapture source "Expecting '<', '=', '/', or whitespace" r"""
        (?<eatwhitespace>\<)?
        (?:
            (?<equalssign>\=)
            |
            (?<closingslash>/)?
            (?:
              \h+
              (?<rest_of_line>.+)
            )?
            $
            (?<newline>\v*)
        )
    """mx

    code_for_inline_val = nothing
    if !isnothing(equalssign)
        @mustcapture source "Expecting an expression" r"""
            \h*
            (?<code_to_parse>
                (?:,\h*(?:\#.*)?\v|.)*
            )
            $(?<newline>\v?)
        """mx
        expr = parse(source, code_to_parse)
        code_for_inline_val = @nolinenodes quote
            @htmlesc string($(esc(expr)))
        end
    elseif !isnothing(rest_of_line)
        code_for_inline_val = @nolinenodes quote
            @output $rest_of_line
        end
    end

    body = @nolinenodes quote end
    parseresult = parse_indented_block!(body, curindent, source)
    if isnothing(parseresult)
        haveblock = false
    else
        if isnothing(eatwhitespace)
            indentation, newline = parseresult
            body = filterlinenodes(:( @indented($indentation, (@nextline; $body)); @nextline ))
        end
        haveblock = true
    end
    if !isnothing(closingslash)
        @assert isnothing(code_for_inline_val)
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attr
            @output $" />"
        end)
    elseif haveblock
        @assert isnothing(code_for_inline_val)
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attr
            @output ">"
            $body
            @output $"</$tagname>"
        end)
    else
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attr
            @output ">"
            $code_for_inline_val
            @output $"</$tagname>"
        end)
    end
    return newline
end

indentdiff(a, b::Nothing) = a

function indentdiff(a, b)
    startswith(a, b) || error("Expecting uniform indentation")
    return a[1+length(b):end]
end

function parse_indented_block!(code, curindent, source)
    controlflow_this = nothing
    controlflow_prev = nothing
    firstindent = nothing
    newline = ""
    while true
        controlflow_this, controlflow_prev = nothing, controlflow_this
        if isempty(source) || indentlength(match(r"\A\h*", source).match) <= indentlength(curindent)
            isnothing(firstindent) && return nothing
            return indentdiff(firstindent, curindent), newline
        end
        if @capture source r"""
            ^
            (?<indent>\h*)                            # indentation
            (?:
              (?<elseblock>-\h*else\h*$\v?)
              |
              (?=(?<sigil>%|\#|\.|-\#|-|=|\\|/|!!!))? # stanza type
              (?:-\#|-|=|\\|/|!!!)?                   # consume these stanza types
            )
        """xm
            if isnothing(firstindent)
                firstindent = indent
            elseif !isnothing(elseblock)
                block = @nolinenodes quote end
                push!(controlflow_prev.args, block)
                parseresult = parse_indented_block!(block, indent, source)
                if !isnothing(parseresult)
                    _, newline = parseresult
                end
                continue
            else
                isnothing(curindent) || firstindent == indent || error(source, "Jagged indentation")
                extendblock!(code, :( @output $newline @indentation ))
            end
            push!(code.args, LineNumberNode(source))

            if sigil in ("%", "#", ".")
                newline = parse_tag_stanza!(code, indent, source)
            elseif sigil == "-#"
                @mustcapture source "Expecting a comment" r"\h*(?<rest_of_line>.*)$(?<newline>\v?)"m
                while indentlength(match(r"\A\h*", source).match) > indentlength(indent)
                    @mustcapture source "Expecting comment continuing" r".*$\v?"m
                end
                newline = ""
            elseif sigil == "-"
                @mustcapture source "Expecting an expression" r"""
                    \h*
                    (?<code_to_parse>
                        (?:,\h*(?:\#.*)?\v|.)*
                    )$\v?
                """mx
                if startswith(code_to_parse, r"\h*(?:for|while)\b")
                    block = parse(source, "$code_to_parse\nend", code_to_parse)
                    block.args[1] = esc(block.args[1])
                    body_of_loop = block.args[2] = @nolinenodes quote
                        !first && @nextline
                        first = false
                    end
                    parseresult = parse_indented_block!(body_of_loop, indent, source)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                    extendblock!(code, @nolinenodes quote
                        let first=true
                            $block
                        end
                    end)
                    controlflow_this = block
                elseif startswith(code_to_parse, r"\h*if\b")
                    block = parse(source, "$code_to_parse\nend", code_to_parse)
                    block.args[1] = esc(block.args[1])
                    extendblock!(code, block)
                    parseresult = parse_indented_block!(block.args[2], indent, source)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                    controlflow_this = block
                elseif (block = parse(source, "$code_to_parse\nend", code_to_parse, raise=false); block isa Expr && block.head == :do)
                    block.args[1] = esc(block.args[1])
                    block.args[2].args[1] = esc(block.args[2].args[1])
                    body_of_fun = block.args[2].args[2] = @nolinenodes quote
                        !first && @nextline
                        first = false
                    end
                    parseresult = parse_indented_block!(body_of_fun, indent, source)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                    extendblock!(code, @nolinenodes quote
                        let first=true
                            $block
                        end
                    end)
                else
                    expr = parse(source, code_to_parse)
                    extendblock!(code, esc(expr))
                    newline = ""
                end
            elseif sigil == "="
                @mustcapture source "Expecting an expression" r"""
                    \h*
                    (?<code_to_parse>
                        (?:.*|,\h*\v)*
                    )
                    $(?<newline>\v?)
                """mx
                expr = parse(source, code_to_parse)
                extendblock!(code, @nolinenodes quote
                    let val = $(esc(expr))
                        @htmlesc string(val)
                    end
                end)
            elseif sigil == "\\" || sigil == nothing
                @mustcapture source "Expecting literal data" r"\h*(?<rest_of_line>.*)$(?<newline>\v?)"m
                extendblock!(code, @nolinenodes quote
                    @output $"$rest_of_line"
                end)
            elseif sigil == "/"
                @mustcapture source "Expecting a comment" r"\h*(?<rest_of_line>.*)$(?<newline>\v?)"m
                if !isempty(rest_of_line)
                    extendblock!(code, @nolinenodes quote
                        @output $"<!-- $rest_of_line -->"
                    end)
                else
                    body = @nolinenodes quote end
                    parseresult = parse_indented_block!(body, indent, source)
                    if !isnothing(parseresult)
                        indentation, newline = parseresult
                        body = filterlinenodes(:( @indented $indentation (@indent; $body) ))
                        extendblock!(code, @nolinenodes quote
                            @output $"<!--\n"
                            $body
                            @nextline $"-->"
                        end)
                    end
                end
            elseif sigil == "!!!"
                @mustcapture source "Only support '!!! 5'" r"\h*5\h*$(?<newline>\v?)"m
                extendblock!(code, @nolinenodes quote
                    @output $"<!DOCTYPE html>"
                end)
            else
                error(source, "Unrecognized sigil: $sigil")
            end
        else
            error(source, "Unrecognized")
        end
    end
end

function generate_haml_writer_codeblock(source)
    code = @nolinenodes quote end
    parseresult = parse_indented_block!(code, nothing, source)
    if isnothing(parseresult)
        return code
    else
        indentation, newline = parseresult
        return @nolinenodes quote
            @output $indentation
            $code
            @output $newline
        end
    end
end

macro haml_str(source)
    code = generate_haml_writer_codeblock(Source(source, __source__))
    code = replace_macro_hygienic(@__MODULE__, __module__, code, at_io => :io)
    code = materialize_indentation(code)

    @nolinenodes quote
        io = IOBuffer()
        $code
        String(take!(io))
    end
end

macro io()
    error("The @io macro can only be used from within a HAML template")
end

mutable struct Indentation
end

macro indentation()
    Indentation()
end


macro indented(indentation, expr)
    Expr(:hamlindented, esc(indentation), esc(expr))
end

macro nextline(expr...)
    expr = map(esc, expr)
    :( @output "\n" @indentation() $(expr...) )
end

macro output(expr...)
    expr = map(esc, expr)
    :( write(@io, $(expr...)) )
end

macro indent()
    :( @output @indentation )
end

macro htmlesc(expr...)
    :( @output $htmlesc($(expr...)) )
end

const at_io = getproperty(@__MODULE__, Symbol("@io"))

end # module
