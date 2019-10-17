@doc read(open(joinpath(@__DIR__, "..", "README.md")), String)
module HAML

include("Hygiene.jl")
include("Parse.jl")
include("Attributes.jl")
include("Codegen.jl")
include("Templates.jl")
include("Helpers.jl")

import .Codegen: generate_haml_writer_codeblock, @haml_str, @io, @output
import .Templates: render, @include
import .Helpers: @surround, @precede, @succeed

export @haml_str, render, @output, @io, @include
export @surround, @precede, @succeed

end # module
