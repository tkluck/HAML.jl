module HAML

import Base.Meta: parse

import DataStructures: OrderedDict
import Markdown: htmlesc

include("Templates.jl")

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

function makeattr(name, val)
    ignore(x) = isnothing(x) || x === false
    val = filter(!ignore, [val;])
    isempty(val) && return (false, nothing, nothing)

    if name == :class
        value = join(val, " ")
    elseif name == :id
        value = join(val, "-")
    else
        ix = findlast(!ignore, val)
        value = val[ix]
    end
    if value === true
        valuerepr = string(name)
    else
        valuerepr = string(value)
    end
    namerepr = replace(string(name), "_" => "-")
    return (true, htmlesc(namerepr), htmlesc(valuerepr))
end

join_attr_name(x...) = Symbol(join(x, "-"))
recurse_attributes(x, path...) = (join_attr_name(path...) => x,)
recurse_attributes(x::Pair, path...) = recurse_attributes(x[2], path..., x[1])
recurse_attributes(x::Union{NamedTuple,AbstractDict}, path...) = (attr for pair in pairs(x) for attr in recurse_attributes(pair, path...))
recurse_attributes(x::AbstractVector, path...) = (attr for pair in x for attr in recurse_attributes(pair, path...))

function writeattributes(io, attributes)
    collected_attributes = OrderedDict()
    for (name, value) in recurse_attributes(attributes)
        a = get!(Vector, collected_attributes, name)
        append!(a, [value;])
    end
    for (name, value) in pairs(collected_attributes)
        (valid, name, value) = makeattr(name, value)
        valid || continue
        write(io, " ", name, "='", value, "'")
    end
end

function parse_tag_stanza!(code, curindent, source; outerindent=outerindent, esc=Base.esc, io=io)
    @assert @capture source r"(?:%(?<tagname>[A-Z-a-z0-9]+)?)?"
    tagname = something(tagname, "div")

    let_block = :( let attributes = []; end )
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
                        push!(attributes, attr => value)
                    end
                end
            end)
        else
            if sigil == "."
                push!(block, quote
                    push!(attributes, :class => $value)
                end)
            elseif sigil == "#"
                push!(block, quote
                    push!(attributes, :id => $value)
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
        @assert @capture source r"""
            \h*
            (?<code_to_parse>
                (?:.*|,\h*\v)*
            )
            $(?<nl>\v?)
        """mx
        expr = parse(code_to_parse)
        code_for_inline_val = :( let val = $(esc(expr))
            htmlesc($io, string(val))
        end )
    elseif !isnothing(rest_of_line)
        code_for_inline_val = quote
            write($io, $rest_of_line)
        end
    end

    body = quote end
    haveblock = parse_indented_block!(body, curindent, source, outerindent=outerindent, esc=esc, io=io)
    if !isnothing(closingslash)
        @assert isnothing(code_for_inline_val)
        push!(block, quote
            write($io, $"$outerindent$curindent<$tagname")
            writeattributes($io, attributes)
            write($io, $" />$nl")
        end)
    elseif haveblock
        @assert isnothing(code_for_inline_val)
        push!(block, quote
            write($io, $"$outerindent$curindent<$tagname")
            writeattributes($io, attributes)
            write($io, ">\n")
            $body
            write($io, $"$outerindent$curindent</$tagname>$nl")
        end)
    else
        push!(block, quote
            write($io, $"$outerindent$curindent<$tagname")
            writeattributes($io, attributes)
            write($io, ">")
            $code_for_inline_val
            write($io, $"</$tagname>$nl")
        end)
    end
end


function parse_indented_block!(code, curindent, source; outerindent="", esc=Base.esc, io=:io)
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
            (?<indent>\h*)                  # indentation
            (?=(?<sigil>%|\#|\.|-|=|\\|:))? # stanza type
            (?:-|=|\\|:)?                   # consume these stanza types
        """xm
            parsed_something = true

            if sigil in ("%", "#", ".")
                parse_tag_stanza!(code, indent, source, outerindent=outerindent, esc=esc, io=io)
            elseif sigil == "-"
                @assert @capture source r"""
                    \h*
                    (?<code_to_parse>
                        (?:.*|,\h*\v)*
                    )$\v?
                """mx
                if startswith(code_to_parse, r"\h*(?:for|if|while)")
                    block = parse(code_to_parse * "\nend")
                    block.args[1] = esc(block.args[1])
                    push!(code.args, block)
                    parse_indented_block!(block.args[2], indent, source, outerindent=outerindent, esc=esc, io=io)
                    controlflow_this = block
                elseif !isnothing(match(r"\A\h*else\h*\z", code_to_parse))
                    block = quote end
                    push!(controlflow_prev.args, block)
                    parse_indented_block!(block, indent, source, outerindent=outerindent, esc=esc, io=io)
                else
                    expr = parse(code_to_parse)
                    push!(code.args, esc(expr))
                end
            elseif sigil == "="
                @assert @capture source r"""
                    \h*
                    (?<code_to_parse>
                        (?:.*|,\h*\v)*
                    )
                    $(?<nl>\v?)
                """mx
                expr = parse(code_to_parse)
                push!(code.args, quote
                    write($io, $indent)
                    let val = $(esc(expr))
                        htmlesc($io, string(val))
                    end
                    write($io, $nl)
                end)
            elseif sigil == "\\" || sigil == nothing
                @assert @capture source r"\h*(?<rest_of_line>.*)$(?<nl>\v*)"m
                push!(code.args, quote
                    write($io, $indent, $rest_of_line, $nl)
                end)
            elseif sigil == ":"
                filter_expr, offset = parse(source[], 1, greedy=true)
                advance!(source, offset - 1)
                if filter_expr isa Expr && filter_expr.head == :call && filter_expr.args[1] == :include
                    push!(code.args, quote
                        $(esc(:hamlfilter))($io, Val(:include), Val(Symbol($(outerindent * indent))), $(filter_expr.args[2:end]...))
                    end)
                else
                    error("Unrecognized filter: $filter_expr")
                end
            else
                error("Unrecognized sigil: $sigil")
            end
        else
            error("Unrecognized")
        end
    end
    return parsed_something
end

function generate_haml_writer_codeblock(source; outerindent="", esc=Base.esc, io=:io)
    code = quote end
    parse_indented_block!(code, nothing, Ref(source), outerindent=outerindent, esc=esc, io=io)
    return code
end

macro _haml(io, outerindent, source)
    generate_haml_writer_codeblock(source, outerindent=outerindent, io=esc(io))
end

macro haml_str(source)
    code = generate_haml_writer_codeblock(source)
    quote
        io = IOBuffer()
        $code
        String(take!(io))
    end
end

import .Templates: render

export @haml_str, @hamlwriter_str, render

end # module
