module Templates

import HAML
import HAML: hamlfilter

import ..Parse: Source
import ..Codegen: generate_haml_writer_codeblock, process_usercode

struct FileRevision{INode, MTime} end

openat(dirname, filename) = open(joinpath(dirname, filename))

const open_files = Dict()

function Base.open(fr::FileRevision)
    io, _ = get!(() -> error("Compiling render function when fd has been closed already!"), open_files, fr)
    seek(io, 0)
    return io
end

function Base.Symbol(fr::FileRevision)
    _, name = get!(() -> error("Compiling render function when fd has been closed already!"), open_files, fr)
    return name
end

module Generated end

function render end

function hamlfilter(::Val{:include}, io::IO, dir, indent, filename; variables...)
    relpath, base_name = dirname(filename), basename(filename)
    if !isempty(relpath)
        dir = joinpath(dir, relpath)
    end
    render(io, base_name, dir; indent=indent, variables=variables.data)
end

module_template(dir) = quote
    import HAML: @io

    @generated function writehaml(io::IO, ::FR, ::Val{indent}; variables...) where FR <: $FileRevision where indent
        source = read(open(FR()), String)
        sourceref = LineNumberNode(1, Symbol(FR()))
        useresc(code) = $process_usercode(@__MODULE__, code, esc(:io), identity)
        code = $generate_haml_writer_codeblock($Source(source, sourceref), outerindent=string(indent), io=esc(:io), esc=useresc, interp=sym -> :( $(esc(:variables)).data.$sym ), dir=$dir)
        return macroexpand($(HAML.Codegen), :( @hygiene($code) ), recursive=false)
    end
end

function getmodule(dirname)
    name = Symbol(dirname)
    try
        return getproperty(Generated, name)
    catch
        Base.eval(Generated, :( module $name $(module_template(dirname)) end ))
        return getproperty(Generated, name)
    end
end

function FileRevision(file)
    st = stat(file)
    if !iszero(st.inode)
        return FileRevision{st.inode, st.mtime}()
    else
        error("Cannot read file information")
    end
end

function render(io::IO, filename::AbstractString, dirname::AbstractString; indent=Val(Symbol("")), variables=())
    file = openat(dirname, filename)
    fr = FileRevision(file)
    open_files[fr] = file, Symbol(joinpath(dirname, filename))
    try
        fn = getproperty(getmodule(dirname), :writehaml)
        return Base.invokelatest(fn, io, fr, indent; variables...)
    finally
        delete!(open_files, fr)
        close(file)
    end
end

function render(io::IO, path::AbstractString; kwds...)
    dir_name, base_name = dirname(path), basename(path)

    return render(io, basename(path), dirname(path); kwds...)
end

end # module
