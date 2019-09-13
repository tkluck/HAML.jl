module Templates

import HAML

struct FileRevision{INode, MTime} end

const open_fds = Dict()

function Base.open(fr::FileRevision)
    fd = get!(() -> error("Compiling render function when fd has been closed already!"), open_fds, fr)
    io = open(fd)
    seek(io, 0)
    return io
end

module Generated end

function render end

function replace_quote_references(expr, repl)
    !(expr isa Expr) && return expr
    if expr.head == :$ && length(expr.args) == 1 && expr.args[1] isa Symbol
        return repl(expr.args[1])
    else
        return Expr(expr.head, map(a -> replace_quote_references(a, repl), expr.args)...)
    end
end

module_template(dirfd) = quote
    function hamlfilter(io::IO, ::Val{:include}, indent, filename; variables...)
        $render(io, filename, $dirfd; indent=indent, variables=variables.data)
    end
    @generated function writehaml(io::IO, ::FR, ::Val{indent}; variables...) where FR <: $FileRevision where indent
        source = read(open(FR()), String)
        code = macroexpand($HAML, :( @_haml io $(string(indent)) $source ))
        code = $replace_quote_references(code, sym -> :( variables.data.$sym ))
        return code
    end
end

function getmodule(dir::RawFD)
    st = stat(dir)
    if !iszero(st.inode)
        name = Symbol("Dev$(st.device)INode$(st.inode)")
        try
            return getproperty(Generated, name)
        catch
            Base.eval(Generated, :( module $name $(module_template(dir)) end ))
            return getproperty(Generated, name)
        end
    else
        error("Cannot read directory information")
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


    fd = ccall(:openat, RawFD, (RawFD, Cstring, Int32), dir, filename, 0)
    fr = FileRevision(fd)
    open_fds[fr] = fd
    try
        fn = getproperty(getmodule(dir), :writehaml)
        return Base.invokelatest(fn, io, fr, indent; variables...)
    finally
        delete!(open_fds, fr)
        ccall(:close, Int, (RawFD,), fd)
    end
end

function render(io::IO, path::AbstractString; kwds...)
    dir_name, base_name = dirname(path), basename(path)

    file, dir = nothing, nothing
    cd(dir_name) do
        # TODO: handle errors
        dir = ccall(:open, RawFD, (Cstring, Int32), :., 0)
    end

    return render(io, base_name, dir; kwds...)
end


end # module
