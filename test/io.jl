# System-construction tests (src/io). These parse the bundled 2000-bus
# SNEM case, so they take a few minutes on first run.

@testset "system construction" begin
    @test isfile(BASE_CASE)
    @test_throws ArgumentError build_system(joinpath(SC_DIR, "no_such_case.m"))

    global TEST_SYS, TEST_PM_DATA, TEST_STORAGE_DATA =
        build_system(BASE_CASE)

    @testset "component inventory" begin
        @test TEST_SYS isa PSY.System
        @test length(PSY.get_components(PSY.ACBus, TEST_SYS)) > 0
        @test length(PSY.get_components(PSY.PowerLoad, TEST_SYS)) > 0
        @test length(PSY.get_components(PSY.ThermalStandard, TEST_SYS)) > 0
        @test length(PSY.get_components(PSY.RenewableDispatch, TEST_SYS)) > 0
        # storage table was re-attached from the MATPOWER data
        @test length(PSY.get_components(PSY.EnergyReservoirStorage, TEST_SYS)) > 0
        # 15 areas in the clustered SNEM representation
        @test length(PSY.get_components(PSY.Area, TEST_SYS)) == iPASA.N_REGIONS
    end

    @testset "augmentation (ST scenario)" begin
        n_gen_before = length(PSY.get_components(PSY.ThermalStandard, TEST_SYS)) +
                       length(PSY.get_components(PSY.RenewableDispatch, TEST_SYS)) +
                       length(PSY.get_components(PSY.HydroDispatch, TEST_SYS))
        n_stg_before = length(PSY.get_components(PSY.EnergyReservoirStorage, TEST_SYS))

        add_baseload!(TEST_SYS, SC_DIR)
        add_future_generators!(TEST_SYS, "ST", SC_DIR)
        add_future_storage!(TEST_SYS, "ST", SC_DIR)

        n_gen_after = length(PSY.get_components(PSY.ThermalStandard, TEST_SYS)) +
                      length(PSY.get_components(PSY.RenewableDispatch, TEST_SYS)) +
                      length(PSY.get_components(PSY.HydroDispatch, TEST_SYS))
        n_stg_after = length(PSY.get_components(PSY.EnergyReservoirStorage, TEST_SYS))
        @test n_gen_after >= n_gen_before
        @test n_stg_after > n_stg_before

        add_retirement_status!(TEST_SYS, "ST",
            joinpath(SC_DIR, "future_gen_thermal_exp_pp.csv"), "gen")
        add_retirement_status!(TEST_SYS, "ST",
            joinpath(SC_DIR, "future_storage_pp.csv"), "storage")
        @test_throws ArgumentError add_retirement_status!(TEST_SYS, "ST",
            joinpath(SC_DIR, "future_storage_pp.csv"), "bogus_kind")
    end

    @testset "scenario time series attachment (ST)" begin
        ts_dict = build_scenario_timeseries!(TEST_SYS, "ST"; isp_dir = ISP_DIR)
        @test haskey(ts_dict, "NNSW_demand_norm")
        @test haskey(ts_dict, "NSW_Solar_norm")
        # every load now carries a max_active_power series
        a_load = first(PSY.get_components(PSY.PowerLoad, TEST_SYS))
        @test PSY.has_time_series(a_load)
    end

    @testset "default_case_file" begin
        @test iPASA.default_case_file("LT_BASE") == BASE_CASE
        # missing variant cases fall back to the base case with a warning
        @test iPASA.default_case_file("LT_TYP") == BASE_CASE ||
              isfile(iPASA.default_case_file("LT_TYP"))
    end

    @testset "system info export" begin
        info_df = iPASA.get_load_gen_info(TEST_SYS)
        @test nrow(info_df) > 0
        @test "comp_type" in names(info_df)
        bus_df = iPASA.collect_bus_info(TEST_SYS)
        @test nrow(bus_df) == length(PSY.get_components(PSY.ACBus, TEST_SYS))
        line_df = iPASA.collect_line_info(TEST_SYS)
        @test nrow(line_df) > 0
    end
end
