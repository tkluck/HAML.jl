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

import ..Attributes: AttributeVals, mergeattributes, writeattributes
import ..Hygiene: mapexpr, escapelet, isexpr
import ..SourceTools: @capture, @mustcapture, Source, parse_juliacode, parse_contentline, parse_expressionline

function filterlinenodes(expr)
    if expr isa Expr && expr.head == :block
        args = filter(e -> !(e isa LineNumberNode), expr.args)
        args = map(a -> mapexpr(filterlinenodes, a), args)
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
    @mustcapture source "Expecting a tag name" r"(?:%(?<tagname>[A-Za-z0-9]+)?)?"
    tagname = something(tagname, "div")

    attrs = AttributeVals()
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
            for a in attr_expr.args
                if isexpr(:(=), a)
                    attrs = mergeattributes(attrs, a.args[1] => a.args[2])
                elseif isexpr(:(...), a)
                    attrs = mergeattributes(attrs, :( (;$a) ))
                elseif isexpr(:call, a) && a.args[1] == :(=>)
                    attrs = mergeattributes(attrs, :( (;$a) ))
                else
                    error(source, loc, "Expecting key=value expression")
                end
            end
        else
            if sigil == "."
                attrs = mergeattributes(attrs, :class => value)
            elseif sigil == "#"
                attrs = mergeattributes(attrs, :id    => value)
            else
                error(source, "(unreachable) Unknown sigil: $sigil")
            end
        end
    end

    attrs = writeattributes(attrs)

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
            print(ElementContentContext(@io), $(esc(expr)))
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
            $attrs
            @output $" />"
        end)
    elseif haveblock
        isnothing(code_for_inline_val) || error(source, blockloc, "block not supported after =")
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attrs
            @output ">"
            $body
            @output $"</$tagname>"
        end)
    elseif !isnothing(code_for_inline_val)
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attrs
            @output ">"
            $code_for_inline_val
            @output $"</$tagname>"
        end)
    else
        extendblock!(code, @nolinenodes quote
            @output $"<$tagname"
            $attrs
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

function HELPER end

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
              (?<elseifblock>-\h*elseif\h*)
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
                    argspec = esc.(expr.args[1].args[2:end])
                    argnames = map(expr.args[1].args[2:end]) do arg
                        isexpr(:(::), arg) && return esc(arg.args[1])
                        arg isa Symbol && return esc(arg)
                        error("Can't understand argument: $arg")
                    end
                    extendblock!(code, @nolinenodes quote
                        # TODO: support kwargs
                        $name_of_fun($(argspec...)) = begin
                            LiteralHTML(io -> HELPER(io, $name_of_fun, $(argnames...)))
                        end
                        HELPER(io::IO, ::typeof($name_of_fun), $(argspec...)) = $body_of_fun
                    end)
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
                    print(ElementContentContext(@io), $(esc(expr)))
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
