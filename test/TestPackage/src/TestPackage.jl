module TestPackage
using Memoization: @memoize
@memoize foo(x) = x
@memoize foo(x,y) = nothing
foo(1)
end
