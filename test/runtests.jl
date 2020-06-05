using Memoization
using Test

##

@testset "Memoization" begin
    
    local n
    
    @memoize f(x::T, y=nothing, args... ; z::Union{Int,Nothing}, w=nothing, kwargs...) where {T<:Int} = (n+=1; ((x,y,args...), (;z=z,w=w,kwargs...)))
    
    
    # args
    @test (n=0; f(1,    z=1) == ((1,nothing),(z=1,w=nothing)) && n==1)
    @test (n=0; f(1,    z=1) == ((1,nothing),(z=1,w=nothing)) && n==0)
    
    @test (n=0; f(1,1,  z=1) == ((1,1),      (z=1,w=nothing)) && n==1)
    @test (n=0; f(1,1,  z=1) == ((1,1),      (z=1,w=nothing)) && n==0)
    
    @test (n=0; f(1,1,1,z=1) == ((1,1,1),    (z=1,w=nothing)) && n==1)
    @test (n=0; f(1,1,1,z=1) == ((1,1,1),    (z=1,w=nothing)) && n==0)
    
    # kwargs
    @test (n=0; f(1,z=1,w=1)     == ((1,nothing),(z=1,w=1))     && n==1)
    @test (n=0; f(1,z=1,w=1)     == ((1,nothing),(z=1,w=1))     && n==0)
    
    @test (n=0; f(1,z=1,w=1,p=1) == ((1,nothing),(z=1,w=1,p=1)) && n==1)
    @test (n=0; f(1,z=1,w=1,p=1) == ((1,nothing),(z=1,w=1,p=1)) && n==0)
    
    # cache clear
    Memoization.empty_cache!(f)
    @test (n=0; f(1,z=1) == ((1,nothing),(z=1,w=nothing)) && n==1)
    Memoization.empty_cache!(f)
    @test (n=0; f(1,z=1) == ((1,nothing),(z=1,w=nothing)) && n==1)
    
    # Dict vs. IdDict cache
    @memoize IdDict g(x) = (n+=1; x)
    @test (n=0; g([1,2])==[1,2] && n==1)
    @test (n=0; g([1,2])==[1,2] && n==1)
    @memoize   Dict g(x) = (n+=1; x)
    @test (n=0; g([1,2])==[1,2] && n==1)
    @test (n=0; g([1,2])==[1,2] && n==0)
    
    # redefinition
    # should only clear cache in toplevel, hence @eval
    @eval @memoize h(x) = x
    @test @eval h(2)==2 && h(2)==2
    @eval @memoize h(x) = 2x
    @test @eval h(2)==4 && h(2)==4
    
    # inference
    @test @inferred((@memoize foo(x) = x)(2)) == 2
    # this is broken because @inferred is failing despite @code_warntype giving that its inferred:
    @test_broken @inferred((@memoize foo(;x) = x)(x=2)) == 2
    
    # closures
    function make_func(x)
        @memoize func(y) = (n+=1; (x,y))
    end
    k = make_func(1)
    @test (n=0; k(2)==(1,2) && n==1)
    @test (n=0; k(2)==(1,2) && n==0)
    k′ = make_func(2)
    @test (n=0; k′(2)==(2,2) && n==1)
    @test (n=0; k′(2)==(2,2) && n==0)
    @test (n=0; k(2)==(1,2) && n==0)
    
    # callables
    @eval struct Baz{T} end
    @memoize (::Baz{T})(x::X) where {X, T<:Int} = (n+=1; Int)
    @memoize (::Baz{T})(x::X) where {X, T<:String} = (n+=1; String)
    bazint = Baz{Int}()
    bazstring = Baz{String}()
    @test (n=0; bazint(2)==Int && n==1)
    @test (n=0; bazint(2)==Int && n==0)
    @test (n=0; bazstring(2)==String && n==1)
    @test (n=0; bazstring(2)==String && n==0)
    Memoization.empty_cache!(Baz{Int})
    @test (n=0; bazint(2)==Int && n==1)
    Memoization.empty_cache!(Baz{String})
    @test (n=0; bazstring(2)==String && n==1)
    Memoization.empty_cache!(Baz)
    @test (n=0; bazint(2)==Int && n==1)
    @test (n=0; bazstring(2)==String && n==1)
    
end
