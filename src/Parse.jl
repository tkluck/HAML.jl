"""
    module HAML.Parse

Contains functions for turning HAML source code into an expression tree.
The most important entrypoint is

    Meta.parse(::HAML.SourceTools.Source, kwds...)

The result of parsing is a normal Julia expression tree, except that the set of
expression nodes is extended with the following nodes.

    - `Expr(:hamltag, args...)` - represents an html tag with attributes
    and contents.

    - `Expr(:hamloutput, args...)` - represents that each element of `args`
    should be stringified, escaped, and appended to the output string

    - `Expr(:hamlindentation)` - represents a string value for the current
    level of indentation: usually a certain number of tabs or spaces.

    - `Expr(:hamlindented, indent, expr)` - represents that for the (lexical)
    scope `expr`, the current level of indentation should be increased by
    concatenating `indent`.

Also note that any Julia code embedded in the HAML source will be wrapped in an
`Expr(:escape, ...)` node.
"""
module Parse

import ..Attributes: AttributeVals, mergeexpr, writeattributes
import ..Escaping: LiteralHTML
import ..Hygiene: mapexpr, escapelet, isexpr, @nolinenodes, filterlinenodes
import ..SourceTools: @capture, @mustcapture, Source, parse_juliacode, parse_contentline, parse_expressionline

indentlength(s) = mapreduce(c -> c == '\t' ? 8 : 1, +, s, init=0)
indentlength(::Nothing) = -1

function extendblock!(target, source)
    @assert isexpr(:block, target)
    if isexpr(:block, source)
        for arg in source.args
            extendblock!(target, arg)
        end
    else
        push!(target.args, source)
    end
    return target
end

function parse_tag_stanza!(code, curindent, source)
    stanza_line_number_node = LineNumberNode(source)

    @mustcapture source "Expecting a tag name" r"(?:%(?<tagname>[A-Za-z0-9]+)?)?"
    tagname = something(tagname, "div")

    attrs = Expr(:hamlattrs)

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
            append!(attrs.args, attr_expr.args)
        else
            if sigil == "."
                push!(attrs.args, Expr(:(=), :class, value))
            elseif sigil == "#"
                push!(attrs.args, Expr(:(=), :id, value))
            else
                error(source, "(unreachable) Unknown sigil: $sigil")
            end
        end
    end

    #attrs = writeattributes(stanza_line_number_node, attrs)

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
            @output $(esc(expr))
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
    haveclosingslash = !isnothing(closingslash)
    contents = haveblock ? body : code_for_inline_val

    if haveclosingslash && !isnothing(code_for_inline_val)
        error(source, inlinevalloc, "inline value not supported after /")
    end
    if haveclosingslash && haveblock
        error(source, blockloc, "block not supported after /")
    end
    if haveblock && !isnothing(code_for_inline_val)
        error(source, blockloc, "block not supported after =")
    end
    extendblock!(code, Expr(
        :hamltag,
        tagname,
        stanza_line_number_node,
        attrs,
        haveclosingslash,
        contents,
    ))
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
              (?<elseifblock>-\h*elseif\b\h*)
              |
              (?=(?<sigil>%|\#|\.|-\#|-|=|\\|/|!!!))? # stanza type
              (?:-\#|-|=|\\|/|!!!)?                   # consume these stanza types
            )
        """xm
            if isnothing(firstindent)
                firstindent = indent
            elseif !isnothing(elseblock)
                block = @nolinenodes quote end
                parseresult = parse_indented_block!(block, indent, source)
                push!(controlflow_prev.args, block)
                if !isnothing(parseresult)
                    _, newline = parseresult
                end
                continue
            elseif !isnothing(elseifblock)
                condition, _, _ = parse_expressionline(source)
                block = @nolinenodes quote end
                parseresult = parse_indented_block!(block, indent, source)
                if !isnothing(parseresult)
                    _, newline = parseresult
                end
                controlflow_this = Expr(:elseif, condition, block)
                push!(controlflow_prev.args, controlflow_this)
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
                    extendblock!(code, loc)
                    extendblock!(code, @nolinenodes quote
                        let first=true
                            $expr
                        end
                    end)
                    controlflow_this = expr
                elseif head == :if
                    expr.args[1] = esc(expr.args[1])
                    extendblock!(code, loc)
                    parseresult = parse_indented_block!(expr.args[2], indent, source)
                    extendblock!(code, expr)
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
                    extendblock!(code, loc)
                    extendblock!(code, @nolinenodes quote
                        let first=true
                            $expr
                        end
                    end)
                elseif head == :block
                    extendblock!(code, loc)
                    parseresult = parse_indented_block!(expr, indent, source)
                    extendblock!(code, expr)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                elseif head == :let
                    expr = escapelet(expr)
                    extendblock!(code, loc)
                    parseresult = parse_indented_block!(expr.args[2], indent, source)
                    extendblock!(code, expr)
                    if !isnothing(parseresult)
                        _, newline = parseresult
                    end
                elseif head == :function
                    extendblock!(code, loc)
                    body_of_fun = @nolinenodes quote
                    end
                    parse_indented_block!(body_of_fun, indent, source)
                    name_of_fun = esc(expr.args[1].args[1])

                    argspec = expr.args[1].args[2:end]
                    if !isempty(argspec) && isexpr(:parameters, argspec[1])
                        kw = esc(argspec[1])
                        a = esc.(argspec[2:end])
                        extendblock!(code, @nolinenodes quote
                            $name_of_fun($kw, $(a...)) = begin
                                LiteralHTML(io -> interpolate($kw, io, $name_of_fun, $(a...)))
                            end
                            interpolate($kw, io::IO, ::typeof($name_of_fun), $(a...)) = $body_of_fun
                        end)
                    else
                        a = esc.(argspec)
                        extendblock!(code, @nolinenodes quote
                            $name_of_fun($(a...)) = begin
                                LiteralHTML(io -> interpolate(io, $name_of_fun, $(a...)))
                            end
                            interpolate(io::IO, ::typeof($name_of_fun), $(a...)) = $body_of_fun
                        end)
                    end
                    newline = ""
                elseif head == :macro
                    extendblock!(code, loc)
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
                    extendblock!(code, expr)
                    newline = ""
                elseif isnothing(head)
                    extendblock!(code, loc)
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
                    @output $(esc(expr))
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
                        @output $(LiteralHTML("<!-- "))
                        $linecode
                        @output $(LiteralHTML(" -->"))
                    end)
                else
                    body = @nolinenodes quote end
                    parseresult = parse_indented_block!(body, indent, source)
                    if !isnothing(parseresult)
                        indentation, newline = parseresult
                        body = filterlinenodes(:( @indented $indentation (@nextline; $body) ))
                        extendblock!(code, @nolinenodes quote
                            @output $(LiteralHTML("<!--"))
                            $body
                            @nextline $(LiteralHTML("-->"))
                        end)
                    end
                end
            elseif sigil == "!!!"
                @mustcapture source "Only support '!!! 5'" r"\h*5\h*$(?<newline>\v?)"m
                extendblock!(code, @nolinenodes quote
                    @output $(LiteralHTML("<!DOCTYPE html>"))
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
