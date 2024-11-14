# Memoization.jl

[![](https://github.com/marius311/Memoization.jl/workflows/runtests/badge.svg)](https://github.com/marius311/Memoization.jl/actions?query=workflow%3Aruntests+branch%3Amaster) 

Easily and efficiently memoize any function call, function, closure, or callable object in Julia.

## Example Usage

```julia

julia> using Memoization

julia> @memoize f(x) = (println("Computed $x"); x) # memoize a function

julia> f(2)
Computed 2
2

julia> f(2)
2

julia> g(x) = (println("Computed $x"); x)

julia> @memoize g(2) # memoize a single function call
Computed 2
2

julia> @memoize g(2)
2
```


## Highlights

* You can `@memoize` a function definition, in which case every call to that function will be memoized, or you can `@memoize` a single function-call to any Julia function, in which case only that call is memoized. 

    Note that memoized function-calls can be slightly less performant and may give incorrect results if the function is redefined, see limitations below. Functions memoized at their definition are optimally performant and will always give the right result even if some methods are redefined.

* All function definition or function call forms with args and/or kwargs and/or type parameters work.

* The function or function call remains inferrable.

* You can choose the cache type, e.g.,

    ```julia
    @memoize Dict f(x) = ...
    @memoize LRU(maxsize=5) f(x) = ...      # using https://github.com/JuliaCollections/LRUCache.jl
    ```

    The specifier should be a type which can be called without arguments to create the cache, or an expression which creates an instance of a cache (note: cache creation is delayed until the first time a function is called, so it is not possible to pass a pre-instantiated cache). 
    
    The default cache type is `IdDict` which 
    counts arguments the same if they `===` each other. Another common choice is `Dict` which memoizes based on if they `==` each other (this is probably useful if you want to count e.g. vectors which contain the same entries as the same, but will lead to somewhat slower cache lookup).
    
* You can clear the cache for a given function at any time with `Memoization.empty_cache!(f)`.

* You can also clear all caches for all functions with `Memoization.empty_all_caches!()`.

* You can call memoized functions during precompilation. The memoized results are then stored in the precompiled module and will not be recomputed at runtime. Note, however, if memoized results are not serializable (e.g. Channels or FFT plans or you just don't want them saved), you should manually call `empty_cache!` at the end of precompilation, e.g. in the top-level of your module or at the end of your `SnoopPrecompile.@precompile_all_calls` block.

Additionally, for memoized function definitions:

* Multiple memoized methods for the same function can be defined across different modules.

* You can memoize some methods of a function but not others, e.g.:

    ```julia
    julia> @memoize f(x) = (println("Computed $x"); x)
    f (generic function with 1 method)

    julia> f(x,y) = (println("Computed $x,$y"); f(x+y))
    f (generic function with 2 methods)

    julia> f(1,2)
    Computed 1,2
    Computed 3
    3

    julia> f(1,2)
    Computed 1,2
    3

    julia> f(1,2)
    Computed 1,2
    3
    ```
 
* You can memoize individual instances of closures, e.g.:

    ```julia

    julia> function make_func(x)
               @memoize func(y) = (println("Computed $x,$y"); (x,y))
           end;

    julia> f = make_func(1);

    julia> f(3)
    Computed 1,3
    (1, 3)

    julia> f(3)
    (1, 3)

    julia> g = make_func(2);

    julia> g(3)
    Computed 2,3
    (2, 3)

    julia> g(3)
    (2, 3)

    julia> f(3) # note both f and g memoized separately at this point
    (1, 3)
    ```

* You can memoize individual instances of "callables", e.g.,

    ```julia
    julia> struct Foo
               x
           end
    
    julia> @memoize (f::Foo)(x) = (println("Computed $(f.x), $x"); (f.x, x))
    
    julia> foo1 = Foo(1);
    
    julia> foo1(3)
    Computed 1,3
    (1,3)
    
    julia> foo1(3)
    (1,3)
    
    julia> foo2 = Foo(2);
    
    julia> foo2(3)
    Computed 2,3
    (2,3)
    
    julia> foo2(3)
    (2,3)

    julia> foo1(3) # note both foo1 and foo2 memoized separately at this point
    (1,3)
    ```

## Limitations

* Memoized function-calls can become out-of-date if the function is redefined, e.g.:

    ```julia
    f(x) = x
    @memoize f(2)
    f(x) = x^2
    @memoize f(2) # incorrectly returns 2, not 4
    ```

    To fix this, manually call `Memoization.empty_cache!(f)` after redefining the function. Function memoized at their definition do not suffer from this problem.

* You cannot switch the cache type within the same session. E.g. you cannot do `@memoize Dict foo() = ...` and then later `@memoize IdDict foo() = ...`. You must restart your Julia session for this.  

* This package is not thread-safe with either `Dict` or `IdDict`. However, if a thread-safe cache is used (e.g. [ThreadSafeDicts.jl](https://github.com/wherrera10/ThreadSafeDicts.jl)), then memoizing top-level functions is thread-safe. Memoizing closures and callables is not yet thread-safe with any cache type. 

## Notes

This package can be used as a drop-in replacement for [Memoize.jl](https://github.com/JuliaCollections/Memoize.jl), and, as of this writing, has fewer limitations.

The design is partly inspired by both [Memoize.jl](https://github.com/JuliaCollections/Memoize.jl) and [this](https://stackoverflow.com/a/52084004/1078529) Stack Overflow comment.
