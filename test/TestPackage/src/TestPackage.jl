module TestPackage
using Memoization: @memoize
@memoize foo(x) = x
foo(1)
end
