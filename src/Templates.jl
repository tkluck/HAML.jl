module Templates

import HAML

import ..Hygiene: replace_macro_hygienic, make_hygienic, invert_escaping, replace_interpolations
import ..Parse: Source
import ..Codegen: generate_haml_writer_codeblock, at_io, materialize_indentation

struct FileRevision{Dir, Basename, MTime} end

Base.dirname(::FileRevision{Dir, Basename, MTime}) where {Dir, Basename, MTime}      = string(Dir)
Base.basename(::FileRevision{Dir, Basename, MTime}) where {Dir, Basename, MTime} = string(Basename)

openat(dirname, filename) = open(joinpath(dirname, filename))

const open_files = Dict()

function Base.open(fr::FileRevision)
    openat(dirname(fr), basename(fr))
end

function Base.Symbol(fr::FileRevision)
    return Symbol(joinpath(dirname(fr), basename(fr)))
end

module Generated end

function render end

const module_template = quote
    import HAML: @io, @output, @include
end

function getmodule(filerevision)
    name = Symbol(repr(filerevision))
    try
        return getproperty(Generated, name)
    catch
        Base.eval(Generated, :( module $name; $module_template; end ))
        return getproperty(Generated, name)
    end
end

function FileRevision(dirname, basename)
    st = stat(openat(dirname, basename))
    if !iszero(st.inode)
        return FileRevision{Symbol(dirname), Symbol(basename), st.mtime}()
    else
        error("Cannot read file information")
    end
end

@generated function render(io::IO, ::FR, ::Val{indent}; variables...) where FR <: FileRevision where indent
    usermod = getmodule(FR())
    source = read(open(FR()), String)
    sourceref = LineNumberNode(1, Symbol(FR()))
    code = generate_haml_writer_codeblock(Source(source, sourceref))
    code = replace_macro_hygienic(HAML.Codegen, usermod, code, at_io => :io)
    code = Expr(:hamlindented, string(indent), code)
    code = materialize_indentation(code)
    code = replace_interpolations(code) do sym
        sym isa Symbol || error("Can only use variables as interpolations")
        :( $(esc(:variables)).data.$sym )
    end
    code = invert_escaping(code)
    code = make_hygienic(usermod, code)
    return code
end

function render(io::IO, basename::AbstractString, dirname::AbstractString; indent=Val(Symbol("")), variables=())
    fr = FileRevision(dirname, basename)
    getmodule(fr)
    return render(io, fr, indent; variables...)
end

function render(io::IO, path::AbstractString; kwds...)
    return render(io, basename(path), dirname(path); kwds...)
end

macro include(relpath, args...)
    relpath = esc(relpath)
    args = map(esc, args)

    at_dir = getproperty(Base, Symbol("@__DIR__"))
    dir = macroexpand(__module__, Expr(:macrocall, at_dir, __source__))

    :( render(@io, joinpath($dir, $relpath); variables=($(args...),)) )
end

end # module
