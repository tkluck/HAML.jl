module Templates

import HAML
import HAML: hamlfilter

struct FileRevision{INode, MTime} end

function openat_raw(dir::RawFD, filename::AbstractString)
    fdesc = ccall(:openat, RawFD, (RawFD, Cstring, Int32), dir, filename, 0)
    reinterpret(Int32, fdesc) < 0 && error("Couldn't open $filename")
    return fdesc
end

openat(dir, filename) = open(openat_raw(dir, filename))

const open_files = Dict()
const friendlynames = Dict()

function Base.open(fr::FileRevision)
    io = get!(() -> error("Compiling render function when fd has been closed already!"), open_files, fr)
    seek(io, 0)
    return io
end

module Generated end

function render end

function hamlfilter(::Val{:include}, io::IO, dir::RawFD, indent, filename; variables...)
    relpath, base_name = dirname(filename), basename(filename)
    if !isempty(relpath)
        dir = openat_raw(dir, relpath)
    end
    render(io, base_name, dir; indent=indent, variables=variables.data)
end


module_template(dirfd) = quote
    @generated function writehaml(io::IO, ::FR, ::Val{indent}; variables...) where FR <: $FileRevision where indent
        source = read(open(FR()), String)
        code = macroexpand($HAML, :( @_haml(io, $(string(indent)), variables, $($dirfd), $source) ))
        return code
    end
end

function getmodule(dir::RawFD)
    friendly = get!(() -> "", friendlynames, dir)
    num = reinterpret(Int32, dir)
    name = Symbol("FD$(num)_$(friendly)")
    try
        return getproperty(Generated, name)
    catch
        Base.eval(Generated, :( module $name $(module_template(dir)) end ))
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

function render(io::IO, filename::AbstractString, dir::RawFD; indent=Val(Symbol("")), variables=())
    file = openat(dir, filename)
    fr = FileRevision(file)
    open_files[fr] = file
    try
        fn = getproperty(getmodule(dir), :writehaml)
        return Base.invokelatest(fn, io, fr, indent; variables...)
    finally
        delete!(open_files, fr)
        close(file)
    end
end

function render(io, filename::AbstractString, dirname::AbstractString; kwds...)
    dir = open(dirname)
    dir = ccall(:open, RawFD, (Cstring, Int32), dirname, 0)
    reinterpret(Int32, dir) < 0 && error("Couldn't open $dirname")
    friendlynames[dir] = dirname
    return render(io, filename, dir; kwds...)
end

function render(io::IO, path::AbstractString; kwds...)
    dir_name, base_name = dirname(path), basename(path)

    return render(io, basename(path), dirname(path); kwds...)
end

end # module
