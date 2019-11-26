# Memoization.jl

[![Build Status](https://travis-ci.com/marius311/Memoization.jl.svg?branch=master)](https://travis-ci.com/marius311/Memoization.jl)

Easily and efficiently memoize any function in Julia. 

## Usage

```julia

julia> using Memoization

julia> @memoize f(x) = (println("Computed $x"); x)

julia> f(2)
Computed 2
2

julia> f(2)
2
```


## Highlights

* All function definition forms with args and/or kwargs and/or type parameters work.
* Your function remains inferrable.
* Multiple memoized methods for the same function can be defined across different modules (no warnings are generated).
* You can choose the cache type with e.g. `@memoize Dict f(x) = ...`. The default is `IdDict` which memoizes based on the object-id of the arguments.  `Dict` might be useful if you want to memoize based on their values, e.g. so that vectors which contain the same entries count as the same.
* You can clear the cache for a given function at any time with `Memoization.empty_cache!(f)`. Defining new memoized methods for a function will also clear the cache.
* You can also clear all caches for all functions with `Memoization.empty_all_caches!()`.
* You are free to memoize some methods of a function but not others, e.g.:

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
 
* You can memoize closures, e.g.:

    ```julia

    julia> function make_func(x)
               @memoize func(y) = (println("Computed $x,$y"); (x,y))
           end;

    julia> f = make_func(1);

    julia> f(2)
    Computed 1,2
    (1, 2)

    julia> f(2)
    (1, 2)

    julia> g = make_func(2);

    julia> g(2)
    Computed 2,2
    (2, 2)

    julia> g(2)
    (2, 2)

    julia> f(2) # note both f and g memoized separately at this point
    (1, 2)
    ```
    
## Notes

This package can be used as a drop-in replacement for [Memoize.jl](https://github.com/JuliaCollections/Memoize.jl), and, as of this writing, has fewer limitations.

The design is partly inspired by both [Memoize.jl](https://github.com/JuliaCollections/Memoize.jl) and [this](https://stackoverflow.com/a/52084004/1078529) Stack Overflow comment.
