module Parse

mutable struct Source
    text       :: String
    __source__ :: LineNumberNode
    ix         :: Int
end

Source(text::String, __source__::LineNumberNode=LineNumberNode(-1)) = Source(text, __source__, 1)

function linecol(s::Source, ix::Int=s.ix)
    line, col = 1, 1
    i = firstindex(s.text)
    while i < ix
        if s.text[i] == '\n'
            line += 1
            col = 1
        else
            col += 1
        end
        i = nextind(s.text, i)
    end
    return line, col, LineNumberNode(line + s.__source__.line - 1, s.__source__.file)
end

Base.LineNumberNode(s::Source, ix::Int=s.ix) = linecol(s, ix)[3]

Base.getindex(s::Source, ix::Int) = s.text[s.ix + ix - 1]
Base.getindex(s::Source, ix::AbstractRange) = SubString(s.text, s.ix .+ ix .- 1)

Base.isempty(s::Source) = s.ix > length(s.text)

Base.match(needle::Regex, haystack::Source, args...; kwds...) = match(needle, SubString(haystack.text, haystack.ix), args...; kwds...)

function _replace_dummy_linenodes(expr, origin::LineNumberNode)
    if expr isa Expr && expr.head == :macrocall && expr.args[2].file == :none
        delta = expr.args[2].line - 1
        line = LineNumberNode(origin.line + delta, origin.file)
        return Expr(:macrocall, expr.args[1], line, expr.args[3:end]...)
    elseif expr isa Expr
        args = map(a -> _replace_dummy_linenodes(a, origin), expr.args)
        return Expr(expr.head, args...)
    else
        return expr
    end
end

function Base.Meta.parse(s::Source; kwds...)
    expr, offset = Base.Meta.parse(s.text, s.ix; kwds...)
    expr = _replace_dummy_linenodes(expr, LineNumberNode(s))
    advance!(s, offset - s.ix)
    expr
end

function Base.Meta.parse(s::Source, snippet::AbstractString, snippet_location::SubString = snippet; raise=true, with_linenode=true, kwds...)
    @assert snippet_location.string == s.text
    ix = snippet_location.offset + 1
    expr = Base.Meta.parse(snippet; raise=false, kwds...)
    loc = LineNumberNode(s, ix)
    expr = _replace_dummy_linenodes(expr, loc)
    if raise && expr isa Expr && expr.head == :error
        error(s, ix, expr.args[1])
    end
    return with_linenode ? Expr(:block, loc, expr) : expr
end

Base.error(s::Source, msg) = error(s, s.ix, msg)

function Base.error(s::Source, ix::Int, msg)
    line, col, linenode = linecol(s, ix)
    lines = split(s.text, "\n")
    source_snippet = join(lines[max(1, line-1) : line], "\n")
    point_at_column = " " ^ (col - 1) * "^^^ here"
    message = """
    $msg at $(linenode.file):$(linenode.line):
    $source_snippet
    $point_at_column
    """
    error(message)
end

function advance!(s::Source, delta)
    s.ix += delta
end

function capture(haystack, needle)
    # eval into Main to avoid Revise.jl compaining about eval'ing "into
    # the closed module HAML.Parse".
    r = Base.eval(Main, needle)
    hay = esc(haystack)
    captures = Base.PCRE.capture_names(r.regex)
    if !isempty(captures)
        maxix = maximum(keys(captures))
        symbols = map(1:maxix) do ix
            capturename = get(captures, ix, "_")
            esc(Symbol(capturename))
        end
        assign = :( ($(symbols...),) = m.captures )
    else
        assign = :( )
    end
    return quote
        m = match($r, $hay.text, $hay.ix, Base.PCRE.ANCHORED)
        if isnothing(m)
            false
        else
            $assign
            advance!($hay, length(m.match))
            true
        end
    end
end

macro capture(haystack, needle)
    return capture(haystack, needle)
end

macro mustcapture(haystack, msg, needle)
    return quote
        succeeded = $(capture(haystack, needle))
        succeeded || error($(esc(haystack)), $msg)
    end
end

function parse_contentline(s::Source)
    exprs = []
    newline = ""
    while !isempty(s)
        @mustcapture s "Expecting literal content or interpolation" r"""
            (?<literal>[^\\\$\v]*)
            (?<nextchar>[\\\$\v]?)
        """mx
        if nextchar == "\\"
            @mustcapture s "Expecting escaped character" r"(?<escaped_char>.)"
            if escaped_char == "\\" || escaped_char == "\$"
                literal *= escaped_char
            else
                literal *= nextchar * escaped_char
            end
        end
        !isempty(literal) && push!(exprs, literal)
        if nextchar == "\$"
            expr = esc(Base.Meta.parse(s, greedy=false))
            expr = :( htmlesc($expr) )
            push!(exprs, expr)
        end
        if nextchar != "\\" && nextchar != "\$"
            newline = nextchar
            break
        end
    end
    expr = isempty(exprs) ? nothing : Expr(:hamloutput, exprs...)
    return expr, newline
end

function parse_line(::Type{Expr}, s::Source)
end


end # module
