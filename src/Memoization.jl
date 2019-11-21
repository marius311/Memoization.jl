module Memoization

using MacroTools: splitdef, combinedef, splitarg
export @memoize

# use a generated function to make one cache dict per unique (function,
# cache_type) pair
@noinline @generated get_cache(::Function, ::Type{D}=IdDict) where {D<:AbstractDict} = D()

empty_cache!(args...) = empty!(get_cache(args...))

"""
    @memoize f(x) = ....
    @memoize Dict f(x) = ....

Memoize a function with respect to all of its arguments and keyword arguments.

By default, an IdDict is used as a cache. any `AbstractDict` can be used instead
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
        $get!($getter, $get_cache($(sdef[:name]),$(cachetype...)), (($(arg_signature...),),(;$(kwarg_signature...),))) :: $T
    end
    quote
        Core.@__doc__ $(esc(combinedef(sdef)))
        $empty_cache!($(esc(sdef[:name])),$(esc.(cachetype)...))
        $(esc(sdef[:name]))
    end
end

end
