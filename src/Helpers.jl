module Helpers

function surround(f, before, after=before)
    before()
    f()
    after()
end

precede(f, before) = surround(f, before, () -> nothing)
succeed(f, after) = surround(f, () -> nothing, after)

macro surround(before, after=before)
    return :( surround(() -> $(Expr(:hamloutput, esc(before))), () -> $(Expr(:hamloutput, esc(after)))) )
end

macro precede(before)
    return :( precede(() -> $(Expr(:hamloutput, esc(before)))) )
end

macro succeed(after)
    return :( succeed(() -> $(Expr(:hamloutput, esc(after)))) )
end

macro sourcefile(relpath)
    at_dir = getproperty(Base, Symbol("@__DIR__"))
    dir = macroexpand(__module__, Expr(:macrocall, at_dir, __source__))

    path = realpath(joinpath(dir, relpath))

    code = quote end
    first = true
    for line in eachline(path)
        if first
            push!(code.args, Expr(:hamloutput, line))
        else
            push!(code.args, Expr(:hamloutput, "\n", Expr(:hamlindentation), line))
        end
        first = false
    end

    code
end

macro cdatafile(relpath)
    at_dir = getproperty(Base, Symbol("@__DIR__"))
    dir = macroexpand(__module__, Expr(:macrocall, at_dir, __source__))

    path = realpath(joinpath(dir, relpath))

    code = quote
        $(Expr(:hamloutput, "<![CDATA["))
    end
    for line in eachline(path)
        line = replace(line, "]]>" => "]]]]><![CDATA[>")
        push!(code.args, Expr(:hamloutput, "\n", Expr(:hamlindentation), line))
    end
    push!(code.args, Expr(:hamloutput, "\n", Expr(:hamlindentation), "]]>"))

    code
end

end
