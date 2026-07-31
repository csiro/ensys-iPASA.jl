# Unit tests for ISP time-series ingestion (src/data/timeseries.jl).

@testset "time series utilities" begin
    @testset "normalise_data" begin
        df = synthetic_norm_df()
        out = normalise_data(df)
        @test "timestamp" in names(out)
        @test "NSW_demand_norm" in names(out)
        @test "NSW_Solar_norm" in names(out)
        @test "NSW_Wind_norm" in names(out)
        @test "NSW_hydro_norm" in names(out)
        # only timestamp + *_norm columns survive
        @test all(n -> n == "timestamp" || endswith(n, "_norm"), names(out))
        @test minimum(out.NSW_demand_norm) ≈ 0.0 atol = 1e-12
        @test maximum(out.NSW_demand_norm) ≈ 1.0 atol = 1e-12
    end

    @testset "get_scenario_data" begin
        df = synthetic_norm_df()
        # empty scenario type returns the frame unchanged
        out = iPASA.get_scenario_data(copy(df), "")
        @test nrow(out) == nrow(df)
        # string timestamps are parsed to DateTime
        df2 = copy(df)
        df2.timestamp = Dates.format.(df2.timestamp, "yyyy-mm-dd HH:MM:SS")
        out2 = iPASA.get_scenario_data(df2, "")
        @test eltype(out2.timestamp) == DateTime
    end

    @testset "load_scaled_data" begin
        mktempdir() do dir
            n = 96  # two days of 30-minute data
            timestamps = collect(DateTime(2024, 7, 1):Minute(30):(DateTime(2024, 7, 1) + Minute(30) * (n - 1)))
            df = DataFrame(timestamp = Dates.format.(timestamps, "yyyy-mm-dd HH:MM:SS"))
            for zone in ["CNSW", "CQ", "CSA", "GG", "NNSW", "NQ", "SESA", "SNSW", "SNW", "SQ", "TAS", "VIC"]
                df[!, "$(zone)_demand_norm"] = rand(n)
            end
            fl = joinpath(dir, "trace.csv")
            CSV.write(fl, df)

            # res = 30: all rows kept, VIC expanded to WNV/MEL/SEV, CSA to NSA
            out = load_scaled_data(fl, 30)
            @test nrow(out) == n
            for col in ["WNV_demand_norm", "MEL_demand_norm", "SEV_demand_norm", "NSA_demand_norm"]
                @test col in names(out)
            end
            @test !("VIC_demand_norm" in names(out))
            @test out.WNV_demand_norm == df.VIC_demand_norm
            @test out.NSA_demand_norm == df.CSA_demand_norm

            # res = 60: every 2nd row; res = 1440: every 48th row
            @test nrow(load_scaled_data(fl, 60)) == n ÷ 2
            @test nrow(load_scaled_data(fl, 1440)) == n ÷ 48

            @test_throws ArgumentError load_scaled_data(joinpath(dir, "missing.csv"), 30)
        end
    end

    @testset "build_time_series" begin
        df = normalise_data(synthetic_norm_df())
        ts_dict = build_time_series(df, Minute(30))
        @test length(ts_dict) == ncol(df) - 1
        @test haskey(ts_dict, "NSW_demand_norm")
        ts = ts_dict["NSW_demand_norm"]
        @test ts isa PSY.SingleTimeSeries
        @test PSY.get_name(ts) == "max_active_power"
        @test length(ts.data) == nrow(df)
    end

    @testset "bundled ISP traces present" begin
        @test isfile(joinpath(ISP_DIR, "2024_ISP_Step_Change_1yr_scaled.csv"))
        @test isfile(joinpath(ISP_DIR, "2024_ISP_Step_Change_6yrs_scaled.csv"))
        @test isfile(joinpath(ISP_DIR, "2024_ISP_SC_hydro_20yrs.csv"))
        @test isfile(joinpath(ISP_DIR, "summer_daily_ED_scaled_2025_2030.csv"))
        @test isfile(joinpath(ISP_DIR, "summer_daily_peak_hydro_2025_2030.csv"))
    end
end
