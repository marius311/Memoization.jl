
@testset "Callsite" begin

global n = 0

@eval f(x::T, y=nothing, args... ; z::Union{Int,Nothing}, w=nothing, kwargs...) where {T<:Int} = (global n+=1; ((x,y,args...), (;z=z,w=w,kwargs...)))

# args
n=0; @test (@memoize(f(1,    z=1)) == ((1,nothing),(z=1,w=nothing)) && n==1)
n=0; @test (@memoize(f(1,    z=1)) == ((1,nothing),(z=1,w=nothing)) && n==0)

n=0; @test (@memoize(f(1,1,  z=1)) == ((1,1),      (z=1,w=nothing)) && n==1)
n=0; @test (@memoize(f(1,1,  z=1)) == ((1,1),      (z=1,w=nothing)) && n==0)

n=0; @test (@memoize(f(1,1,1,z=1)) == ((1,1,1),    (z=1,w=nothing)) && n==1)
n=0; @test (@memoize(f(1,1,1,z=1)) == ((1,1,1),    (z=1,w=nothing)) && n==0)

# kwargs
n=0; @test (@memoize(f(1,z=1,w=1))     == ((1,nothing),(z=1,w=1))     && n==1)
n=0; @test (@memoize(f(1,z=1,w=1))     == ((1,nothing),(z=1,w=1))     && n==0)

n=0; @test (@memoize(f(1,z=1,w=1,p=1)) == ((1,nothing),(z=1,w=1,p=1)) && n==1)
n=0; @test (@memoize(f(1,z=1,w=1,p=1)) == ((1,nothing),(z=1,w=1,p=1)) && n==0)


# cache clear
Memoization.empty_cache!(f)
n=0; @test (@memoize(f(1,z=1)) == ((1,nothing),(z=1,w=nothing)) && n==1)
Memoization.empty_cache!(f)
n=0; @test (@memoize(f(1,z=1)) == ((1,nothing),(z=1,w=nothing)) && n==1)

# Dict vs. IdDict cache vs. custom cache
@eval g1(x) = (global n+=1; x)
n=0; @test (@memoize(IdDict,g1([1,2]))==[1,2] && n==1)
n=0; @test (@memoize(IdDict,g1([1,2]))==[1,2] && n==1)
@eval g2(x) = (global n+=1; x)
n=0; @test (@memoize(Dict,g2([1,2]))==[1,2] && n==1)
n=0; @test (@memoize(Dict,g2([1,2]))==[1,2] && n==0)
@eval g3(x) = (global n+=1; x)
n=0; @test (@memoize(Dict(),g3([1,2]))==[1,2] && n==1)
n=0; @test (@memoize(Dict(),g3([1,2]))==[1,2] && n==0)

# redefinition
# i think we could probably fix this in the future with some fancy
# backedge thing
@eval h(x) = x
@test @memoize(h(2))==2 && @memoize(h(2))==2
@eval h(x) = 2x
@test_broken @memoize(h(2))==4 && @memoize(h(2))==4

# inference
@eval foo(x) = x
@eval foo(;x) = x
@test @inferred((()->@memoize(foo(2)))()) == 2
@test @inferred((()->@memoize(foo(x=2)))()) == 2

# closures
function make_func(x)
    func(y) = (global n+=1; (x,y))
end
k = make_func(1)
n=0; @test (@memoize(k(2))==(1,2) && n==1)
n=0; @test (@memoize(k(2))==(1,2) && n==0)
k′ = make_func(2)
n=0; @test (@memoize(k′(2))==(2,2) && n==1)
n=0; @test (@memoize(k′(2))==(2,2) && n==0)
n=0; @test (@memoize(k(2))==(1,2) && n==0)

end