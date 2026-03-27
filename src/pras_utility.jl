using NPZ

function energy_storage_ts(metrics, timeseries)
    flow_util = vcat(hcat("timestamp", timeseries),
         hcat(metrics.storages, metrics.energy_mean))
    flow_util = DataFrame(flow_util, :auto)

    my_matrix = collect(flow_util[!, "x1"][2:end, :])
    header = []
    for kk in my_matrix
        push!(header, kk)
    end
    index_col = collect(flow_util[1:1, 2:end][1,:])
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]

    xx = flow_util[2:end, :]
    select!(xx, Not("x1")) 
    all_columns_data = hcat([vec(xx[!, col]) for col in names(xx)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique=true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

function save_generator_storage_data(ga, gps, energy, scenario, odir)
# Save the matrix to an .npy file
    ofile = joinpath(odir, "gen_available_sample.npy")
    npzwrite(ofile, ga.available)
    ofile = joinpath(odir, "gen_available_sample_info.csv")
    CSV.write(ofile, Tables.table(ga.generators), writeheader=false)
    println("pras metrics data saved")

    timestamps = gps.timestamps
    timestamprow = permutedims(timestamps)
    en_df = energy_storage_ts(energy, timestamprow)
    ofile = joinpath(odir, "pras_energy_storage_timeseries.csv")
    CSV.write(ofile, en_df)
    println("Saved energy data")
end


function save_shortfall_time_series_data(scenario, shortfall_rs, gps, flow_rs, util_rs, odir)
    saveshortfall(shortfall_rs, gps, odir)
    println("Saved shortfall data")
    timestamps = gps.timestamps
    timestamprow_5 = permutedims(timestamps)
    utilisation_ts =  flow_utilisation(util_rs, timestamprow_5 )
    flow_ts =  flow_utilisation(flow_rs, timestamprow_5 )
    println("pras time series metrics calculated")
    ofile = joinpath(odir, "pras_flow_timeseries.csv")
    CSV.write(ofile, flow_ts)
    ofile = joinpath(odir, "pras_util_timeseries.csv")
    CSV.write(ofile, utilisation_ts)
    println("Saved PRAS time series metrics data")
    load_df = get_pras_regional_loads(gps)
    ofile = joinpath(pwd(), odir, "pras_regional_loads.csv")
    CSV.write(ofile, load_df)
    println("pras regional loads calculated")
end

function save_shortfall_eue_metrics(gps, shortfall_rs, scenario, odir)
    lolps = LOLE.(shortfall_rs, gps.timestamps)
    indices = collect(gps.timestamps[findall(val.(lolps).==1)])
    use = AbstractFloat[]
    eue_matrix = zeros(Float64,  length(indices), 15)
    region_array = parse.(Int, shortfall_rs.regions.names)
    for (inx, kk) in enumerate(indices)
        for i in region_array
        #push!(region_list, i)
            eue_matrix[inx,i,:] .= val.(EUE.(shortfall_rs, string(i), kk))
        end   
    end
    symbol_names = string.(collect(1:15))
    dd = DataFrame(eue_matrix, symbol_names)
#dd = DataFrame(eue_matrix, :auto)
    dd[!,:timestamp] = indices
    out_file = joinpath(odir, "shortfall_eue.csv")
    CSV.write(out_file, dd)
#df = DataFrame(timestamp = indices, EUE = use)
#plot(df, x=:timestamp, y=:use)
    println("done") 
    return dd
end

function flow_utilisation(metrics, timeseries)
    flow_util = vcat(hcat("timestamp", timeseries),
         hcat(metrics.interfaces, metrics[:, :]))
    flow_util = DataFrame(flow_util, :auto)

    my_matrix = collect(flow_util[!, "x1"][2:end, :])
    header = []
    for kk in my_matrix
        push!(header, (parse(Int, kk[1]), parse(Int, kk[2])))
    end
    index_col = collect(flow_util[1:1, 2:end][1,:])
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]

    xx = flow_util[2:end, :]
    select!(xx, Not("x1")) 
    all_columns_data = hcat([vec(xx[!, col]) for col in names(xx)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique=true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

function get_dataframe_metrics(met)
    my_matrix = collect(met[!, "x1"][2:end, :])
    header = []
    for kk in my_matrix
        push!(header, (parse(Int, kk[1])))
    end
    index_col = collect(met[1:1, 2:end][1,:])
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]
    xx = met[2:end, :]
    select!(xx, Not("x1")) 
    all_columns_data = hcat([vec(xx[!, col]) for col in names(xx)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique=true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

function shortfall_metrics(rts, shortfall_rs, timeseries)
    regionscol = rts.regions.names
    lole = vcat(hcat("timestamp", timeseries),
         hcat(regionscol, LOLE(shortfall_rs, :, :)))
    lole = DataFrame(lole, :auto)
    
    lole_data = copy(get_dataframe_metrics(lole))
    eue = vcat(hcat("timestamp", timeseries),
         hcat(regionscol, EUE(shortfall_rs, :, :)))
    eue = DataFrame(lole, :auto)
    eue_data = get_dataframe_metrics(eue)

    return lole_data, eue_data
end

function get_interface_result(gps, limit)
    my_matrix = DataFrame(limit, :auto)
    interface_col = collect(zip(gps.interfaces.regions_from,
        gps.interfaces.regions_to))
    header = []
    for kk in interface_col
        push!(header, kk)
    end
    #header = interface_col
    index_col = gps.timestamps
    time_inx = DataFrame(index_col)
    time_inx = time_inx[!, "utc_datetime"]
    all_columns_data = hcat([vec(my_matrix[!, col]) for col in names(my_matrix)]...)
    all_columns_data = DataFrame(all_columns_data, :auto)
    all_columns_data = permutedims(all_columns_data)
    DataFrames.rename!(all_columns_data, Symbol.(header))
    all_columns_data = hcat(time_inx, all_columns_data, makeunique=true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end

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
    all_columns_data = hcat(time_inx, all_columns_data, makeunique=true)
    DataFrames.rename!(all_columns_data, :x1 => :timestamp)
    return all_columns_data
end


function save_pras_lines_limits_info(gps, scenario)
    limit = gps.interfaces.limit_forward
    limit_forward = get_interface_result(gps, limit)
    println("interface limit forward values extracted")
    odir = joinpath(pwd(), "data", "pras_metrics_output", "shortfall_data", scenario)

    ofile = joinpath(odir, "pras_interface_lim_for.csv")
    CSV.write(ofile, limit_forward)
    backward = gps.interfaces.limit_backward
    limit_backward = get_interface_result(gps, backward)
    println("interface limit forward values extracted")
    ofile = joinpath(odir, "pras_interface_lim_back.csv")
    CSV.write(ofile, limit_backward)
    lines_core = test_line_core(gps)
    println("pras lines: ",  size(lines_core,1), ", total matrix length:", length(lines_core))
    pras_lines_df = DataFrame(lines_core, :auto)
    new_names = Dict(:x1 => :name, :x2 => :ln_type, :x3 => :area_from,
    :x4 => :area_to)
    DataFrames.rename!(pras_lines_df, new_names)
    rating_dict = Dict()
    for line in pras_lines_df.name
        ll = get_component(PSY.Line, sys, line)
        ln_type = pras_lines_df[pras_lines_df.name .== line, :ln_type][1]
        if occursin("HVDCLine", ln_type)
            ll = get_component(PSY.TwoTerminalHVDCLine, sys, line)
            rating_dict[ll.name] = PSY.get_active_power_limits_from(ll).max
        else 
            rating_dict[ll.name] = PSY.get_rating(ll)
        end
    end
    line_pw = DataFrame(String(k) => v for (k, v) in pairs(rating_dict))
    DataFrames.rename!(line_pw, Dict(:first => :name, :second => :power))
    pras_lines_df = leftjoin(pras_lines_df, line_pw, on = [:name]; makeunique=true)
    ofile = joinpath(odir, "pras_lines.csv")
    CSV.write(ofile, pras_lines_df)
  
    println("done")
    println("PRAS model has - gens: ", length(gps.generators) , ", interfaces:", 
        length(gps.interfaces), ", Battery storages:", 
        length(gps.storages), ", Hydro storages:", length(gps.generatorstorages),
        ", regions:", 
        length(gps.regions), ", lines:", length(gps.lines))
end

