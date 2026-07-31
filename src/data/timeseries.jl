#############################################################################
# ISP time-series ingestion and attachment
#
# The 2024 ISP "Step Change" demand/solar/wind traces are provided as
# normalised CSV files (see `data/isp/output`). The functions below load
# and normalise the traces, expand the 12 published zones into the
# 15-region SNEM representation and attach them to system components as
# `SingleTimeSeries` scaling factors.
#############################################################################

"""
    normalize_to_range(col, min_val, max_val)

Linearly rescale the values of `col` into the interval
`[min_val, max_val]` (min-max normalisation).
"""
function normalize_to_range(col, min_val, max_val)
    col_min = minimum(col)
    col_max = maximum(col)
    return (col .- col_min) ./ (col_max - col_min) * (max_val - min_val) .+ min_val
end

"""
    normalise_data(df::DataFrame)

Min-max normalise every demand/solar/wind/hydro column of `df` whose name
contains a zone prefix, producing new `*_norm` columns, and return a
DataFrame containing only the `timestamp` and `*_norm` columns.
"""
function normalise_data(df::DataFrame)
    norm_df = copy(df)
    zones = names(norm_df)
    for zn in zones
        zn == "timestamp" && continue
        for n in names(df)
            if occursin(zn, n)
                for kind in ("demand", "Solar", "Wind", "hydro")
                    if occursin(kind, n)
                        norm_df[!, n * "_norm"] = normalize_to_range(df[!, n], 0, 1)
                    end
                end
            end
        end
    end
    return norm_df[!, r"timestamp|norm"]
end

"""
    load_scaled_data(input_fl, res)

Read a pre-scaled ISP trace CSV and expand it to the 15-region model.

`res` is the target resolution in minutes: the bundled CSVs are 30-minute
data, so `res == 60` keeps every 2nd row and `res == 1440` every 48th row;
any other value keeps all rows.

The published VIC and CSA demand traces are copied onto their constituent
sub-regions (WNV/MEL/SEV from VIC, NSA from CSA) so that all
$(N_REGIONS) regions carry a demand trace.
"""
function load_scaled_data(input_fl::AbstractString, res::Integer)
    isfile(input_fl) || throw(ArgumentError(
        "ISP trace file not found: $input_fl. " *
        "Large traces may need to be regenerated with notebooks/pre-processing_ISP_data.ipynb."))
    df = CSV.read(input_fl, DataFrame)
    if res == 60      # keep hourly rows only
        df = df[1:2:size(df)[1], :]
    elseif res == 1440  # keep daily rows only
        df = df[1:48:size(df)[1], :]
    end
    norm_df_15 = copy(df)
    norm_df_15[:, "WNV_demand_norm"] = df[:, "VIC_demand_norm"]
    norm_df_15[:, "MEL_demand_norm"] = df[:, "VIC_demand_norm"]
    norm_df_15[:, "SEV_demand_norm"] = df[:, "VIC_demand_norm"]
    norm_df_15[:, "NSA_demand_norm"] = df[:, "CSA_demand_norm"]
    norm_df_15 = select!(norm_df_15, Not(:VIC_demand_norm))
    @info "Copied normalised data with 15 areas" source = basename(input_fl)
    return norm_df_15
end

"""
    build_time_series(norm_df, res)

Convert every non-`timestamp` column of `norm_df` into a
`SingleTimeSeries` named `"max_active_power"` (scaling factors applied to
each component's max active power). `res` is the series period (e.g.
`Dates.Minute(30)`). Returns a `Dict` keyed by column name.
"""
function build_time_series(norm_df::DataFrame, res)
    time_series_data = Dict()
    dates = minimum(norm_df.timestamp):res:maximum(norm_df.timestamp)
    for nn in names(norm_df)[2:size(norm_df)[2]]
        data = TimeArray(dates, norm_df[!, nn])
        time_series = SingleTimeSeries("max_active_power", data,
            scaling_factor_multiplier = get_max_active_power)
        push!(time_series_data, nn => time_series)
    end
    return time_series_data
end

"""
    get_scenario_data(norm_df, scenario_type)

Optionally restrict `norm_df` to a sub-period. Currently only
`scenario_type == "Typical summer"` (Dec 2024 - Feb 2025) is defined; any
other value returns the frame unchanged. Timestamps given as strings are
parsed to `DateTime`.
"""
function get_scenario_data(norm_df::DataFrame, scenario_type::AbstractString)
    myFormat = Dates.DateFormat(DATE_FORMAT)
    if eltype(norm_df.timestamp) <: AbstractString
        norm_df.timestamp = Dates.DateTime.(norm_df.timestamp, myFormat)
    end
    if scenario_type == "Typical summer"
        start_dt = DateTime(2024, 12, 1, 0, 0, 0)
        end_dt = DateTime(2025, 3, 1, 0, 0, 0)
        norm_df = norm_df[start_dt .<= norm_df.timestamp .< end_dt, :]
    end
    return norm_df
end

"""
    add_renewable_ts!(sys, component, time_series_data, ren_dist_dict=REN_DIST_DICT)

Attach the state-level solar/wind/hydro trace matching `component`'s
prime mover and region to it. Tasmania has no solar trace, so solar
devices in TAS are skipped.
"""
function add_renewable_ts!(sys::System, ll, time_series_data,
        ren_dist_dict::Dict = REN_DIST_DICT)
    area_no = parse(Int, ll.bus.area.name)
    zn = find_region(ren_dist_dict, area_no)
    if ll.prime_mover_type.value == 21      # PrimeMovers.PVe (solar)
        if zn != "TAS"
            PSY.add_time_series!(sys, ll, time_series_data[zn * "_Solar_norm"])
        end
    elseif ll.prime_mover_type.value == 22  # PrimeMovers.WT (wind)
        PSY.add_time_series!(sys, ll, time_series_data[zn * "_Wind_norm"])
    elseif ll.prime_mover_type.value == 16  # PrimeMovers.HY (hydro)
        PSY.add_time_series!(sys, ll, time_series_data[zn * "_hydro_norm"])
    end
    return sys
