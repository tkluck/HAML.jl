module Helpers

import ..Codegen: @io

function surround(f, io, before, after=before)
    write(io, before)
    f()
    write(io, after)
end

precede(f, io, before) = surround(f, io, before, "")
succeed(f, io, after) = surround(f, io, "", after)

macro surround(before, after=before)
    return :( surround(@io, $(esc(before)), $(esc(after))) )
end

macro precede(before)
    return :( precede(@io, $(esc(before))) )
end

macro succeed(after)
    return :( succeed(@io, $(esc(after))) )
end

end
