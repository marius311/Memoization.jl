module TestPackage
using Memoization
@memoize foo(x) = x
foo(1)
end
