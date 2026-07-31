# iPASA test suite.
#
# Run with `] test` or `Pkg.test("iPASA")`.
#
# Environment variables:
#   IPASA_TEST_SKIP_SYSTEM=true  skip the slow full-system + PRAS tests
#   IPASA_TEST_SAMPLES=<n>       Monte Carlo samples for the fast
#                                integration test (default 2)

include("common.jl")

@testset "iPASA" begin
    include("util.jl")
    include("timeseries.jl")
    if SKIP_SYSTEM_TESTS
        @info "Skipping system construction and PRAS integration tests (IPASA_TEST_SKIP_SYSTEM=true)"
    else
        include("io.jl")
        include("pras.jl")
    end
end
