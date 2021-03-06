module Helpers

import ..Escaping: LiteralHTML

macro indentation()
    Expr(:hamlindentation)
end


macro indented(indentation, expr)
    Expr(:hamlindented, esc(indentation), esc(expr))
end

macro output(expr...)
    expr = map(esc, expr)
    Expr(:hamloutput, expr...)
end

macro indent()
    Expr(:hamloutput, Expr(:hamlindentation))
end

macro nextline(expr...)
    expr = map(esc, expr)
    Expr(:hamloutput, "\n", Expr(:hamlindentation), expr...)
end

function surround(f, before, after=before)
    before()
    f()
    after()
end

precede(f, before) = surround(f, before, () -> nothing)
succeed(f, after) = surround(f, () -> nothing, after)

"""
    - @surround(before, after) do
      <haml block>

Surround the output of `<haml block>` with `before` and `after` with
no space in between.
"""
macro surround(before, after=before)
    return :( surround(() -> $(Expr(:hamloutput, esc(before))), () -> $(Expr(:hamloutput, esc(after)))) )
end

"""
    - @precede(before) do
      <haml block>

Precede the output of `<haml block>` with `before` with no space in between.
"""
macro precede(before)
    return :( precede(() -> $(Expr(:hamloutput, esc(before)))) )
end

"""
    - @succeed(after) do
      <haml block>

Follow the output of `<haml block>` with `after` with no space in between.
"""
macro succeed(after)
    return :( succeed(() -> $(Expr(:hamloutput, esc(after)))) )
end

"""
    - @sourcefile(relpath)

Include the contents of the file at `relpath` (relative to the current
file's directory) literally into the output.
"""
macro sourcefile(relpath)
    at_dir = Base.var"@__DIR__"
    dir = macroexpand(__module__, Expr(:macrocall, at_dir, __source__))

    path = realpath(joinpath(dir, relpath))

    code = quote end
    first = true
    for line in eachline(path)
        if first
            push!(code.args, Expr(:hamloutput, LiteralHTML(line)))
        else
            push!(code.args, Expr(:hamloutput, "\n", Expr(:hamlindentation), LiteralHTML(line)))
        end
        first = false
    end

    code
end

"""
    - @cdatafile(relpath)

Include the contents of the file at `relpath` (relative to the current
file's directory) as a CDATA section in the output. Any occurrences
of `]]>` are suitably escaped.
"""
macro cdatafile(relpath)
    at_dir = Base.var"@__DIR__"
    dir = macroexpand(__module__, Expr(:macrocall, at_dir, __source__))

    path = realpath(joinpath(dir, relpath))

    code = quote
        $(Expr(:hamloutput, LiteralHTML("<![CDATA[")))
    end
    for line in eachline(path)
        line = replace(line, "]]>" => "]]]]><![CDATA[>")
        push!(code.args, Expr(:hamloutput, "\n", Expr(:hamlindentation), LiteralHTML(line)))
    end
    push!(code.args, Expr(:hamloutput, "\n", Expr(:hamlindentation), LiteralHTML("]]>")))

    code
end

function nestedindent(html::LiteralHTML, indent)
    LiteralHTML() do io
        text = html.html
        ix = 1
        while true
            m = match(r"\v+"m, text, ix)
            if isnothing(m)
                write(io, SubString(text, ix))
                break
            end
            write(io, SubString(text, ix, m.offset-1), m.match, indent)
            ix = m.offset + length(m.match)
        end
    end
end

"""
    = @nestedindent value

Output value into the rendered HAML string, with every new line indented
at the current indentation level.
"""
macro nestedindent(expr)
    return :($nestedindent($(esc(expr)), @indentation))
end

end
