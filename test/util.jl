# Unit tests for generic helpers (src/core, src/util).

@testset "core constants and helpers" begin
    @testset "scenario_class" begin
        @test scenario_class("ST") == "ST"
        @test scenario_class("MT") == "MT"
        @test scenario_class("SUM_ED") == "SUM_ED"
        @test scenario_class("LT") == "LT"
        @test scenario_class("LT_BASE") == "LT"
        @test scenario_class("LT_TYP") == "LT"
        @test scenario_class("LT_BEST") == "LT"
        @test scenario_class("LT_WORST") == "LT"
        @test_throws ArgumentError scenario_class("BOGUS")
    end

    @testset "region constants" begin
        @test iPASA.N_REGIONS == 15
        @test length(AREA_CODE_REGION) == 15
        @test AREA_CODE_REGION[15] == "TAS"
        @test sort(vcat(values(REN_DIST_DICT)...)) == collect(1:15)
    end

    @testset "find_region" begin
        @test find_region(REN_DIST_DICT, 1) == "NSW"
        @test find_region(REN_DIST_DICT, 6) == "VIC"
        @test find_region(REN_DIST_DICT, 15) == "TAS"
        @test find_region(REN_DIST_DICT, 99) === nothing
    end

    @testset "stringify_keys" begin
        d = Dict(1 => "a", 2 => Dict(3 => "b"))
        s = stringify_keys(d)
        @test s isa Dict{String, Any}
        @test s["1"] == "a"
        @test s["2"]["3"] == "b"
    end

    @testset "normalize_to_range" begin
        col = [0.0, 5.0, 10.0]
        out = normalize_to_range(col, 0, 1)
        @test out ≈ [0.0, 0.5, 1.0]
        out2 = normalize_to_range(col, -1, 1)
        @test out2 ≈ [-1.0, 0.0, 1.0]
        @test minimum(normalize_to_range(rand(100) .* 42, 0, 1)) ≈ 0.0 atol = 1e-12
    end

    @testset "calculate_gen_rating" begin
        @test iPASA.calculate_gen_rating(3.0, 4.0, 1.0) ≈ 5.0
        @test iPASA.calculate_gen_rating(3.0, 4.0, 2.0) ≈ 10.0
        # zero apparent power falls back to 1.0 to avoid divide-by-zero
        @test iPASA.calculate_gen_rating(0.0, 0.0, 10.0) == 1.0
    end

    @testset "setup_logging" begin
        mktempdir() do dir
            logfile = joinpath(dir, "log", "test.log")
            old_logger = Base.CoreLogging.global_logger()
            try
                setup_logging(logfile; console = false)
                @info "test message"
            finally
                Base.CoreLogging.global_logger(old_logger)
            end
            @test isfile(logfile)
            @test occursin("test message", read(logfile, String))
        end
    end
end
