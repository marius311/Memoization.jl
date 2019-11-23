module Memoization

using MacroTools: splitdef, combinedef, splitarg
export @memoize

# Use a generated function to make one memoization cache per unique
# (objectid(function), cache_type) pair. The generated function makes looking up
# the right cache for a target memoized function as fast as possible since it
# will be done at compile time. We also keep track of the caches in a variable
# to allow empty_all_caches!. The reason for using the function objectid instead
# of the function type itself is because the function might be a closure, and in
# this way we can have a separate cache for each instance of the closure (which
# might have different closed over variables). 
@inline get_cache(f::Function, args...) = get_cache(Val(objectid(f)), args...)
@noinline @generated function get_cache(::Val{id}, ::Type{D}=IdDict) where {id,D<:AbstractDict}
    caches[id,D] = d = D()
    d
end
caches = Dict()
empty_cache!(args...) = empty!(get_cache(args...))
empty_all_caches!() = map(empty!,values(caches))

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
        $empty_cache!($(esc(sdef[:name])),$(esc.(cachetype)...))
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
