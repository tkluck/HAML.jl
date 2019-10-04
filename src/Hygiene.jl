module Hygiene

macro hygienic(expr)
    return expr
end

const at_hygienic = getproperty(@__MODULE__, Symbol("@hygienic"))

function hasmacrocall(expr)
    if expr isa Expr && expr.head == :macrocall
        return true
    elseif expr isa Expr
        return any(hasmacrocall, expr.args)
    else
        return false
    end
end

function deref(mod, expr)
    if expr isa Symbol
        return getproperty(mod, expr)
    elseif expr isa GlobalRef
        return getproperty(expr.mod, expr.symbol)
    elseif expr isa Expr && expr.head == :.
        return deref(getproperty(mod, expr.args[1]), expr.args[2])
    elseif expr isa QuoteNode
        return deref(mod, expr.value)
    else
        dump(expr)
        error("Don't know how to de-reference $expr")
    end
end

function _replace_macro_and_escape_rest(mod, expr, substitutions...)
    if expr isa Expr && expr.head == :macrocall
        for (before, after) in substitutions
            if deref(mod, expr.args[1]) == before
                return after, false
            end
        end
        return macroexpand(mod, expr, recursive=false), true
    elseif expr isa Expr
        result = map(expr.args) do a
            _replace_macro_and_escape_rest(mod, a, substitutions...)
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

function _replace_macro_hygienic(outermod, innermod, expr, substitutions...)
    if expr isa Expr && expr.head == :macrocall
        for (before, after) in substitutions
            if deref(outermod, expr.args[1]) == before
                return after
            end
        end
        return macroexpand(outermod, expr, recursive=false)
    elseif expr isa Expr && expr.head == :escape
        e, should_escape = _replace_macro_and_escape_rest(innermod, expr.args[1], substitutions...)
        return should_escape ? esc(e) : e
    elseif expr isa Expr
        args = map(expr.args) do a
            _replace_macro_hygienic(outermod, innermod, a, substitutions...)
        end
        return Expr(expr.head, args...)
    else
        return expr
    end
end

function replace_macro_hygienic(outermod, innermod, expr, substitutions...)
    while hasmacrocall(expr)
        expr = _replace_macro_hygienic(outermod, innermod, expr, substitutions...)
    end
    return expr
end

function make_hygienic(outermod, expr)
    dummy_linenode = LineNumberNode(@__LINE__, @__FILE__)
    return macroexpand(outermod, Expr(:macrocall, at_hygienic, dummy_linenode, expr), recursive=false)
end

end # module
