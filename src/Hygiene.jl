module Hygiene

mapexpr(f, expr) = expr
mapexpr(f, expr::Expr) = begin
    res = Expr(expr.head)
    resize!(res.args, length(expr.args))
    map!(f, res.args, expr.args)
    return res
end

macro hygienic(expr)
    return expr
end

const at_hygienic = var"@hygienic"

function make_hygienic(outermod, expr)
    dummy_linenode = LineNumberNode(@__LINE__, Symbol(@__FILE__))
    return macroexpand(outermod, Expr(:macrocall, at_hygienic, dummy_linenode, expr), recursive=false)
end

hasnode(head, expr) = false
hasnode(head, expr::Expr) = expr.head == head || any(a -> hasnode(head, a), expr.args)
hasmacrocall(expr) = hasnode(:macrocall, expr)

function _replace_expression_nodes_unescaped(f, head, expr, should_escape)
    if !hasnode(head, expr)
        return expr, should_escape
    elseif expr isa Expr && expr.head == head
        if should_escape
            return f(esc, expr.args...), false
        else
            return f(identity, expr.args...), false
        end
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

function mapesc(f, expr)
    if expr isa Expr && expr.head == :escape
        return mapexpr(f, expr)
    else
        return mapexpr(a -> mapesc(f, a), expr)
    end
end

function expand_macros_hygienic(outermod, innermod, expr)
    expr = mapesc(expr) do a
        macroexpand(innermod, a)
    end
    expr = macroexpand(outermod, expr)
    return expr
end

escapeassignments(expr) = expr
escapeassignments(expr::Expr) = if expr.head == :block
    return Expr(:block, map(escapeassignments, expr.args)...)
elseif expr.head == :(=)
    return Expr(:(=), map(esc, expr.args)...)
else
    return expr
end

escapelet(expr::Expr) = begin
    @assert expr.head == :let
    return Expr(:let, escapeassignments(expr.args[1]), expr.args[2:end]...)
end

end # module