end

"""
    attach_all_timeseries!(sys, time_series_data)

Attach the loaded traces to all renewable generators, hydro devices and
loads of `sys`. Demand traces are matched by sub-region, renewable traces
by state grouping (see [`REN_DIST_DICT`](@ref)).
"""
function attach_all_timeseries!(sys::System, time_series_data)
    for ll in collect(PSY.get_components(PSY.RenewableGen, sys))
        add_renewable_ts!(sys, ll, time_series_data)
    end
    for ll in collect(PSY.get_components(PSY.HydroEnergyReservoir, sys))
        add_renewable_ts!(sys, ll, time_series_data)
    end
    for ll in collect(PSY.get_components(PSY.HydroDispatch, sys))
        add_renewable_ts!(sys, ll, time_series_data)
    end
    for ll in collect(PSY.get_components(PSY.PowerLoad, sys))
        key = ZONE_DICT[ll.bus.area.name] * "_demand_norm"
        PSY.add_time_series!(sys, ll, time_series_data[key])
    end
    return sys
end

# --- Scenario-specific trace configuration ------------------------------
# file: scaled demand/solar/wind trace CSV inside `isp_dir`
# res: resolution passed to `load_scaled_data` / series period in minutes
# cutoff: exclusive upper bound applied to the hydro trace
const _SCENARIO_TS_CONFIG = Dict(
    "ST" => (file = "2024_ISP_Step_Change_1yr_scaled.csv", res = 30,
             cutoff = DateTime(2025, 7, 1)),
    "MT" => (file = "2024_ISP_Step_Change_6yrs_scaled.csv", res = 30,
             cutoff = DateTime(2030, 7, 1)),
    "LT" => (file = "2024_ISP_Step_Change_20yrs_scaled.csv", res = 60,
             cutoff = DateTime(2044, 7, 1)),
)

"""
    build_scenario_timeseries!(sys, scenario; isp_dir=joinpath(default_data_dir(), "isp", "output"))

Load, normalise and attach the demand/solar/wind/hydro traces for
`scenario` (`"ST"`, `"MT"`, any `"LT*"` variant, or `"SUM_ED"`) to `sys`.

Returns the `Dict` of `SingleTimeSeries` that was attached.

!!! note
    The 20-year LT trace (`2024_ISP_Step_Change_20yrs_scaled.csv`) is too
    large to ship with the repository; regenerate it with
    `notebooks/pre-processing_ISP_data.ipynb` and place it in `isp_dir`.
"""
function build_scenario_timeseries!(sys::System, scenario::AbstractString;
        isp_dir::AbstractString = joinpath(default_data_dir(), "isp", "output"))
    sclass = scenario_class(scenario)
    if sclass == "SUM_ED"
        return _build_summer_ed_timeseries!(sys, isp_dir)
    end

    cfg = _SCENARIO_TS_CONFIG[sclass]
    norm_df = load_scaled_data(joinpath(isp_dir, cfg.file), cfg.res)
    norm_df.timestamp = DateTime.(norm_df.timestamp, DATE_FORMAT)

    hydro_file = joinpath(isp_dir, "2024_ISP_SC_hydro_20yrs.csv")
    isfile(hydro_file) || throw(ArgumentError("Hydro trace file not found: $hydro_file"))
    df = CSV.read(hydro_file, DataFrame)
    df.timestamp = DateTime.(df.timestamp, DATE_FORMAT)
    df = df[df.timestamp .< cfg.cutoff, :]
    hydro_norm_df = normalise_data(df)

    norm_df = innerjoin(norm_df, hydro_norm_df, on = :timestamp)
    norm_df = get_scenario_data(norm_df, "")

    time_series_data = build_time_series(norm_df, Dates.Minute(cfg.res))
    attach_all_timeseries!(sys, time_series_data)
    @info "Time series attached" scenario = sclass resolution_min = cfg.res rows = nrow(norm_df)
    return time_series_data
end

"""
    _build_summer_ed_timeseries!(sys, isp_dir)

SUM_ED variant of [`build_scenario_timeseries!`](@ref): summer extreme
days (daily maxima resampled at a 3-day period) for 2025-2030.
"""
function _build_summer_ed_timeseries!(sys::System, isp_dir::AbstractString)
    input_fl = joinpath(isp_dir, "summer_daily_ED_scaled_2025_2030.csv")
    norm_df = load_scaled_data(input_fl, 4320)  # no downsampling: data is pre-sampled
    norm_df = select(norm_df, Not(:original_daily_timestamp))
    norm_df = select(norm_df, Not(:Summer_Year))

    hydro_file = joinpath(isp_dir, "summer_daily_peak_hydro_2025_2030.csv")
    isfile(hydro_file) || throw(ArgumentError("Hydro trace file not found: $hydro_file"))
    df = CSV.read(hydro_file, DataFrame)
    df = select(df, Not(:original_daily_timestamp))
    df = select(df, Not(:Summer_Year))
    hydro_norm_df = normalise_data(df)

    norm_df = innerjoin(norm_df, hydro_norm_df, on = :timestamp)
    norm_df = get_scenario_data(norm_df, "")

    time_series_data = build_time_series(norm_df, Day(3))
    attach_all_timeseries!(sys, time_series_data)
    @info "Time series attached" scenario = "SUM_ED" rows = nrow(norm_df)
    return time_series_data
end
