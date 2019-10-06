@doc read(open(joinpath(@__DIR__, "..", "README.md")), String)
module HAML

function hamlfilter end

include("Hygiene.jl")
include("Parse.jl")
include("Codegen.jl")
include("Templates.jl")
include("Helpers.jl")

import .Codegen: generate_haml_writer_codeblock, @haml_str, @io
import .Templates: render, @include
import .Helpers: @surround, @precede, @succeed

export @haml_str, render, @io, @include
export @surround, @precede, @succeed

end # module
