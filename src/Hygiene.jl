module Hygiene

function mapexpr(f, expr)
    res = Expr(expr.head)
    resize!(res.args, length(expr.args))
    map!(f, res.args, expr.args)
    return res
end

macro hygienic(expr)
    return expr
end

const at_hygienic = getproperty(@__MODULE__, Symbol("@hygienic"))

function make_hygienic(outermod, expr)
    dummy_linenode = LineNumberNode(@__LINE__, @__FILE__)
    return macroexpand(outermod, Expr(:macrocall, at_hygienic, dummy_linenode, expr), recursive=false)
end

hasnode(head, expr) = false
hasnode(head, expr::Expr) = expr.head == head || any(a -> hasnode(head, a), expr.args)
hasmacrocall(expr) = hasnode(:macrocall, expr)

function _replace_expression_nodes_unescaped(f, head, expr, should_escape)
    if !hasnode(head, expr)
        return expr, false
    elseif expr isa Expr && expr.head == head
        return f(expr.args...), false
    elseif expr isa Expr && expr.head == :escape
        res, should_escape = _replace_expression_nodes_unescaped(f, head, expr.args[1], true)
        return res, should_escape
    elseif expr isa Expr
        result = Vector{Any}(undef, length(expr.args))
        map!(result, expr.args) do a
            _replace_expression_nodes_unescaped(f, head, a, should_escape)
        end
        if all(r -> r[2], result)
            args = map(r -> r[1], result)
            should_escape = true
        else
            args = map(result) do A
                a, should_escape = A
                should_escape ? esc(a) : a
            end
            should_escape = false
        end
        return Expr(expr.head, args...), should_escape
    else
        return expr, should_escape
    end
end

function replace_expression_nodes_unescaped(f, head, expr)
    expr, should_escape = _replace_expression_nodes_unescaped(f, head, expr, false)
    return should_escape ? esc(expr) : expr
end

function _expand_macros_hygienic(outermod, innermod, expr)
    if !hasmacrocall(expr)
        return expr
    elseif expr isa Expr && expr.head == :macrocall
        return macroexpand(outermod, expr, recursive=false)
    elseif expr isa Expr && expr.head == :escape
        # FIXME: not sure if we should traverse multiple levels of escaping,
        # but if we don't we risk an infinite loop in while hasmacrocall(...)
        # below.
        return esc(_expand_macros_hygienic(innermod, innermod, expr.args[1]))
    elseif expr isa Expr
        return mapexpr(expr) do a
            _expand_macros_hygienic(outermod, innermod, a)
        end
    else
        return expr
    end
end

function expand_macros_hygienic(outermod, innermod, expr)
    while hasmacrocall(expr)
        expr = _expand_macros_hygienic(outermod, innermod, expr)
    end
    return expr
end

function _invert_escaping(expr)
    if !hasnode(:escape, expr)
        return expr, true
    elseif expr isa Expr && expr.head == :escape
        return expr.args[1], false
    elseif expr isa Expr && expr.head == :(=)
        tgt = invert_escaping(expr.args[1])
        val = invert_escaping(expr.args[2])
        return Expr(:(=), tgt, val), false
    elseif expr isa Expr
        result = Vector{Any}(undef, length(expr.args))
        map!(result, expr.args) do a
            _invert_escaping(a)
        end
        if all(r -> r[2], result)
            args = map(r -> r[1], result)
            should_escape = true
        else
            args = map(result) do A
                a, should_escape = A
                should_escape ? esc(a) : a
            end
            should_escape = false
        end
        return Expr(expr.head, args...), should_escape
    else
        return expr, true
    end
end

function invert_escaping(expr)
    expr, should_escape = _invert_escaping(expr)
    return should_escape ? esc(expr) : expr
end

end # module
