@testset "Revise compatibility" begin

if VERSION < v"1.12"
    @info "Skipping Revise test on Julia < 1.12"
else

using Pkg

# Create a multi-file temp package that uses @memoize
tmpdir = mktempdir()
pkg_dir = joinpath(tmpdir, "RevTestPkg")
src_dir = joinpath(pkg_dir, "src")
mkpath(src_dir)

write(joinpath(pkg_dir, "Project.toml"), """
name = "RevTestPkg"
uuid = "a1b2c3d4-1234-4321-abcd-000000000002"
version = "0.1.0"

[deps]
Memoization = "6fafb56a-5788-4b4e-91ca-c0cea6611c73"
""")

main_file = joinpath(src_dir, "RevTestPkg.jl")
write(main_file, """
module RevTestPkg
using Memoization: @memoize

struct Foo{T}
    x::Vector{T}
    n::Int
end

@memoize f(x::Float64) = x^2
@memoize g(n::Int) = ones(n, n)

include("utils.jl")
end
""")

utils_file = joinpath(src_dir, "utils.jl")
write(utils_file, """
function h(x::Vector{Float64})
    foo = Foo(x, length(x))
    return sum(g(foo.n)) + f(Float64(foo.n))
end
""")

env_dir = joinpath(tmpdir, "env")
mkpath(env_dir)
memoization_dir = dirname(@__DIR__)

test_script = joinpath(tmpdir, "run_test.jl")
write(test_script, """
using Revise
using RevTestPkg

# Verify initial behavior
@assert RevTestPkg.h([1.0, 2.0, 3.0]) == 18.0
@assert RevTestPkg.f(3.0) == 9.0
@assert sum(RevTestPkg.g(2)) == 4.0

failed = false

# Test 1: Change function body in included file
utils_file = "$(escape_string(utils_file))"
write(utils_file, \"\"\"
function h(x::Vector{Float64})
    foo = Foo(x, length(x))
    return sum(g(foo.n)) + f(Float64(foo.n)) + 1000.0
end
\"\"\")
sleep(1)  # let the file watcher see the change
Revise.revise()

try
    result = RevTestPkg.h([1.0, 2.0, 3.0])
    if result != 1018.0
        println(stderr, "FAIL test1: h = \$result, expected 1018.0")
        global failed = true
    end
catch e
    println(stderr, "ERROR test1: ", sprint(showerror, e))
    global failed = true
end

# Test 2: Change memoized function body + struct redefinition
main_file = "$(escape_string(main_file))"
write(main_file, \"\"\"
module RevTestPkg
using Memoization: @memoize

struct Foo{T}
    x::Vector{T}
    n::Int
    y::Symbol  # new field
end

@memoize f(x::Float64) = x^2 + 1.0
@memoize g(n::Int) = ones(n, n)

include("utils.jl")
end
\"\"\")
# Also update utils.jl for the new struct layout
write(utils_file, \"\"\"
function h(x::Vector{Float64})
    foo = Foo(x, length(x), :y)
    return sum(g(foo.n)) + f(Float64(foo.n))
end
\"\"\")
sleep(1)  # let the file watcher see the change
Revise.revise()

# Memoized functions (don't take struct) should still work
try
    result = RevTestPkg.f(3.0)
    if result != 10.0
        println(stderr, "FAIL test2: f = \$result, expected 10.0")
        global failed = true
    end
catch e
    println(stderr, "ERROR test2 f: ", sprint(showerror, e))
    global failed = true
end

try
    result = sum(RevTestPkg.g(2))
    if result != 4.0
        println(stderr, "FAIL test2: g = \$result, expected 4.0")
        global failed = true
    end
catch e
    println(stderr, "ERROR test2 g: ", sprint(showerror, e))
    global failed = true
end

# h constructs the struct internally and calls memoized functions
try
    result = RevTestPkg.h([1.0, 2.0, 3.0])
    # sum(g(3)) = 9, f(3.0) = 10.0, total = 19.0
    if result != 19.0
        println(stderr, "FAIL test2: h = \$result, expected 19.0")
        global failed = true
    end
catch e
    println(stderr, "ERROR test2 h: ", sprint(showerror, e))
    global failed = true
end

exit(failed ? 1 : 0)
""")

# Set up the environment
setup_proc = run(ignorestatus(`julia --startup-file=no --project=$env_dir -e "
    using Pkg
    Pkg.develop(PackageSpec(path=\"$memoization_dir\"))
    Pkg.develop(PackageSpec(path=\"$pkg_dir\"))
    Pkg.add([\"Revise\", \"Preferences\"])
    using Preferences
    set_preferences!(\"Revise\", \"revise_structs\" => true; force=true)
    Pkg.precompile()
"`))
@test success(setup_proc)

if success(setup_proc)
    proc = run(ignorestatus(`julia --startup-file=no --project=$env_dir --depwarn=error $test_script`))
    @test success(proc)
end

end # VERSION check

end
