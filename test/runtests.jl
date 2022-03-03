using Memoization
using Test

@testset "Memoization" begin

    include("funcdef.jl")
    Memoization.empty_all_caches!()
    include("funccall.jl")

end