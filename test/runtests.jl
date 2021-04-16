using Memoization
using Test


##

@testset "Memoization" begin

global n = 0

@eval @memoize f(x::T, y=nothing, args... ; z::Union{Int,Nothing}, w=nothing, kwargs...) where {T<:Int} = (global n+=1; ((x,y,args...), (;z=z,w=w,kwargs...)))

# args
n=0; @test (f(1,    z=1) == ((1,nothing),(z=1,w=nothing)) && n==1)
n=0; @test (f(1,    z=1) == ((1,nothing),(z=1,w=nothing)) && n==0)

n=0; @test (f(1,1,  z=1) == ((1,1),      (z=1,w=nothing)) && n==1)
n=0; @test (f(1,1,  z=1) == ((1,1),      (z=1,w=nothing)) && n==0)

n=0; @test (f(1,1,1,z=1) == ((1,1,1),    (z=1,w=nothing)) && n==1)
n=0; @test (f(1,1,1,z=1) == ((1,1,1),    (z=1,w=nothing)) && n==0)

# kwargs
n=0; @test (f(1,z=1,w=1)     == ((1,nothing),(z=1,w=1))     && n==1)
n=0; @test (f(1,z=1,w=1)     == ((1,nothing),(z=1,w=1))     && n==0)

n=0; @test (f(1,z=1,w=1,p=1) == ((1,nothing),(z=1,w=1,p=1)) && n==1)
n=0; @test (f(1,z=1,w=1,p=1) == ((1,nothing),(z=1,w=1,p=1)) && n==0)

# cache clear
Memoization.empty_cache!(f)
n=0; @test (f(1,z=1) == ((1,nothing),(z=1,w=nothing)) && n==1)
Memoization.empty_cache!(f)
n=0; @test (f(1,z=1) == ((1,nothing),(z=1,w=nothing)) && n==1)

# Dict vs. IdDict cache vs. custom cache
@eval @memoize IdDict g1(x) = (global n+=1; x)
n=0; @test (g1([1,2])==[1,2] && n==1)
n=0; @test (g1([1,2])==[1,2] && n==1)
@eval @memoize   Dict g2(x) = (global n+=1; x)
n=0; @test (g2([1,2])==[1,2] && n==1)
n=0; @test (g2([1,2])==[1,2] && n==0)
@eval @memoize Dict() g3(x) = (global n+=1; x)
n=0; @test (g3([1,2])==[1,2] && n==1)
n=0; @test (g3([1,2])==[1,2] && n==0)

# redefinition
# should only clear cache in toplevel, hence @eval
@eval @memoize h(x) = x
@test h(2)==2 && h(2)==2
@eval @memoize h(x) = 2x
@test h(2)==4 && h(2)==4

# inference
@eval @memoize foo(x) = x
@eval @memoize foo(;x) = x
@test @inferred(foo(2)) == 2
@test @inferred(foo(x=2)) == 2

# closures
function make_func(x)
    @memoize func(y) = (global n+=1; (x,y))
end
k = make_func(1)
n=0; @test (k(2)==(1,2) && n==1)
n=0; @test (k(2)==(1,2) && n==0)
k′ = make_func(2)
n=0; @test (k′(2)==(2,2) && n==1)
n=0; @test (k′(2)==(2,2) && n==0)
n=0; @test (k(2)==(1,2) && n==0)

# callables
@eval struct Baz{T} end
@eval @memoize (::Baz{T})(x::X) where {X, T<:Int} = (global n+=1; Int)
@eval @memoize (::Baz{T})(x::X) where {X, T<:String} = (global n+=1; String)
bazint = Baz{Int}()
bazstring = Baz{String}()
n=0; @test (bazint(2)==Int && n==1)
n=0; @test (bazint(2)==Int && n==0)
n=0; @test (bazstring(2)==String && n==1)
n=0; @test (bazstring(2)==String && n==0)
Memoization.empty_cache!(Baz{Int})
n=0; @test (bazint(2)==Int && n==1)
Memoization.empty_cache!(Baz{String})
n=0; @test (bazstring(2)==String && n==1)
Memoization.empty_cache!(Baz)
n=0; @test (bazint(2)==Int && n==1)
n=0; @test (bazstring(2)==String && n==1)

# unnamed args
@eval @memoize uarg(::Type{T}) where {T} = (global n+=1; T)
n=0; @test (uarg(Int)==Int && n==1)
n=0; @test (uarg(Int)==Int && n==0)
n=0; @test (uarg(Float64)==Float64 && n==1)
n=0; @test (uarg(Float64)==Float64 && n==0)

# redefining cache type
@eval @memoize IdDict redef_cache_toplevel(x) = x
@test_throws Exception @eval @memoize Dict redef_cache_toplevel(x) = x

end