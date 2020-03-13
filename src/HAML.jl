@doc read(open(joinpath(@__DIR__, "..", "README.md")), String)
module HAML

import Requires: @require

include("Hygiene.jl")
include("Parse.jl")
include("Attributes.jl")
include("Codegen.jl")
include("Templates.jl")
include("Helpers.jl")

function __init__()
    @require Genie="c43c736e-a2d1-11e8-161f-af95117fbd1e" include("Genie.jl")
end

import .Codegen: generate_haml_writer_codeblock, @haml_str, @io, @output
import .Parse: Source
import .Templates: render, @include, includehaml
import .Helpers: @surround, @precede, @succeed

export @haml_str, render, @output, @io, @include, includehaml
export @surround, @precede, @succeed

end # module
