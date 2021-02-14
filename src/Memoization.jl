module Memoization

using MacroTools: splitdef, combinedef, splitarg, combinearg, isexpr
export @memoize

# Stores a mapping (func => cache) for each memoized function `func`.
const caches = WeakKeyDict()

# Stores a mapping (cache_constructor_exprs => cache) for each
# memoized function `func`, so that we can verify the same expression 
const cache_constructor_exprs = IdDict()

# Non-function "callables" or any function that has closed-over variables
# attached to it (indicated by having type parameters) are memoized
# per-instance. 
memoize_per_instance(::Type{F}) where {F<:Function} = !isempty(F.parameters)
memoize_per_instance(::Type) = true

# Look up (and possibly create) the cache for a given memoized function. Using a
# generated function allows us to move this lookup to compile time for top-level
# functions and improve performance.
@generated get_cache(func::F) where {F} =
    memoize_per_instance(F) ? :($caches[func]) : caches[F.instance]
    

"""
    empty_cache!(arg)
    
Empties the memoization cache for functions, closures, or callables.
    
For functions or closures, `arg` should be the name of the function or closure.
For callables, `arg` should be a type and the cache for all callable objects
matching that type will be cleared.
"""
empty_cache!(func) = map(empty!, values(find_caches(func)))
find_caches(func::F) where {F<:Function} = 
    filter((((func′,_),_),)->(memoize_per_instance(F) ? (func′ == func) : (func′ == F)), caches)
find_caches(F::Union{DataType,Union,UnionAll}) = 
    filter((((func′,_),_),)->(func′ isa F), caches)
empty_all_caches!() = map(empty!, values(caches))

"""
    @memoize f(x) = ...
    @memoize Dict f(x) = ... # with custom cache type
    @memoize LRU(maxsize=4) f(x) = ... # with custom cache type
    @memoize (::Foo)(x) = ... # memoizing a callable
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
    # if cache_constructor is a call, wrap it in a () -> ...
    if isexpr(cache_constructor,:call)
        cache_constructor = (:(() -> $cache_constructor),)
    end
    cache_constructor_expr = QuoteNode(Base.remove_linenums!(cache_constructor))
    # give unnamed args a placeholder name:
    sdef[:args] = map(sdef[:args]) do arg
        sarg = splitarg(arg)
        combinearg((sarg[1] == nothing ? gensym() : sarg[1]), sarg[2:end]...)
    end
    arg_signature   = [(issplat ? :($arg...) : arg)          for (arg,_,issplat) in map(splitarg,sdef[:args])]
    kwarg_signature = [(issplat ? :($arg...) : :($arg=$arg)) for (arg,_,issplat) in map(splitarg,sdef[:kwargs])]
    T, getter = (gensym.(("T","getter")))
    
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
        $_get!($getter, $get_cache($cacheid_get), (($(arg_signature...),),(;$(kwarg_signature...),))) :: $T
    end
    

    canary = gensym("canary")
    quote
        func = Core.@__doc__ $(esc(combinedef(sdef)))
        # only empty cache if this function definition is at the toplevel
        # see also: https://discourse.julialang.org/t/is-there-a-way-to-determine-whether-code-is-toplevel
        $(esc(canary)) = true
        if isdefined($__module__, $(QuoteNode(canary)))
            # $empty_cache!($(esc(cacheid_empty)))
        end
        # verify we haven't already memoized this function with some other cache type
        begin
            local cache = _get!($(esc(cache_constructor)), caches, func)
            if $(esc(cache_constructor)) isa Type
                if !(cache isa $(esc(cache_constructor)))
                    error("All methods must use same cache type, but $func is already memoized with $(typeof(cache))")
                end
            else
                local cache_constructor_expr′ = _get!(()->$cache_constructor_expr, cache_constructor_exprs, func)
                if cache_constructor_expr′ != $cache_constructor_expr
                    error("All methods must use same cache type, but $func is already memoized with:\n $cache_constructor_expr′")
                end
            end
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
