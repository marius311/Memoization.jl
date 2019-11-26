module Memoization

using MacroTools: splitdef, combinedef, splitarg
export @memoize

# Stores a mapping from (f, cache_type) to individual caches for each memoized
# function. The key is different if we are memoizing a top-level function vs. a
# closure. For top-level functions, f is the function's type. For closures, f is the
# actual instance of the closure (hence we will have a different entry for each
# instance, which is good since each one might have different closed-over
# variables).
const caches = IdDict()

# A closure counts as any function that has closed-over variables attached to
# it, indicated by having type parameters.
isclosure(::Type{F}) where {F<:Function} = !isempty(F.parameters)

# A generated function is used to look up the cache for any given top-level
# function or closure. For top-level functions, we are effectively pasting the
# appropriate cache directly into the expression tree at compile time, so its
# super fast. For closures, we have to do the lookup at run-time, so its a
# little bit slower.
@generated function get_cache(f::F, ::Type{D}=IdDict) where {F<:Function, D<:AbstractDict}
    isclosure(F) ? :(_get!($(()->D()), $caches, (f,D))) : _get!(()->D(), caches, (F,D))
end

function empty_cache!(f::F) where {F<:Function}
    map(empty!, [cache for ((f′,_),cache) in caches if (f′ == (isclosure(F) ? f : F))])
end
empty_all_caches!() = map(empty!, values(caches))

"""
    @memoize f(x) = ....
    @memoize Dict f(x) = ....

Memoize a function with respect to all of its arguments and keyword arguments.

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
    sdef[:body] = quote
        ($getter)() = $(sdef[:body])
        $T = $(Core.Compiler.return_type)($getter, $Tuple{})
        $_get!($getter, $get_cache($(sdef[:name]),$(cachetype...)), (($(arg_signature...),),(;$(kwarg_signature...),))) :: $T
    end
    quote
        Core.@__doc__ $(esc(combinedef(sdef)))
        $empty_cache!($(esc(sdef[:name])))
        $(esc(sdef[:name]))
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
