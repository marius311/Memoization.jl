using Memoization
using Test
using Pkg

@testset "Memoization" begin

    include("funcdef.jl")
    Memoization.empty_all_caches!()
    include("funccall.jl")

end