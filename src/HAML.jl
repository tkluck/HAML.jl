@doc read(open(joinpath(@__DIR__, "..", "README.md")), String)
module HAML

function hamlfilter end

include("Parse.jl")
include("Codegen.jl")
include("Templates.jl")

import .Codegen: generate_haml_writer_codeblock, @_haml, @haml_str, @io
import .Templates: render

export @haml_str, render, @io

end # module
