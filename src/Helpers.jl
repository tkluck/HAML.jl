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

end
