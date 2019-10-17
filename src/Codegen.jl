module Codegen

import Base.Meta: parse, quot

import DataStructures: OrderedDict
import Markdown: htmlesc

import ..Attributes: mergeattributes, writeattributes
import ..Hygiene: expand_macros_hygienic, replace_expression_nodes_unescaped, hasnode, mapexpr
import ..Parse: @capture, @mustcapture, Source, parse_contentline, parse_expressionline

function filterlinenodes(expr)
    if expr isa Expr && expr.head == :block
        args = filter(e -> !(e isa LineNumberNode), expr.args)
        return Expr(expr.head, args...)
    elseif expr isa Expr && expr.head == :$
        return expr
    elseif expr isa Expr
        return mapexpr(filterlinenodes, expr)
    else
        return expr
    end
end

macro nolinenodes(expr)
    @assert expr.head == :quote
    return esc(mapexpr(filterlinenodes, expr))
end

indentlength(s) = mapreduce(c -> c == '\t' ? 8 : 1, +, s, init=0)
indentlength(::Nothing) = -1

function materialize_indentation(expr, cur="")
    if !hasnode(:hamlindented, expr) && !hasnode(:hamlindentation, expr)
        return expr
    elseif expr isa Expr && expr.head == :hamlindented
        return materialize_indentation(expr.args[2], cur * expr.args[1])
    elseif expr isa Expr && expr.head == :hamlindentation
        return cur
    elseif expr isa Expr
        return mapexpr(a -> materialize_indentation(a, cur), expr)
    else
        return expr
    end
end

