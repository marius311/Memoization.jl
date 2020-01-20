module Memoization

using MacroTools: splitdef, combinedef, splitarg, isexpr
export @memoize

# Stores a mapping from (f, cache_type) to individual caches for each memoized
# function. The key is different if we are memoizing a top-level function vs. a
# closure. For top-level functions, f is the function's type. For closures, f is the
# actual instance of the closure (hence we will have a different entry for each
# instance, which is good since each one might have different closed-over
# variables).
const caches = IdDict()

# A closure counts as a non-function "callable" or any function that has
# closed-over variables attached to it, indicated by having type parameters.
isclosure(::Type{F}) where {F<:Function} = !isempty(F.parameters)
isclosure(::Type) = true

# A generated function is used to look up the cache for any given top-level
# function or closure. For top-level functions, we are effectively pasting the
# appropriate cache directly into the expression tree at compile time, so its
# super fast. For closures, we have to do the lookup at run-time, so its a
# little bit slower.
@generated function get_cache(f::F, ::Type{D}=IdDict) where {F, D<:AbstractDict}
    isclosure(F) ? :(_get!($(()->D()), $caches, (f,D))) : _get!(()->D(), caches, (F,D))
end

"""
    empty_cache!(arg)
    
Empties the memoization cache for functions, closures, or callables.
    
For functions or closures, `arg` should be the name of the function or closure.
For callables, `arg` should be a type and the cache for all callable objects
matching that type will be cleared.
"""
empty_cache!(f) = map(empty!, values(find_caches(f)))
find_caches(f::F) where {F<:Function} = filter((((f′,_),_))->(isclosure(F) ? (f′ == f) : (f′ == F)), caches)
find_caches(F::Union{DataType,Union,UnionAll}) = filter((((f′,_),_))->(f′ isa F), caches)
empty_all_caches!() = map(empty!, values(caches))

"""
    @memoize f(x) = ...
    @memoize Dict f(x) = ... # with custom cache type
    @memoize (::Foo)(x) = ... # memoizing a callable
    f(x) = @memoize g(y) = ... # memoizing a closure

Memoize a function, closure, or callable, with respect to all of its arguments
and keyword arguments.

Memoized closures or callables are memoized on a per-instance basis, so closures
are free to use the closed over variables and callables are free to use the
fields of the callable object.

By default, an IdDict is used as a cache. Any `AbstractDict` can be used instead
by passing the type as the first argment to the macro before the function
definition. For example, if you want to memoize based on the contents of
vectors, you could use a `Dict`.
"""
macro memoize(ex1, ex2=nothing)
    cachetype, funcdef = ex2 == nothing ? ((), ex1) : ((ex1,), ex2)
    sdef = splitdef(funcdef)
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
    
    sdef[:body] = quote
        ($getter)() = $(sdef[:body])
        $T = $(Core.Compiler.return_type)($getter, $Tuple{})
        $_get!($getter, $get_cache($cacheid_get, $(cachetype...)), (($(arg_signature...),),(;$(kwarg_signature...),))) :: $T
    end
    quote
        func = Core.@__doc__ $(esc(combinedef(sdef)))
        $empty_cache!($(esc(cacheid_empty)))
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
