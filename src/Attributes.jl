"""
    module HAML.Attributes

Contains functions for HAML-style flexible representation of attributes:
`id` attributes through `#`, `class` attributes through `.`, and any
attributes through a named tuple syntax.

Whenever possible we expand the attributes at compile time but we fallback
to dynamic expansion when necessary.
"""
module Attributes

import DataStructures: OrderedDict

import ..Escaping: htmlesc
import ..Hygiene: isexpr

AttributeVals() = NamedTuple()

mergeattributes(attrs, (k, v)::Pair) = :( $a($attrs, ($k = $(esc(v)),)) )
mergeattributes(attrs, expr) = :( $a($attrs, $pairs($(esc(expr)))...) )

@generated function a(attrs::NamedTuple, x::NamedTuple)
    @assert length(fieldnames(x)) == 1
    name, = fieldnames(x)

    curval = name in fieldnames(attrs) ? :( attrs.$name ) : nothing

    if name == :class
        return :( Base.merge(attrs, ($name = mergeclass($curval, x.$name),)) )
    elseif name == :id
        return :( Base.merge(attrs, ($name = mergeid($curval, x.$name),)) )
    else
        return :( Base.merge(attrs, ($name = mergeval($curval, x.$name),)) )
    end
end

function a(attrs::NamedTuple, xs::Pair...)
    for (name, val) in xs
        curval = name in fieldnames(typeof(attrs)) ? getproperty(attrs, name) : nothing
        if name == :class
            attrs = Base.setindex(attrs, mergeclass(curval, val), name)
        elseif name == :id
            attrs = Base.setindex(attrs, mergeid(curval, val), name)
        else
            attrs = Base.setindex(attrs, mergeval(curval, val), name)
        end
    end
    attrs
end

const NestedType = Union{NamedTuple, AbstractDict}
const MultipleType = Union{AbstractVector, AbstractSet}

joinpath(path...) = join(path, "-")

ignore(::Nothing) = true
ignore(x::Bool) = !x
ignore(x) = false

joinid(::Nothing, val) = string(val)

function joinid(vals...)
    v = filter(!ignore, vals)
    return isempty(v) ? nothing : join(v, "-")
end

function joinclass(vals...)
    v = filter(!ignore, vals)
    return isempty(v) ? nothing : join(v, " ")
end

leaf(::Nothing) = nothing
leaf(x) = x.leaf
children(::Nothing) = NamedTuple()
children(x) = x.children

function merge(x::NamedTuple, y::NestedType)
    for (name, val) in pairs(y)
        curval = name in fieldnames(typeof(x)) ? getproperty(x, name) : nothing
        x = Base.setindex(x, mergeval(curval, val), name)
    end
    x
end

mergeid(curval, val::Nothing) = curval
mergeid(curval, val::NestedType) = (leaf=leaf(curval), children=merge(children(curval), val))
mergeid(curval, val::MultipleType) = (leaf=joinid(leaf(curval), val...), children=children(curval))
mergeid(curval, val) = (leaf=joinid(leaf(curval), val), children=children(curval))

mergeclass(curval, val::Nothing) = curval
mergeclass(curval, val::NestedType) = (leaf=leaf(curval), children=merge(children(curval), val))
mergeclass(curval, val::MultipleType) = (leaf=joinclass(leaf(curval), val...), children=children(curval))
mergeclass(curval, val) = (leaf=joinclass(leaf(curval), val), children=children(curval))

mergeval(curval, val::Nothing) = curval
mergeval(curval, val::NestedType) = (leaf=leaf(curval), children=merge(children(curval), val))
mergeval(curval, val::MultipleType) = (leaf=last(val), children=children(curval))
mergeval(curval, val) = (leaf=val, children=children(curval))

isconstant(::Union{AbstractString, Number, Tuple, NamedTuple}) = true
isconstant(x) = false

function foldconstants(expr)
    if isexpr(:call, expr) && expr.args[1] == a
        args = map(foldconstants, expr.args[2:end])
        if all(isconstant, args)
            return a(args...)
        end
    elseif isexpr(:escape, expr)
        arg = foldconstants(expr.args[1])
        if isconstant(arg)
           return arg
        end
    elseif isexpr(:tuple, expr) && length(expr.args) == 1
        arg = expr.args[1]
        if isexpr(:(=), arg) && arg.args[1] isa Symbol
            x = foldconstants(arg.args[2])
            if isconstant(x)
                return NamedTuple{(arg.args[1],)}((x,))
            end
        end
    end

    return expr
end

function writeattributes(attrs)
    attrs = foldconstants(attrs)

    if attrs isa NamedTuple
        s = sprint(io -> attributes_to_string(io, attrs))
        return :( @output $s )
    else
        return :( $attributes_to_string(@io, $attrs) )
    end
end

@generated function attributes_to_string(io::IO, attrs::NamedTuple, prefix::Val{Prefix}=Val(Symbol(""))) where Prefix
    code = quote
    end

    for k in fieldnames(attrs)
        kk = htmlesc(replace("$Prefix$k", '_' => '-'))
        nested_prefix = Val(Symbol("$kk-"))
        push!(code.args, quote
            if !isnothing(attrs.$k.leaf) && attrs.$k.leaf !== false
                print(io, ' ', $kk, "='")
                if attrs.$k.leaf == true
                    htmlesc(io, $kk)
                else
                    htmlesc(io, attrs.$k.leaf)
                end
                print(io, "'")
            end
            if !isnothing(attrs.$k.children)
                attributes_to_string(io, attrs.$k.children, $nested_prefix)
            end
        end)
    end

    code
end

end # module