function extendblock!(block, expr)
    @assert block isa Expr && block.head == :block
    if expr isa Expr && expr.head == :block
        for e in expr.args
            extendblock!(block, e)
        end
    else
        push!(block.args, expr)
    end
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
            (?:\h*)
        )
    """mx

    code_for_inline_val = nothing
    if !isnothing(equalssign)
        startix = source.ix
        expr, head, newline = parse_expressionline(source)
        if !isnothing(head)
            error(source, startix, "Block not supported after =")
        end
        code_for_inline_val = @nolinenodes quote
            @htmlesc string($(esc(expr)))
        end
    else
        code_for_inline_val, newline = parse_contentline(source)
    end

    body = @nolinenodes quote end
    parseresult = parse_indented_block!(body, curindent, source)
    if isnothing(parseresult)
        haveblock = false
    else
        if isnothing(eatwhitespace)
            indentation, newline = parseresult
            body = Expr(
                :block,
                Expr(:hamlindented, indentation,
                    filterlinenodes(:(@nextline; $body))
                ),
                :(@nextline),
            )
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
              (?<elseblock>-\h*else\h*(\#.*)?$\v?)
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

            if sigil in ("%", "#", ".")
                newline = parse_tag_stanza!(code, indent, source)
            elseif sigil == "-#"
                @mustcapture source "Expecting a comment" r"\h*(?<rest_of_line>.*)$(?<newline>\v?)"m
                while indentlength(match(r"\A\h*", source).match) > indentlength(indent)
                    @mustcapture source "Expecting comment continuing" r".*$\v?"m
                end
                newline = ""
            elseif sigil == "-"
                loc = LineNumberNode(source)
                expr, head, newline = parse_expressionline(source, with_linenode=false)
                if head in (:for, :while)
                    expr.args[1] = esc(expr.args[1])
                    body_of_loop = expr.args[2] = @nolinenodes quote
                        !first && @nextline
                        first = false
                    end
                    parseresult = parse_indented_block!(body_of_loop, indent, source)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                    push!(code.args, loc)
                    extendblock!(code, @nolinenodes quote
                        let first=true
                            $expr
                        end
                    end)
                    controlflow_this = expr
                elseif head == :if
                    expr.args[1] = esc(expr.args[1])
                    push!(code.args, loc)
                    extendblock!(code, expr)
                    parseresult = parse_indented_block!(expr.args[2], indent, source)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                    controlflow_this = expr
                elseif head == :do
                    expr.args[1] = esc(expr.args[1])
                    expr.args[2].args[1] = esc(expr.args[2].args[1])
                    body_of_fun = expr.args[2].args[2] = @nolinenodes quote
                        !first && @nextline
                        first = false
                    end
                    parseresult = parse_indented_block!(body_of_fun, indent, source)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                    push!(code.args, loc)
                    extendblock!(code, @nolinenodes quote
                        let first=true
                            $expr
                        end
                    end)
                elseif isnothing(head)
                    push!(code.args, LineNumberNode(source))
                    extendblock!(code, esc(expr))
                    newline = ""
                else
                    error(source, "Unexpected expression head: $head")
                end
            elseif sigil == "="
                startix = source.ix
                expr, head, newline = parse_expressionline(source)
                if !isnothing(head)
                    error(source, startix, "Block not supported after =")
                end
                extendblock!(code, @nolinenodes quote
                    @htmlesc string($(esc(expr)))
                end)
            elseif sigil == "\\" || sigil == nothing
                @mustcapture source "Expecting space" r"\h*"
                linecode, newline = parse_contentline(source)
                extendblock!(code, linecode)
            elseif sigil == "/"
                @mustcapture source "Expecting space" r"\h*"
                linecode, newline = parse_contentline(source)
                if !isnothing(linecode)
                    extendblock!(code, @nolinenodes quote
                        @output "<!-- "
                        $linecode
                        @output " -->"
                    end)
                else
                    body = @nolinenodes quote end
                    parseresult = parse_indented_block!(body, indent, source)
                    if !isnothing(parseresult)
                        indentation, newline = parseresult
                        body = filterlinenodes(:( @indented $indentation (@nextline; $body) ))
                        extendblock!(code, @nolinenodes quote
                            @output $"<!--"
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
                prev = deepcopy(a)
                push!(args, prev)
            end
        end
        if length(args) == 1 && isoutput(args[1])
            return args[1]
        else
            return Expr(:block, args...)
        end
    elseif expr isa Expr
        return mapexpr(merge_outputs, expr)
    else
        return expr
    end
end

function generate_haml_writer_codeblock(usermod, source, extraindent="")
    code = @nolinenodes quote end
    parseresult = parse_indented_block!(code, nothing, source)
    if !isnothing(parseresult)
        indentation, newline = parseresult
        code = @nolinenodes quote
            @output $indentation
            $(code.args...)
            @output $newline
        end
    end
    code = expand_macros_hygienic(@__MODULE__, usermod, code)
    code = Expr(:hamlindented, extraindent, code)
    code = materialize_indentation(code)
    code = merge_outputs(code)
    return code
end

function replace_output_nodes(code, io)
    code = replace_expression_nodes_unescaped(:hamloutput, code) do (args...)
        write_statements = map(args) do a
            # each in its own statement; no need to put everything on the
            # stack before starting sending stuff out on the io. (By this
            # time, static strings have already been concatenated.)
            :( write($io, $a) )
        end
        Expr(:block, write_statements...)
    end
    code = replace_expression_nodes_unescaped(:hamlio, code) do
        io
    end
    return code
end

macro haml_str(source)
    # FIXME: off-by-one because triple-quoted haml""" has its
    # first character on the next line.
    loc = LineNumberNode(__source__.line + 1, __source__.file)
    code = generate_haml_writer_codeblock(__module__, Source(source, loc))

    if isoutput(code) && !hasnode(:hamlio, code)
        return Expr(:string, code.args...)
    end

    code = replace_output_nodes(code, :io)

    return @nolinenodes quote
        io = IOBuffer()
        $code
        String(take!(io))
    end
end

macro io()
    Expr(:hamlio)
end

macro indentation()
    Expr(:hamlindentation)
end


macro indented(indentation, expr)
    Expr(:hamlindented, esc(indentation), esc(expr))
end

macro output(expr...)
    expr = map(esc, expr)
    Expr(:hamloutput, expr...)
end

macro indent()
    :( @output @indentation )
end

macro nextline(expr...)
    expr = map(esc, expr)
    :( @output "\n" @indentation() $(expr...) )
end

macro htmlesc(expr...)
    :( @output $htmlesc($(expr...)) )
end

end # module
