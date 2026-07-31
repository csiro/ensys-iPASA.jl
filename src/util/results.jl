#############################################################################
# PRAS result extraction and persistence
#
# Note on a recurring idiom in this file: `DataFrame(v)` where `v` is a
# vector of `ZonedDateTime` splits the struct fields into columns, so the
# UTC timestamps are recovered via the `"utc_datetime"` column.
#############################################################################

"""
    line_core_matrix(gps)

Return an `n_lines x 4` string matrix with columns
`name, category, region_from, region_to` describing every line of the
PRAS system `gps`.
"""
function line_core_matrix(gps)
    lines_core = Matrix{String}(undef, length(gps.lines), 4)
    lines_core[:, 1] = gps.lines.names
    lines_core[:, 2] = gps.lines.categories
    for (lines, r_from, r_to) in zip(gps.interface_line_idxs,
                                     gps.interfaces.regions_from,
                                     gps.interfaces.regions_to)
        lines_core[lines, 3] .= gps.regions.names[r_from]
        lines_core[lines, 4] .= gps.regions.names[r_to]
    end
    return lines_core
end

"""
    get_pras_lines(gps, sys::System)

Return a `DataFrame` describing every PRAS line (name, type, from/to
area) joined with the power rating of the corresponding AC line or HVDC
line component in `sys`.
"""
function get_pras_lines(gps, sys::System)
    lines_core = line_core_matrix(gps)
    @info "PRAS lines extracted" n_lines = size(lines_core, 1)
    pras_lines_df = DataFrame(lines_core, :auto)
    new_names = Dict(:x1 => :name, :x2 => :ln_type, :x3 => :area_from, :x4 => :area_to)
    DataFrames.rename!(pras_lines_df, new_names)
    rating_dict = Dict()
    for line in pras_lines_df.name
        ln_type = pras_lines_df[pras_lines_df.name .== line, :ln_type][1]
        if occursin("HVDCLine", ln_type)
            ll = get_component(PSY.TwoTerminalHVDCLine, sys, line)
            rating_dict[ll.name] = PSY.get_active_power_limits_from(ll).max
        else
            ll = get_component(PSY.Line, sys, line)
            rating_dict[ll.name] = PSY.get_rating(ll)
        end
    end
    line_pw = DataFrame(String(k) => v for (k, v) in pairs(rating_dict))
    DataFrames.rename!(line_pw, Dict(:first => :name, :second => :power))
    pras_lines_df = leftjoin(pras_lines_df, line_pw, on = [:name]; makeunique = true)
    return pras_lines_df
end

"""
    save_line_capacity(gps, location, scenario)

Write `interface_forward_lines_<scenario>.csv` in `location`, listing
each PRAS interface (from/to region) with its transfer limit, and return
the corresponding `DataFrame`.
"""
function save_line_capacity(gps, location::AbstractString, scenario::AbstractString)
    ints_core = Matrix{String}(undef, length(gps.interfaces), 2)
    ints_core[:, 1] = getindex.(Ref(gps.regions.names), gps.interfaces.regions_from)
    ints_core[:, 2] = getindex.(Ref(gps.regions.names), gps.interfaces.regions_to)
    ints_core = DataFrame(ints_core, ["region_from", "region_to"])

    limits = Matrix{Int64}(undef, length(gps.interfaces), 1)
    limits[:, 1] .= gps.interfaces.limit_backward[:, 1]
    limits = DataFrame(limits, ["forward"])
    ints_core = hcat(ints_core, limits)

    ofile = joinpath(location, "interface_forward_lines_" * scenario * ".csv")
    CSV.write(ofile, ints_core)
    @info "Interface capacities saved" ofile
    return ints_core
end

