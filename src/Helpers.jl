module Helpers

function surround(f, before, after=before)
    before()
    f()
    after()
end

precede(f, before) = surround(f, before, () -> nothing)
succeed(f, after) = surround(f, () -> nothing, after)

macro surround(before, after=before)
    return :( surround(() -> @output($(esc(before))), () -> @output($(esc(after)))) )
end

macro precede(before)
    return :( precede(() -> @output($(esc(before)))) )
end

macro succeed(after)
    return :( succeed(() -> @output($(esc(after)))) )
end

end
