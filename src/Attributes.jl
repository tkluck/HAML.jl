"""
    module HAML.Attributes

Contains functions for HAML-style flexible representation of attributes:
`id` attributes through `#`, `class` attributes through `.`, and any
attributes through a named tuple syntax.

Whenever possible we expand the attributes at compile time but we fallback
to dynamic expansion when necessary. The former case is represented by
`NamedTuple`s and the latter by `OrderedDict{Symbol}`s.
"""
module Attributes

import DataStructures: OrderedDict

import ..Escaping: LiteralHTML, htmlesc
import ..Hygiene: @nolinenodes, isexpr, mapexpr

abstract type Level end
struct TopLevel <: Level end
struct NestedLevel <: Level end

const NestedType = Union{NamedTuple, AbstractDict{Symbol}}
const MultipleType = Union{AbstractVector, AbstractSet}

AttributeVals() = NamedTuple()

mergeexpr(attrs, (k, v)::Pair) = :( $tlmerge($attrs, ($k = $(esc(v)),)) )
mergeexpr(attrs, expr) = :( $tlmerge($attrs, $pairs($(esc(expr)))...) )

tlmerge(args...) = merge(TopLevel(), args...)

@generated function merge(level::Level, attrs::NamedTuple, x::NamedTuple)
    code = quote
    end
    for name in fieldnames(x)
        curval = name in fieldnames(attrs) ? :( attrs.$name ) : nothing

        if level == TopLevel && name == :class
            push!(code.args, :( attrs = Base.merge(attrs, ($name = mergeclass($curval, x.$name),)) ))
        elseif level == TopLevel && name == :id
            push!(code.args, :( attrs = Base.merge(attrs, ($name = mergeid($curval, x.$name),)) ))
        else
            push!(code.args, :( attrs = Base.merge(attrs, ($name = mergeval($curval, x.$name),)) ))
        end
    end
    code
end


function merge(level::Level, attrs::NestedType, xs::Pair...)
    # attribute names in `xs` might be dynamic, so don't use named
    # tuple or the compiler will want to instantiate a different
    # method for each.
    if attrs isa NamedTuple
        attrs = OrderedDict{Symbol, Any}(pairs(attrs))
    end
    for (name, val) in xs
        curval = name in fieldnames(typeof(attrs)) ? getproperty(attrs, name) : nothing
        if level == TopLevel() && name == :class
            attrs[name] = mergeclass(curval, val)
        elseif level == TopLevel() && name == :id
            attrs[name] = mergeid(curval, val)
        else
            attrs[name] = mergeval(curval, val)
        end
    end
    attrs
end

merge(level::Level, attrs::NestedType, xs) = merge(level, attrs, pairs(xs)...)

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

mergeid(curval, val::Nothing) = curval
mergeid(curval, val::NestedType) = (leaf=leaf(curval), children=merge(NestedLevel(), children(curval), val))
mergeid(curval, val::MultipleType) = (leaf=joinid(leaf(curval), val...), children=children(curval))
mergeid(curval, val) = (leaf=joinid(leaf(curval), val), children=children(curval))

mergeclass(curval, val::Nothing) = curval
mergeclass(curval, val::NestedType) = (leaf=leaf(curval), children=merge(NestedLevel(), children(curval), val))
mergeclass(curval, val::MultipleType) = (leaf=joinclass(leaf(curval), val...), children=children(curval))
mergeclass(curval, val) = (leaf=joinclass(leaf(curval), val), children=children(curval))

mergeval(curval, val::Nothing) = curval
mergeval(curval, val::NestedType) = (leaf=leaf(curval), children=merge(NestedLevel(), children(curval), val))
mergeval(curval, val::MultipleType) = (leaf=last(val), children=children(curval))
mergeval(curval, val) = (leaf=val, children=children(curval))

isconstant(::Union{AbstractString, Number, Tuple, NamedTuple}) = true
isconstant(x) = false

function foldconstants(expr)
    if isexpr(:call, expr) && expr.args[1] in (merge, tlmerge)
        args = map(foldconstants, expr.args[2:end])
        if all(isconstant, args)
            return expr.args[1](args...)
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

function writeattributes(loc, attrs)
    attrs = foldconstants(attrs)

    if attrs isa NamedTuple
        s = LiteralHTML(io -> attributes_to_string(io, attrs))
        return :( @output $s )
    else
        return Expr(:block,
            loc,
            :( $attributes_to_string(@io, $attrs) ),
        )
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

function attributes_to_string(io::IO, attrs, prefix::String="")
    for (k, v) in pairs(attrs)
        kk = htmlesc(replace("$prefix$k", '_' => '-'))
        nested_prefix = "$kk-"
        if !isnothing(v.leaf) && v.leaf !== false
            print(io, ' ', kk, "='")
            if v.leaf == true
                htmlesc(io, kk)
            else
                htmlesc(io, v.leaf)
            end
            print(io, "'")
        end
        if !isnothing(v.children)
            attributes_to_string(io, v.children, nested_prefix)
        end
    end
end

function expand_tag_blocks(code)
    if isexpr(:hamltag, code)
        tagname, line_number_node, attrs, closingslash, contents = code.args
        contents = mapexpr(expand_tag_blocks, contents)

        @assert isexpr(:hamlattrs, attrs)
        attrsexpr = AttributeVals()
        for a in attrs.args
            if isexpr(:(=), a)
                attrsexpr = mergeexpr(attrsexpr, a.args[1] => a.args[2])
            elseif isexpr(:(...), a)
                attrsexpr = mergeexpr(attrsexpr, :( (;$a) ))
            elseif isexpr(:call, a) && a.args[1] == :(=>)
                attrsexpr = mergeexpr(attrsexpr, :( (;$a) ))
            else
                error("Unexpected expression inside attribute block: '$a'")
            end
        end

        attrsexpr = writeattributes(line_number_node, attrsexpr)

        if closingslash
            return @nolinenodes quote
                @output $(LiteralHTML("<$tagname"))
                $attrsexpr
                @output $(LiteralHTML(" />"))
            end
        else
            return @nolinenodes quote
                @output $(LiteralHTML("<$tagname"))
                $attrsexpr
                @output $(LiteralHTML(">"))
                $((isnothing(contents) ? [] : [contents])...)
                @output $(LiteralHTML("</$tagname>"))
            end
        end
    elseif code isa Expr
        return mapexpr(expand_tag_blocks, code)
    else
        return code
    end
end

end # module
