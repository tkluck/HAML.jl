module HAML

import Base.Meta: parse

import DataStructures: OrderedDict
import Markdown: htmlesc

advance!(s, delta) = s[] = SubString(s[], delta + 1)

macro capture(haystack, needle)
    r = r"\A" * eval(needle)
    captures = Base.PCRE.capture_names(r.regex)
    if !isempty(captures)
        maxix = maximum(keys(captures))
        symbols = map(1:maxix) do ix
            capturename = get(captures, ix, "_")
            esc(Symbol(capturename))
        end
        return quote
            m = match($r, $(esc(haystack))[])
            if isnothing(m)
                false
            else
                ($(symbols...),) = m.captures
                advance!($(esc(haystack)), length(m.match))
                true
            end
        end
    else
        return :( !isnothing(match($r, $(esc(haystack))[])) )
    end
end

indentlength(s) = mapreduce(c -> c == '\t' ? 8 : 1, +, s, init=0)
indentlength(::Nothing) = -1

function joinattributes(io, attributes)
    # TODO: escaping!
    ignore(x) = isnothing(x) || x === false
    for (name, values) in pairs(attributes)
        if any(!ignore, values)
            write(io, " ", name, "='")
            if name == :class
                join(io, filter(!ignore, values), " ")
            elseif name == :id
                join(io, filter(!ignore, values), "_")
            elseif length(values) == 1 && values[1] === true
                # selected='selected'
                write(io, name)
            else
                ix = findlast(!ignore, values)
                htmlesc(io, string(values[ix]))
            end
            write(io, "'")
        end
    end
end

function parse_tag_stanza!(code, curindent, source)
    @assert @capture source r"(?:%(?<tagname>[A-Z-a-z0-9]+)?)?"
    tagname = something(tagname, "div")

    let_block = :( let attributes = OrderedDict(); end )
    push!(code.args, let_block)
    block = let_block.args[2].args
    while @capture source r"""
        (?=(?<openbracket>\())
        |
        (?:
            (?<sigil>\.|\#)
            (?<value>[A-Za-z0-9]+)
        )
    """x
        if !isnothing(openbracket)
            attributes_tuple_expr, offset = parse(source[], 1, greedy=false)
            if attributes_tuple_expr.head == :(=)
                attributes_tuple_expr = :( ($attributes_tuple_expr,) )
            end
            advance!(source, offset - 1)
            push!(block, quote
                let attributes_tuple = $(esc(attributes_tuple_expr))
                    for (attr, value) in pairs(attributes_tuple)
                        a = get!(Vector, attributes, attr)
                        append!(a, [value;])
                    end
                end
            end)
        else
            if sigil == "."
                push!(block, quote
                    a = get!(Vector, attributes, :class)
                    push!(a, $value)
                end)
            elseif sigil == "#"
                push!(block, quote
                    a = get!(Vector, attributes, :id)
                    push!(a, $value)
                end)
            else
                error("Unknown sigil: $sigil")
            end
        end
    end

    @assert @capture source r"""
        (?<equalssign>\=)
        |
        (?<closingslash>/)?
        \h*
        (?<rest_of_line>.+)?
        $
        (?<nl>\v*)
    """mx

    code_for_inline_val = nothing
    if !isnothing(equalssign)
        expr, offset = parse(source[], 1, greedy=false)
        advance!(source, offset - 1)
        @assert @capture source r"\h*$(?<nl>\v*)"m
        code_for_inline_val = :( let val = $(esc(expr))
            htmlesc(io, string(val))
        end )
    elseif !isnothing(rest_of_line)
        code_for_inline_val = quote
            write(io, $rest_of_line)
        end
    end

    body = quote end
    haveblock = parse_indented_block!(body, curindent, source)
    if !isnothing(closingslash)
        @assert isnothing(code_for_inline_val)
        push!(block, quote
            write(io, $"$curindent<$tagname")
            joinattributes(io, attributes)
            write(io, $" />$nl")
        end)
    elseif haveblock
        @assert isnothing(code_for_inline_val)
        push!(block, quote
            write(io, $"$curindent<$tagname")
            joinattributes(io, attributes)
            write(io, ">\n")
            $body
            write(io, $"$curindent</$tagname>$nl")
        end)
    else
        push!(block, quote
            write(io, $"$curindent<$tagname")
            joinattributes(io, attributes)
            write(io, ">")
            $code_for_inline_val
            write(io, $"</$tagname>$nl")
        end)
    end
end


function parse_indented_block!(code, curindent, source)
    parsed_something = false

    controlflow_this = nothing
    controlflow_prev = nothing
    while !isempty(source[])
        controlflow_this, controlflow_prev = nothing, controlflow_this
        if indentlength(match(r"\A\h*", source[]).match) <= indentlength(curindent)
             return parsed_something
         end
        if @capture source r"""
            ^
            (?<indent>\h*)                # indentation
            (?=(?<sigil>%|\#|\.|-|=|\\))? # stanza type
            (?:-|=|\\)?                   # consume these stanza types
        """xm
            parsed_something = true

            if sigil in ("%", "#", ".")
                parse_tag_stanza!(code, indent, source)
            elseif sigil == "-"
                @assert @capture source r"\h*(?<rest_of_line>.*)$\v?"m
                if startswith(rest_of_line, r"\h*(?:for|if|while)")
                    block = parse(rest_of_line * "\nend")
                    block.args[1] = esc(block.args[1])
                    push!(code.args, block)
                    parse_indented_block!(block.args[2], indent, source)
                    controlflow_this = block
                elseif !isnothing(match(r"\A\h*else\h*\z", rest_of_line))
                    block = quote end
                    push!(controlflow_prev.args, block)
                    parse_indented_block!(block, indent, source)
                else
                    expr = parse(rest_of_line)
                    push!(code.args, esc(expr))
                end
            elseif sigil == "="
                expr, offset = parse(source[], 1, greedy=false)
                advance!(source, offset - 1)
                @assert @capture source r"\h*$(?<nl>\v*)"m
                push!(code.args, quote
                    write(io, $indent)
                    let val = $(esc(expr))
                        htmlesc(io, string(val))
                    end
                    write(io, $nl)
                end)
            elseif sigil == "\\" || sigil == nothing
                @assert @capture source r"\h*(?<rest_of_line>.*)$(?<nl>\v*)"m
                push!(code.args, quote
                    write(io, $indent, $rest_of_line, $nl)
                end)
            else
                error("Unrecognized sigil: $sigil")
            end
        else
            error("Unrecognized")
        end
    end
    return parsed_something
end

function generate_haml_writer_codeblock(source)
    code = quote end
    parse_indented_block!(code, nothing, Ref(source))
    return code
end

macro hamlwriter_str(source)
    code = generate_haml_writer_codeblock(source)
    return :( function(io)
        $code
    end )
end

macro haml_str(source)
    code = generate_haml_writer_codeblock(source)
    quote
        io = IOBuffer()
        $code
        String(take!(io))
    end
end


export @haml_str, @hamlwriter_str

end # module
