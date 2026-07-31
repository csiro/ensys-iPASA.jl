# PRAS integration tests. Reuses TEST_SYS prepared in io.jl (base case,
# ST augmentation and ST time series already applied) and runs a tiny
# sequential Monte Carlo assessment. Production runs use >= 100 samples;
# TEST_SAMPLES (default 2) keeps CI fast.

@testset "PRAS assessment (fast, $(TEST_SAMPLES) samples)" begin
    gps = generate_pras_model(TEST_SYS)

    @testset "PRAS model dimensions" begin
        @test length(gps.regions) == iPASA.N_REGIONS
        @test length(gps.generators) > 0
        @test length(gps.storages) > 0
        @test length(gps.lines) > 0
        @test length(gps.timestamps) > 0
    end

    apply_storage_timeseries!(gps, TEST_SYS)

    @test_throws ArgumentError run_pras_assessment(gps; samples = 0)
    results = run_pras_assessment(gps; samples = TEST_SAMPLES, seed = 123)

    @testset "result structure" begin
        for field in (:shortfall, :surplus, :flow, :utilization, :storage_energy,
                      :gs_energy, :gen_availability, :line_availability,
                      :storage_availability, :gs_availability)
            @test hasproperty(results, field)
        end
        @test results.shortfall.nsamples == TEST_SAMPLES
    end

    @testset "result extraction and persistence" begin
        mktempdir() do odir
            eue_df = save_shortfall_eue_metrics(gps, results.shortfall, "ST", odir)
            @test eue_df isa DataFrame
            @test isfile(joinpath(odir, "shortfall_eue.csv"))

            save_shortfall_time_series_data("ST", results.shortfall, gps,
                results.flow, results.utilization, odir)
            @test isfile(joinpath(odir, "pras_shortfall_timeseries.csv"))
            @test isfile(joinpath(odir, "pras_flow_timeseries.csv"))
            @test isfile(joinpath(odir, "pras_util_timeseries.csv"))
            @test isfile(joinpath(odir, "pras_regional_loads.csv"))

            save_generator_storage_data(results.gen_availability, gps,
                results.storage_energy, "ST", odir)
            @test isfile(joinpath(odir, "gen_available_sample.npy"))
            @test isfile(joinpath(odir, "gen_available_sample_info.csv"))
            @test isfile(joinpath(odir, "pras_energy_storage_timeseries.csv"))

            lines_df = save_pras_lines_info(gps, TEST_SYS, odir)
            @test lines_df isa DataFrame
            @test isfile(joinpath(odir, "pras_lines.csv"))
            @test isfile(joinpath(odir, "pras_interface_lim_for.csv"))
            @test isfile(joinpath(odir, "pras_interface_lim_back.csv"))

            cap_df = save_line_capacity(gps, odir, "ST")
            @test nrow(cap_df) == length(gps.interfaces)

            loads_df = get_pras_regional_loads(gps)
            @test ncol(loads_df) == iPASA.N_REGIONS + 1  # timestamp + regions
            @test nrow(loads_df) == length(gps.timestamps)
        end
    end
end
