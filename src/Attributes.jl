module Attributes

import DataStructures: OrderedDict
import Markdown: htmlesc

function makeattr(name, val)
    ignore(x) = isnothing(x) || x === false
    val = filter(!ignore, [val;])
    isempty(val) && return (false, nothing, nothing)

    if name == :class
        value = join(val, " ")
    elseif name == :id
        value = join(val, "-")
    else
        ix = findlast(!ignore, val)
        value = val[ix]
    end
    if value === true
        valuerepr = string(name)
    else
        valuerepr = string(value)
    end
    namerepr = replace(string(name), "_" => "-")
    return (true, htmlesc(namerepr), htmlesc(valuerepr))
end

join_attr_name(x...) = Symbol(join(x, "-"))
recurse_attributes(x, path...) = (join_attr_name(path...) => x,)
recurse_attributes(x::Pair, path...) = recurse_attributes(x[2], path..., x[1])
recurse_attributes(x::Union{NamedTuple,AbstractDict}, path...) = (attr for pair in pairs(x) for attr in recurse_attributes(pair, path...))
recurse_attributes(x::AbstractVector, path...) = (attr for pair in x for attr in recurse_attributes(pair, path...))

function writeattributes(io, attributes)
    collected_attributes = OrderedDict()
    for (name, value) in recurse_attributes(attributes)
        a = get!(Vector, collected_attributes, name)
        append!(a, [value;])
    end
    for (name, value) in pairs(collected_attributes)
        (valid, name, value) = makeattr(name, value)
        valid || continue
        write(io, " ", name, "='", value, "'")
    end
end

function mergeattributes(attr, keyvalue)
    return :( $mergeattributes($attr, $keyvalue) )
end

function mergeattributes(attr, kv, kvs...)
    return mergeattributes(mergeattributes(attr, kv), kvs...)
end

function mergeattributes(attr, keyvalue::Expr)
    if keyvalue.head == :(=)
        k, v = keyvalue.args[1:2]
        @assert k isa Symbol
        if v isa String
            return mergeattributes(attr, k => v)
        else
            k = QuoteNode(k)
            v = esc(v)
            return :( $mergeattributes($attr, $k => $v) )
        end
    elseif keyvalue.head == :call && keyvalue.args[1] == :(=>)
        k, v = keyvalue.args[2:3]
        k = esc(k)
        v = esc(v)
        return :( $mergeattributes($attr, $k => $v) )
    elseif keyvalue.head == :...
        kvs = esc(keyvalue.args[1])
        return :( $mergeattributes($attr, $pairs($kvs)...) )
    else
        error()
    end
end

function mergeattributes(attr::AbstractDict, (key, val)::Pair{Symbol})
    res = copy(attr)

    ignore(x) = isnothing(x) || x === false
    val = filter(!ignore, [val;])
    isempty(val) && return

    key = replace(string(key), "_" => "-")

    if key == "class" || key == "id"
        a = get!(Vector, res, key)
        append!(a, val)
    else
        res[key] = val[end]
    end

    return res
end

function writeattributes(attr)
    return :( $writeattributes(@io, $attr) )
end

function writeattributes(attr::AbstractDict)
    io = IOBuffer()
    writeattributes(io, attr)
    attrstr = String(take!(io))
    return :( @output $attrstr )
end

end # module
