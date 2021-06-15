module Memoization

using MacroTools: splitdef, combinedef, splitarg, combinearg, isexpr
export @memoize

# Stores a mapping (memoizable-object => cache) for each memoized object.
const caches = IdDict()

# Stores a mapping (memoizable-object => cache_constructor_expr) for each
# memoized object, so that we can verify the same expression
# is always used.
const cache_constructor_exprs = IdDict()


is_top_level_func(::Type{M}) where {M} = isdefined(M, :instance)


# Look up a given memoizable object in Memoization.caches.
#
# There's three ways this can happen below:
#
# 1) Its a top-level function and we are allowed to call the
#    DefaultCache() function from the world-age of get_cache, so just
#    do so and return the cache outright (totally static cache lookup,
#    easiest option)
#
# 2) Its a top-level function but DefaultCache() was defined *after*
#    get_cache, so we're not allowed to call it. In this case, do a
#    dynamic lookup, but also set the function body up so that it
#    defines a specialized get_cache which will make the next call
#    after we hit top-level static. Couple of caveats are a) we can't
#    do this during precompilation of a module (jl_generating_output),
#    b) we can't do this is the memoized call is itself inside a pure
#    context like another generated function (jl_is_in_pure_context),
#    and c) for performance, we have to be careful to make the @eval
#    only get called once even if we don't hit top-level before the
#    second call.
#
# 3) Its a closure or callable, so just do the necessary dynamic
#    lookup. 
#
@generated function get_cache(::Val{DefaultCache}, memoizable_obj::M) where {DefaultCache, M}
    if is_top_level_func(M)
        try
            # (1)
            return caches[M.instance] = DefaultCache()
        catch err
            if !(err isa MethodError) || (err.f != DefaultCache)
                rethrow() # kludgy way to only catch a world-age error in DefaultCache()
            end
        end
        if ccall(:jl_generating_output,Cint,()) == 0
            # (2)
            return quote
                cache = get($caches, memoizable_obj, nothing) # cant use get! here since it needs a closure
                if cache === nothing
                    cache = $caches[memoizable_obj] = DefaultCache()
                    if ccall(:jl_is_in_pure_context, Cint, ()) == 0
                        @eval @generated get_cache(::Val{DefaultCache}, ::$M) where {DefaultCache} = caches[$(M.instance)]
                    end
                end
                cache
            end
        end
    end
    # (3)
    return quote
        _get!(DefaultCache, $caches, memoizable_obj)
    end
end



"""
    empty_cache!(arg)
    
Empties the memoization cache for functions, closures, or callables.
    
For functions or closures, `arg` should be the name of the function or closure.
For callables, `arg` should be a type and the cache for all callable objects
matching that type will be cleared.
"""
empty_cache!(func) = map(empty!, values(find_caches(func)))
find_caches(func::F) where {F<:Function} = 
    filter(((func′,_),)->(is_top_level_func(F) ? (func′ == func) : (func′ == F)), caches)
find_caches(F::Union{DataType,Union,UnionAll}) = 
    filter(((func′,_),)->(func′ isa F), caches)
empty_all_caches!() = map(empty!, values(caches))

"""
    @memoize f(x) = ...
    @memoize Dict f(x) = ... # with custom cache type
    @memoize LRU(maxsize=4) f(x) = ... # with custom cache type
    @memoize (x::Foo)(y) = ... # memoizing a callable (on both x and y)
    f(x) = @memoize g(y) = ... # memoizing a closure

Memoize a function, closure, or callable, with respect to all of its arguments
and keyword arguments.

Memoized closures or callables are memoized on a per-instance basis, so closures
are free to use the closed over variables and callables are free to use the
fields of the callable object.

By default, an IdDict is used as a cache. Any dict-like object can be used by
passing a type or an expression to construct the object as the first argment to
the macro before the function definition. For example, if you want to memoize
based on the contents of vectors, you could use a `Dict`.
"""
macro memoize(ex1, ex2=nothing)
    cache_constructor, funcdef = ex2 == nothing ? (IdDict, ex1) : (ex1, ex2)
    sdef = splitdef(funcdef)
    cache_constructor_expr = QuoteNode(Base.remove_linenums!(cache_constructor))
    # if cache_constructor is a call, wrap it in a () -> ...to make it a callable
    if isexpr(cache_constructor, :call)
        cache_constructor = :(() -> $cache_constructor)
    end
    # give unnamed args placeholder names
    sdef[:args] = map(sdef[:args]) do arg
        sarg = splitarg(arg)
        combinearg((sarg[1] == nothing ? gensym() : sarg[1]), sarg[2:end]...)
    end
    arg_signature   = [(issplat ? :($arg...) : arg)          for (arg,_,issplat) in map(splitarg,sdef[:args])]
    kwarg_signature = [(issplat ? :($arg...) : :($arg=$arg)) for (arg,_,issplat) in map(splitarg,sdef[:kwargs])]
    T, getter = gensym.(("T","getter"))
    
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
    sdef[:body] = quote
        ($getter)() = $(sdef[:body])
        $T = $(Core.Compiler.return_type)($getter, $Tuple{})
        $_get!($getter, $get_cache(Val($cache_constructor), $cacheid_get), (($(arg_signature...),),(;$(kwarg_signature...),))) :: $T
    end
    

    canary = gensym("canary")
    quote
        func = Core.@__doc__ $(esc(combinedef(sdef)))
        begin
            # verify we haven't already memoized this function with a different cache type
            local cache_constructor_expr′ = _get!(()->$cache_constructor_expr, cache_constructor_exprs, func)
            if cache_constructor_expr′ != $cache_constructor_expr
                error("$func is already memoized with $cache_constructor_expr′")
            end
        end
        # empty cache, but only if this is a top-level function definition
        # see also: https://discourse.julialang.org/t/is-there-a-way-to-determine-whether-code-is-toplevel
        $(esc(canary)) = true
        if isdefined($__module__, $(QuoteNode(canary)))
            $empty_cache!($(esc(cacheid_empty)))
        end
        func
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
