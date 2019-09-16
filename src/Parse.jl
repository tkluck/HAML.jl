module Parse

advance!(s, delta) = s[] = SubString(s[], delta + 1)

macro capture(haystack, needle)
    # eval into Main to avoid Revise.jl compaining about eval'ing "into
    # the closed module HAML.Parse".
    r = Base.eval(Main, needle)
    captures = Base.PCRE.capture_names(r.regex)
    if !isempty(captures)
        maxix = maximum(keys(captures))
        symbols = map(1:maxix) do ix
            capturename = get(captures, ix, "_")
            esc(Symbol(capturename))
        end
        return quote
            m = match($r, $(esc(haystack))[], 1, Base.PCRE.ANCHORED)
            if isnothing(m)
                false
            else
                ($(symbols...),) = m.captures
                advance!($(esc(haystack)), length(m.match))
                true
            end
        end
    else
        return :( !isnothing(match($r, $(esc(haystack))[], 1, Base.PCRE.ANCHORED)) )
    end
end

end # module