"""
    flow_utilisation(metrics, timeseries)

Reshape a PRAS interface-indexed result (`Flow` or `Utilization`) into a
`DataFrame` with a `timestamp` column and one column per interface
(named by the `(from, to)` region tuple). `timeseries` is a 1-row matrix
of timestamps (`permutedims(gps.timestamps)`).
"""
function flow_utilisation(metrics, timeseries)
    flow_util = vcat(hcat("timestamp", timeseries),
        hcat(metrics.interfaces, metrics[:, :]))
    flow_util = DataFrame(flow_util, :auto)

    my_matrix = collect(flow_util[!, "x1"][2:end, :])
    header = []
    for kk in my_matrix
        push!(header, (parse(Int, kk[1]), parse(Int, kk[2])))
    end
    index_col = collect(flow_util[1:1, 2:end][1, :])
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]

    xx = flow_util[2:end, :]
    select!(xx, Not("x1"))
    all_columns_data = hcat([vec(xx[!, col]) for col in names(xx)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique = true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

"""
    energy_storage_ts(metrics, timeseries)

Reshape a PRAS storage-energy result into a `DataFrame` with a
`timestamp` column and one column per storage device (mean stored
energy). `timeseries` is a 1-row matrix of timestamps.
"""
function energy_storage_ts(metrics, timeseries)
    flow_util = vcat(hcat("timestamp", timeseries),
        hcat(metrics.storages, metrics.energy_mean))
    flow_util = DataFrame(flow_util, :auto)

    my_matrix = collect(flow_util[!, "x1"][2:end, :])
    header = []
    for kk in my_matrix
        push!(header, kk)
    end
    index_col = collect(flow_util[1:1, 2:end][1, :])
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]

    xx = flow_util[2:end, :]
    select!(xx, Not("x1"))
    all_columns_data = hcat([vec(xx[!, col]) for col in names(xx)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique = true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

"""
    get_dataframe_metrics(met)

Transpose a metric `DataFrame` whose first column holds region names and
first row holds timestamps into a tidy frame with a `timestamp` column
and one column per region.
"""
function get_dataframe_metrics(met)
    my_matrix = collect(met[!, "x1"][2:end, :])
    header = []
    for kk in my_matrix
        push!(header, (parse(Int, kk[1])))
    end
    index_col = collect(met[1:1, 2:end][1, :])
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]
    xx = met[2:end, :]
    select!(xx, Not("x1"))
    all_columns_data = hcat([vec(xx[!, col]) for col in names(xx)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique = true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

"""
    shortfall_metrics(rts, shortfall_rs, timeseries)

Return `(lole_data, eue_data)` DataFrames of per-region LOLE and EUE
metrics for the PRAS system `rts` and shortfall result `shortfall_rs`.
"""
function shortfall_metrics(rts, shortfall_rs, timeseries)
    regionscol = rts.regions.names
    lole = vcat(hcat("timestamp", timeseries),
        hcat(regionscol, LOLE(shortfall_rs, :, :)))
    lole = DataFrame(lole, :auto)
    lole_data = copy(get_dataframe_metrics(lole))

    eue = vcat(hcat("timestamp", timeseries),
        hcat(regionscol, EUE(shortfall_rs, :, :)))
    eue = DataFrame(eue, :auto)
    eue_data = get_dataframe_metrics(eue)

    return lole_data, eue_data
end

"""
    get_interface_result(gps, limit)

Reshape an interface-by-time matrix `limit` (e.g.
`gps.interfaces.limit_forward`) into a `DataFrame` with a `timestamp`
column and one column per interface `(from, to)` tuple.
"""
function get_interface_result(gps, limit)
    my_matrix = DataFrame(limit, :auto)
    interface_col = collect(zip(gps.interfaces.regions_from, gps.interfaces.regions_to))
    header = []
    for kk in interface_col
        push!(header, kk)
    end
    index_col = gps.timestamps
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]
    all_columns_data = hcat([vec(my_matrix[!, col]) for col in names(my_matrix)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique = true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

"""
    get_pras_regional_loads(gps)

Return a `DataFrame` of the regional load series of the PRAS system
`gps` (one column per region, plus `timestamp`).
"""
function get_pras_regional_loads(gps)
    my_matrix = DataFrame(gps.regions.load, :auto)
    header = []
    for kk in gps.regions.names
        push!(header, (parse(Int, kk)))
    end
    index_col = gps.timestamps
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]
    all_columns_data = hcat([vec(my_matrix[!, col]) for col in names(my_matrix)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique = true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

"""
    save_shortfall(shortfall_rs, gps, odir)

Write `pras_shortfall_timeseries.csv` in `odir`: the mean unserved
energy (shortfall) per region and time step.
"""
function save_shortfall(shortfall_rs, gps, odir::AbstractString)
    header = string.(parse.(Int, shortfall_rs.regions.names))
    df = DataFrame(permutedims(shortfall_rs.shortfall_mean), header)
    insertcols!(df, 1, :timestamp => _timestamps_column(gps.timestamps))
    ofile = joinpath(odir, "pras_shortfall_timeseries.csv")
    CSV.write(ofile, df)
    @info "Shortfall time series saved" ofile
    return df
end

"""
    save_shortfall_eue_metrics(gps, shortfall_rs, scenario, odir)

Identify all time steps with loss-of-load (LOLE == 1), compute the
per-region EUE at each of those steps and write the result to
`shortfall_eue.csv` in `odir`. Returns the `DataFrame`.
"""
function save_shortfall_eue_metrics(gps, shortfall_rs, scenario::AbstractString,
        odir::AbstractString)
    lolps = LOLE.(shortfall_rs, gps.timestamps)
    indices = collect(gps.timestamps[findall(val.(lolps) .== 1)])
    eue_matrix = zeros(Float64, length(indices), N_REGIONS)
    region_array = parse.(Int, shortfall_rs.regions.names)
    for (inx, kk) in enumerate(indices)
        for i in region_array
            eue_matrix[inx, i] = val(EUE(shortfall_rs, string(i), kk))
        end
    end
    dd = DataFrame(eue_matrix, string.(collect(1:N_REGIONS)))
    dd[!, :timestamp] = indices
    out_file = joinpath(odir, "shortfall_eue.csv")
    CSV.write(out_file, dd)
    @info "Shortfall EUE metrics saved" out_file events = length(indices)
    return dd
end

"""
    save_shortfall_time_series_data(scenario, shortfall_rs, gps, flow_rs, util_rs, odir)

Write the shortfall, interface flow, interface utilisation and regional
load time series of a PRAS run to CSV files in `odir`.
"""
function save_shortfall_time_series_data(scenario::AbstractString, shortfall_rs,
        gps, flow_rs, util_rs, odir::AbstractString)
    save_shortfall(shortfall_rs, gps, odir)

    timestamprow = permutedims(gps.timestamps)
    utilisation_ts = flow_utilisation(util_rs, timestamprow)
    flow_ts = flow_utilisation(flow_rs, timestamprow)
    CSV.write(joinpath(odir, "pras_flow_timeseries.csv"), flow_ts)
    CSV.write(joinpath(odir, "pras_util_timeseries.csv"), utilisation_ts)
    @info "Flow and utilisation time series saved" odir

    load_df = get_pras_regional_loads(gps)
    CSV.write(joinpath(odir, "pras_regional_loads.csv"), load_df)
    @info "Regional loads saved" odir
    return nothing
end

"""
    save_generator_storage_data(ga, gps, energy, scenario, odir)

Write the per-sample generator availability matrix (`.npy` +
accompanying name list CSV) and the mean storage energy time series to
`odir`.
"""
function save_generator_storage_data(ga, gps, energy, scenario::AbstractString,
        odir::AbstractString)
    npzwrite(joinpath(odir, "gen_available_sample.npy"), ga.available)
    CSV.write(joinpath(odir, "gen_available_sample_info.csv"),
        Tables.table(ga.generators), writeheader = false)
    @info "Generator availability samples saved" odir

    timestamprow = permutedims(gps.timestamps)
    en_df = energy_storage_ts(energy, timestamprow)
    CSV.write(joinpath(odir, "pras_energy_storage_timeseries.csv"), en_df)
    @info "Storage energy time series saved" odir
    return nothing
end

"""
    save_pras_lines_info(gps, sys, odir)

Write the PRAS interface forward/backward limits and the line summary
(with component power ratings from `sys`) to CSV files in `odir`, and
log a summary of the PRAS model dimensions.
"""
function save_pras_lines_info(gps, sys::System, odir::AbstractString)
    mkpath(odir)
    limit_forward = get_interface_result(gps, gps.interfaces.limit_forward)
    CSV.write(joinpath(odir, "pras_interface_lim_for.csv"), limit_forward)
    limit_backward = get_interface_result(gps, gps.interfaces.limit_backward)
    CSV.write(joinpath(odir, "pras_interface_lim_back.csv"), limit_backward)
    @info "Interface limits saved" odir

    pras_lines_df = get_pras_lines(gps, sys)
    CSV.write(joinpath(odir, "pras_lines.csv"), pras_lines_df)

    @info "PRAS model summary" gens = length(gps.generators) interfaces = length(gps.interfaces) battery_storages = length(gps.storages) hydro_storages = length(gps.generatorstorages) regions = length(gps.regions) lines = length(gps.lines)
    return pras_lines_df
end
