# Memoization.jl

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
* Multiple memoized methods for the same function can be defined across different modules (no warning are generated).
* You are free to memoize some methods of a function but not others. E.g.

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

 
* The default cache is an `IdDict` which memoizes based on the object-id of the arguments. If you want to memoize based on their values, e.g. so that vectors which contain the same entries count as the same, you can use a `Dict` as a cache. This can be specified via `@memoize Dict f(x) = ...`
* You can clear the cache at any time with `Memoization.empty_cache!(f)` (if you used a non-default cache type, you should do `Memoization.empty_cache!(f,Dict)` where `Dict` is replaced with whatever cache type you used).
