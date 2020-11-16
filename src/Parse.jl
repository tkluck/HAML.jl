"""
    module HAML.Parse

Contains functions for turning HAML source code into an expression tree.
The most important entrypoint is

    Meta.parse(::HAML.SourceTools.Source, kwds...)

The result of parsing is a normal Julia expression tree, except that the set of
expression nodes is extended with the following nodes.

    - `Expr(:hamloutput, args...)` - represents that each element of `args`
    should be stringified and appended to the output string

    - `Expr(:hamlindentation)` - represents a string value for the current
    level of indentation: usually a certain number of tabs or spaces.

    - `Expr(:hamlindented, indent, expr)` - represents that for the (lexical)
    scope `expr`, the current level of indentation should be increased by
    concatenating `indent`.

    - `Expr(:hamlio)` - represents a value of type `IO` that can be used as an
    argument for `Base.write`, resulting in appending to the output string.
    (Usually, one should use `:hamloutput` instead.)

Also note that any Julia code embedded in the HAML source will be wrapped in an
`Expr(:escape, ...)` node.
"""
module Parse

import DataStructures: OrderedDict

import ..Attributes: mergeattributes, writeattributes
import ..Hygiene: mapexpr, escapelet
import ..SourceTools: @capture, @mustcapture, Source, parse_juliacode, parse_contentline, parse_expressionline

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
            (?<value>[A-Za-z0-9][A-Za-z0-9-]*)
        )
    """x
        if !isnothing(openbracket)
            loc = source.ix
            attr_expr = parse_juliacode(source, greedy=false)
            attr_expr isa Expr || error(source, loc, "Expecting key=value expression")
            if attr_expr.head == :(=) || attr_expr.head == :...
                attr_expr = :( ($attr_expr,) )
            elseif attr_expr.head == :call && attr_expr.args[1] == :(=>)
                attr_expr = :( ($attr_expr,) )
            end
            attr_expr.head == :tuple || error(source, loc, "Expecting key=value expression")
            attr = mergeattributes(attr, attr_expr.args...)
        else
            if sigil == "."
                attr = mergeattributes(attr, :class => value)
            elseif sigil == "#"
                attr = mergeattributes(attr, :id    => value)
            else
                error(source, "(unreachable) Unknown sigil: $sigil")
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
    inlinevalloc = source.ix
    if !isnothing(equalssign)
        startix = source.ix
        expr, head, newline = parse_expressionline(source)
        if !isnothing(head)
            error(source, startix, "Block not supported after =")
        end
        code_for_inline_val = @nolinenodes quote
            @output encode(ElementContentContext(), $(esc(expr)))
        end
    else
        code_for_inline_val, newline = parse_contentline(source)
    end

    body = @nolinenodes quote end
    blockloc = source.ix
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
        isnothing(code_for_inline_val) || error(source, inlinevalloc, "inline value not supported after /")
        haveblock && error(source, blockloc, "block not supported after /")
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attr
            @output $" />"
        end)
    elseif haveblock
        isnothing(code_for_inline_val) || error(source, blockloc, "block not supported after =")
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attr
            @output ">"
            $body
            @output $"</$tagname>"
        end)
    elseif !isnothing(code_for_inline_val)
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attr
            @output ">"
            $code_for_inline_val
            @output $"</$tagname>"
        end)
    else
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attr
            @output $"></$tagname>"
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
                !isempty(newline) && extendblock!(code, :( @output $newline @indentation ))
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
                startix = source.ix
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
                elseif head == :block
                    push!(code.args, loc)
                    parseresult = parse_indented_block!(expr, indent, source)
                    extendblock!(code, expr)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                elseif head == :let
                    expr = escapelet(expr)
                    push!(code.args, loc)
                    extendblock!(code, expr)
                    parseresult = parse_indented_block!(expr.args[2], indent, source)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                # TODO: this works but the resulting function closes over `io`
                # and it may be in module scope. We need to define proper semantics
                # before exposing this.
                #elseif head == :function
                #    expr.args[1] = esc(expr.args[1])
                #    push!(code.args, loc)
                #    extendblock!(code, expr)
                #    parseresult = parse_indented_block!(expr.args[2], indent, source)
                #    if !isnothing(parseresult)
                #        _, newline = parseresult
                #    end
                elseif head == :macro
                    push!(code.args, loc)
                    extendblock!(code, expr)
                    body_of_fun = @nolinenodes quote
                    end
                    expr.args[2] = body_of_fun #Expr(:block, Expr(:quote, body_of_fun))
                    parseresult = parse_indented_block!(body_of_fun, indent, source)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                        extendblock!(body_of_fun, @nolinenodes quote
                            @output $newline
                        end)
                    end
                    newline = ""
                elseif isnothing(head)
                    push!(code.args, loc)
                    extendblock!(code, esc(expr))
                    newline = ""
                else
                    error(source, startix, "Unexpected expression head: $head")
                end
            elseif sigil == "="
                startix = source.ix
                expr, head, newline = parse_expressionline(source)
                if !isnothing(head)
                    error(source, startix, "Block not supported after =")
                end
                extendblock!(code, @nolinenodes quote
                    @output encode(ElementContentContext(), $(esc(expr)))
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
                error(source, "(unreachable) Unrecognized sigil: $sigil")
            end
        else
            error(source, "Unrecognized")
        end
    end
end

function Meta.parse(source::Source; kwds...)
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
    return code
end

end # module
