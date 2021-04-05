@doc read(open(joinpath(@__DIR__, "..", "README.md")), String)
module HAML

import Requires: @require

include("Hygiene.jl")
include("Escaping.jl")
include("SourceTools.jl")
include("Attributes.jl")
include("Parse.jl")
include("Helpers.jl")
include("Codegen.jl")
include("Templates.jl")

function __init__()
    @require Genie="c43c736e-a2d1-11e8-161f-af95117fbd1e" include("Genie.jl")
    @require Revise="295af30f-e4ad-537b-8983-00126c2a3abe" include("Revise.jl")
end

import .Codegen: generate_haml_writer_codeblock, @haml_str
import .Escaping: LiteralHTML
import .SourceTools: Source
import .Templates: render, @include, includehaml
import .Helpers: @surround, @precede, @succeed, @sourcefile, @cdatafile
import .Helpers: @output, @nestedindent

export @haml_str, render, @output, @include, includehaml
export @surround, @precede, @succeed, @sourcefile, @cdatafile, @nestedindent
export LiteralHTML

end # module
