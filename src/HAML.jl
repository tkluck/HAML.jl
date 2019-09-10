module HAML

import Base.Meta: parse

import DataStructures: OrderedDict

const stanza_regex = r"""
    ^                                          # line beginning
    (?<indent>\s*)                             # indentation
    (?<sigil>%|\#|\.|-|=|\\)?                  # stanza type
    (?<rest>
        \s*(?<block>for|if|while)?             # block introduction
        (?:.*)                                 # rest of line
    )
    $\n                                        # line end
"""xm
const offset_indent, offset_sigil, offset_rest = 1, 2, 3

const tag_regex = r"""
    %                         # literal percent
    (?<tagname>[A-Za-z0-9]+)? # tag name
"""x
const tag_attrs_regex = r"""
    (?<openbracket>\()
    |
    (?:
        (?<sigil>\.|\#)
        (?<value>[A-Za-z0-9]+)
    )
"""x
const rest_regex = r"""
    (?<closingslash>/)?
    [ \t]*
    (?<rest>.+)?
    $
"""mx

function mustmatch(r, s, ix)
    m = match(r, s, ix)
    m == nothing && error("Syntax error: should match $r at '$(s[ix:min(end,ix+10)])'...")
    m
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
            else
                ix = findlast(!ignore, values)
                write(io, values[ix])
            end
            write(io, "'")
        end
    end
end

function parse_tag_stanza!(code, curindent, source, sourceix)
    if (n = match(tag_regex, source, sourceix[])) |> !isnothing
        sourceix[] += length(n.match)
        tagname = something(n[:tagname], "div")
    else
        tagname = "div"
    end
    push!(code.args, :( attributes = OrderedDict() ) )
    while (n = match(tag_attrs_regex, source, sourceix[])) |> !isnothing
        if !isnothing(n[:openbracket])
            attributes_tuple_expr, sourceix[] = parse(source, sourceix[], greedy=false)
            push!(code.args, quote
                attributes_tuple = $(esc(attributes_tuple_expr))
                for (attr, value) in pairs(attributes_tuple)
                    a = get!(Vector, attributes, attr)
                    append!(a, [value;])
                end
            end)
        else
            sourceix[] += length(n.match)
            if n[:sigil] == "."
                push!(code.args, quote
                    a = get!(Vector, attributes, :class)
                    push!(a, $(n[:value]))
                end)
            elseif n[:sigil] == "#"
                push!(code.args, quote
                    a = get!(Vector, attributes, :id)
                    push!(a, $(n[:value]))
                end)
            else
                error("Unknown sigil: $(n[:sigil])")
            end
        end
    end
    n = mustmatch(rest_regex, source, sourceix[])
    sourceix[] += length(n.match)

    open, close = "<$tagname", "</$tagname>"
    body = quote end
    haveblock = parse_indented_block!(body, curindent, source, sourceix)
    if haveblock
        push!(code.args, quote
            write(io, $curindent, $open)
            joinattributes(io, attributes)
            write(io, ">\n")
            # TODO: write n[:rest]
            $body
            write(io, $curindent, $close, "\n")
        end)
    elseif !isnothing(n[:closingslash])
        push!(code.args, quote
            write(io, $curindent, $open)
            joinattributes(io, attributes)
            write(io, " />\n")
        end)
    elseif !isnothing(n[:rest])
        push!(code.args, quote
            write(io, $curindent, $open)
            joinattributes(io, attributes)
            write(io, ">", $(n[:rest]), $close, "\n")
        end)
    else
        push!(code.args, quote
            write(io, $curindent, $open)
            joinattributes(io, attributes)
            write(io, ">", $close, "\n")
        end)
    end
end


function parse_indented_block!(code, curindent, source, sourceix=Ref(1))
    parsed_something = false
    while sourceix[] <= length(source)
        if sourceix[] == length(source) && source[sourceix[]] == '\n'
            push!(code.args, :( write(io, "\n") ))
            sourceix[] += 1
            return parsed_something
        end

        m = mustmatch(stanza_regex, source, sourceix[])
        indentlength(m[:indent]) <= indentlength(curindent) && return parsed_something

        parsed_something = true

        if m[:sigil] in ("%", "#", ".")
            sourceix[] = m.offsets[offset_sigil]
            parse_tag_stanza!(code, m[:indent], source, sourceix)
        elseif m[:sigil] == "-" && isnothing(m[:block])
            expr = parse(m[:rest])
            push!(code.args, esc(expr))
            sourceix[] += length(m.match)
        elseif m[:sigil] == "-" && !isnothing(m[:block])
            block = parse(m[:rest] * "\nend")
            block.args[1] = esc(block.args[1])
            push!(code.args, block)
            sourceix[] += length(m.match)
            parse_indented_block!(block.args[2], m[:indent], source, sourceix)
        elseif m[:sigil] == "="
            expr, sourceix[] = parse(source, m.offsets[offset_sigil] + 1, greedy=false)
            push!(code.args, quote
                write(io, $(m[:indent]), $(esc(expr)), "\n")
            end)
        elseif m[:sigil] == "\\"
            push!(code.args, quote
                write(io, $(m[:indent]), $(m[:rest]), "\n")
            end)
            sourceix[] += length(m.match) + 1
        elseif m[:sigil] == nothing
            push!(code.args, quote
                write(io, $(m[:indent]), $(m[:rest]), "\n")
            end)
            sourceix[] += length(m.match) + 1
        else
            error("Unrecognized sigil: $(m[:sigil])")
        end
    end
    return parsed_something
end

function generate_haml_writer_codeblock(source)
    code = quote end
    parse_indented_block!(code, nothing, source)
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
