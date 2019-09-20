module Parse

mutable struct Source
    text :: String
    ix   :: Int
    line :: Int
    col  :: Int
end

Source(text::String) = Source(text, 1, 1, 1)

Base.getindex(s::Source, ix::Int) = s.text[s.ix + ix - 1]
Base.getindex(s::Source, ix::AbstractRange) = SubString(s.text, s.ix .+ ix .- 1)

Base.isempty(s::Source) = s.ix > length(s.text)

Base.match(needle::Regex, haystack::Source, args...; kwds...) = match(needle, SubString(haystack.text, haystack.ix), args...; kwds...)

function Base.Meta.parse(s::Source, args...; kwds...)
    expr, offset = Base.Meta.parse(SubString(s.text, s.ix), 1, args...; kwds...)
    advance!(s, offset - 1)
    expr
end

function Base.error(s::Source, msg)
    lines = split(s.text, "\n")
    source_snippet = join(lines[max(1, s.line-1) : s.line], "\n")
    point_at_column = " " ^ (s.col - 1) * "^^^ here"
    message = """
    $msg at line $(s.line) column $(s.col):
    $source_snippet
    $point_at_column
    """
    error(message)
end

function advance!(s::Source, delta)
    for _ in 1:delta
        if s[1] == '\n'
            s.line += 1
            s.col = 1
        else
            s.col += 1
        end
        s.ix += 1
    end
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
        return quote
            m = match($r, $hay.text, $hay.ix, Base.PCRE.ANCHORED)
            if isnothing(m)
                false
            else
                ($(symbols...),) = m.captures
                advance!($hay, length(m.match))
                true
            end
        end
    else
        return :( !isnothing(match($r, $hay.text, $hay.ix, Base.PCRE.ANCHORED)) )
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

end # module
