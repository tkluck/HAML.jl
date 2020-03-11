module Templates

import HAML

import ..Hygiene: make_hygienic, invert_escaping, replace_expression_nodes_unescaped
import ..Parse: Source
import ..Codegen: generate_haml_writer_codeblock, replace_output_nodes, @output, @io

macro include(relpath, args...)
    relpath = esc(relpath)
    args = map(esc, args)

    at_dir = getproperty(Base, Symbol("@__DIR__"))
    dir = macroexpand(__module__, Expr(:macrocall, at_dir, __source__))

    :( render(joinpath($dir, $relpath); variables=($(args...),)) do (content...)
        $(Expr(:hamloutput, :(content...)))
    end )
end

"""
    includehaml(mod::Module, fn::Symbol, path, indent="")

Define two methods for the function `mod.fn` that allow rendering the HAML
template in  the file `path`. These methods have the following signatures:

    fn(io::IO; variables...)
    fn(f::Function; variables...)

where the output of the template will be written to `io` / passed to `f`
respectively.
"""
includehaml(mod::Module, fn::Symbol, path, indent="") = _includehaml(mod, fn, path, indent)


function _includehaml(mod::Module, fn::Symbol, path, indent="")
    s = Source(path)
    code = generate_haml_writer_codeblock(mod, s, string(indent))
    code = replace_expression_nodes_unescaped(:hamloutput, code) do content...
        :( f($(content...)) )
    end
    code = replace_expression_nodes_unescaped(:$, code) do sym
        sym isa Symbol || error("Can only use variables as interpolations")
        :( variables.data.$sym )
    end
    fn = esc(fn)
    code = quote
        $fn(f::Function; variables...) = $code
        $fn(io::IO; variables...) = $fn(; variables...) do (content...)
            write(io, content...)
        end
        $fn(; variables...) = let io = IOBuffer()
            $fn(; variables...) do (content...)
                write(io, content...)
            end
            String(take!(io))
        end
    end
    code = make_hygienic(mod, code)
    Base.eval(mod, code)
end

module Generated
    import ...Templates: @output, @io, @include
end

function render(io, path; variables=(), indent="")
    fn = gensym()
    includehaml(Generated, fn, path, indent)
    Base.invokelatest(getproperty(Generated, fn), io; variables...)
end

end # module
