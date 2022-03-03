module Memoization

using MacroTools: splitdef, combinedef, splitarg, combinearg, isexpr
export @memoize

# Stores a mapping (func => cache) for each memoized function `func`.
const caches = IdDict()

# Stores a mapping (func => cache_constructor_expr) for each
# memoized function `func`, so that we can verify the same expression
# is always used.
const cache_constructor_exprs = IdDict()


# "Statically" memoizable functions are those where we can move the
# `get_cache` lookup below to compile time, as opposed to having to
# "dynamically" search the `caches` for the right cache at run-time.
# Right now, this includes just top-level functions, but in theory
# could maybe include non-closure inner functions in the future too.
statically_memoizable(::Type{F}) where {F} = isdefined(F, :instance)

# Lookup `func` in `caches`, and create its cache if its not there.
# Note: for statically memoizable functions, the macro below will also
# creates a @generated method for this function specific to each
# statically memoizable function, such that the lookup becomes static.
# The following definition is the dynamic fallback:
get_cache(default, func) = _get!(default, caches, func)


"""
    empty_cache!(arg)
    
Empties the memoization cache for functions, closures, or callables.
    
For functions or closures, `arg` should be the name of the function or closure.
For callables, `arg` should be a type and the cache for all callable objects
matching that type will be cleared.
"""
empty_cache!(func) = map(empty!, values(find_caches(func)))
find_caches(func::F) where {F<:Function} = 
    filter(((func′,_),)->(statically_memoizable(F) ? (func′ == func) : (func′ == F)), caches)
find_caches(F::Union{DataType,Union,UnionAll}) = 
    filter(((func′,_),)->(func′ isa F), caches)
empty_all_caches!() = map(empty!, values(caches))

"""
    @memoize f(x) = ...                # memoize a function definition
    @memoize Dict f(x) = ...           # with custom cache type
    @memoize LRU(maxsize=4) f(x) = ... # with another custom cache type
    @memoize (x::Foo)(y) = ...         # memoize a callable (w.r.t. both x and y)
    f(x) = @memoize g(y) = ...         # memoize a closure (w.r.t y, and x if its used)
    @memoize h(2)                      # memoize a call to any Julia function

When applied to a function definition, memoize a function, closure, or
callable, with respect to all of its arguments and keyword arguments.
When applied to a function call, memoize just that function call
(works with any Julia function).

Memoized closures or callables are memoized on a per-instance basis,
so closures are free to use the closed over variables and callables
are free to use the fields of the callable object.

By default, an IdDict is used as a cache. Any dict-like object can be
used by passing a type or an expression to construct the object as the
first argment to the macro before the function definition. For
example, if you want to memoize based on the contents of vectors, you
could use a `Dict`.
"""
macro memoize(ex1, ex2=nothing)
    cache_constructor, func_call_or_def = ex2 == nothing ? (IdDict, ex1) : (ex1, ex2)
    cache_constructor_expr = QuoteNode(Base.remove_linenums!(cache_constructor))
    # if cache_constructor is a call, wrap it in a () -> ...to make it a callable
    if isexpr(cache_constructor, :call)
        cache_constructor = :(() -> $cache_constructor)
    end
    if isexpr(func_call_or_def, :call)
        _memoize_funccall(cache_constructor, func_call_or_def)
    else
        _memoize_funcdef(cache_constructor, cache_constructor_expr, func_call_or_def)
    end
end


function _memoize_funcdef(cache_constructor, cache_constructor_expr, funcdef)
    sdef = splitdef(funcdef)
    # give unnamed args placeholder names
    sdef[:args] = map(sdef[:args]) do arg
        sarg = splitarg(arg)
        combinearg((sarg[1] == nothing ? gensym() : sarg[1]), sarg[2:end]...)
    end
    # give anonymous function placeholder name
    if !haskey(sdef, :name)
        sdef[:name] = gensym()
    end
    args   = [(issplat ? :($arg...) : arg)          for (arg,_,issplat) in map(splitarg,sdef[:args])]
    kwargs = [(issplat ? :($arg...) : :($arg=$arg)) for (arg,_,issplat) in map(splitarg,sdef[:kwargs])]
    
    # if memoizing just `f(x) = ...` we want to call both `get_cache` and
    # `empty_cache` on `f`, but if memoizing a callable like
    # `(x::Foo{T})(args...) where {T} = ...`, we want to call get_cache on `x`
    # but empty_cache on `Foo{T} where {T}`
    if isexpr(sdef[:name], :(::))
        length(sdef[:name].args)==1 && pushfirst!(sdef[:name].args, gensym())
        cacheid_get   = sdef[:name].args[1]
        cacheid_empty = :($(sdef[:name].args[2]) where {$(sdef[:whereparams]...)})
    else
        cacheid_get = cacheid_empty = sdef[:name]
    end
    
    # the body of the function definition is replaced with this:
    sdef[:body] = _memoized_call(cache_constructor, cacheid_get, sdef[:body], args, kwargs)

    quote
        func = Core.@__doc__ $(esc(combinedef(sdef)))
        begin
            # verify we haven't already memoized this function with a different cache type
            local cache_constructor_expr′ = _get!(()->$cache_constructor_expr, cache_constructor_exprs, func)
            if cache_constructor_expr′ != $cache_constructor_expr
                error("$func is already memoized with $cache_constructor_expr′")
            end
        end
        if statically_memoizable(typeof(func))
            # if it doesnt exist yet, define a get_cache specific to
            # `func`. by using a @generated function which directly
            # returns the cache, this effectively causes the cache lookup to
            # be done at compile time
            if first(methods($Memoization.get_cache, Tuple{Any,typeof(func)})).sig.parameters[3] == Any
                @eval @generated function $Memoization.get_cache(_, f::typeof($(Expr(:$,:func))))
                    $_get!($cache_constructor, $Memoization.caches, f.instance)
                end
            end
            # since here we know this is a top-level function
            # definition, we also need to clear the cache (if it
            # exists) as existing memoized results may have been
            # invalidated by the new definition
            $empty_cache!($(esc(cacheid_empty)))
        end
        func
    end
end


function _memoize_funccall(cache_constructor, funccall)
    funcname = funccall.args[1]
    args, kwargs = [], []
    for arg in funccall.args[2:end]
        if isexpr(arg, :kw)
            push!(kwargs, Expr(:(=), arg.args...))
        elseif isexpr(arg, :parameters)
            push!(kwargs, arg)
        else
            push!(args, arg)
        end
    end
    esc(_memoized_call(cache_constructor, funcname, funccall, args, kwargs))
end


function _memoized_call(cache_constructor, cacheid_get, getter_body, args, kwargs)
    T, getter = gensym.(("T","getter"))
    quote
        cache = $get_cache($cache_constructor, $cacheid_get)
        ($getter)() = $getter_body
        $T = $(Core.Compiler.return_type)($getter, $Tuple{})
        $_get!($getter, cache, (($(args...),), ($(kwargs...),))) :: $T
    end
end


_get!(args...) = get!(args...)
if VERSION < v"1.1.0-DEV.752"
    # this was only added in https://github.com/JuliaLang/julia/commit/7ba6c824467d2df51db6e091bbfc9e821e5a6dc2
    function _get!(default::Base.Callable, d::IdDict{K,V}, @nospecialize(key)) where {K, V}
        val = get(d, key, Base.secret_table_token)
        if val === Base.secret_table_token
            val = default()
            setindex!(d, val, key)
        end
        return val
    end
end

end
