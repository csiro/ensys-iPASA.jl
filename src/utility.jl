
function get_load_gen_storage_system(sys, ofile)
    PSY.set_units_base_system!(sys, PSY.UnitSystem.NATURAL_UNITS)
    gen = 0
    load = 0
    hydro = 0
    storage = 0
    thermal_rating = 0
    ren_rating = 0
    pgen = Dict()
    pl = Dict()
    storage_cap = 0
    power_rating = 0
    gen_rating = 0
    thermal_active = 0
    ren_wind_active = 0
    ren_wind_rating = 0
    ren_nw_active = 0
    ren_nw_rating = 0
    ren_region_active_power = zeros(15, 1)
    ren_region_rating = zeros(15, 1)
    ther_region_active_power = zeros(15, 1)
    ther_region_rating = zeros(15, 1)
    ld_region_active_power = zeros(15, 1)
    hydro_act = zeros(15, 1)
    stg_act = zeros(15, 1)
    stg_cap = zeros(15,1)
   
    for ll in collect(PSY.get_components(PSY.RenewableDispatch, sys))
        area_name = parse.(Int, get_name(get_area(get_bus(ll))))
        gen += get_active_power(ll)
        
        if PSY.get_prime_mover_type(ll) == PrimeMovers.WT
            ren_wind_active += get_active_power(ll)
            ren_wind_rating += get_rating(ll)
        else
            ren_nw_rating += get_rating(ll)
            ren_nw_active += get_active_power(ll)
        end
        ren_region_active_power[area_name] += get_active_power(ll)
        ren_region_rating[area_name] += get_rating(ll)
        
    end
    for ll in collect(PSY.get_components(PSY.ThermalStandard, sys))
        area_name = parse.(Int, get_name(get_area(get_bus(ll))))
        gen += get_rating(ll)  
        thermal_rating += get_rating(ll)
        thermal_active += get_active_power(ll)
        ther_region_active_power[area_name] += get_active_power(ll)
        ther_region_rating[area_name] += get_rating(ll)
    end
    for ll in collect(PSY.get_components(PSY.HydroDispatch, sys))
        area_name = parse.(Int, get_name(get_area(get_bus(ll))))
        gen += get_active_power(ll) 
        hydro += get_active_power(ll)
        hydro_act[area_name] += get_active_power(ll)
        
    end
    
    for ll in collect(PSY.get_components(PSY.EnergyReservoirStorage, sys))
        area_name = parse.(Int, get_name(get_area(get_bus(ll))))
        stg_act[area_name] += get_active_power(ll)
        storage += get_active_power(ll) 
        storage_cap += get_storage_capacity(ll)
        stg_cap[area_name] += get_storage_capacity(ll)
        
    end
    for ll in collect(PSY.get_components(PSY.PowerLoad, sys))
        area_name = parse.(Int, get_name(get_area(get_bus(ll))))
        load += get_active_power(ll) 
        ld_region_active_power[area_name] += get_active_power(ll)
        
    end 
    lg_dict = Dict("load" => load, "thermal_rating" => thermal_rating, "thermal_active" => thermal_active,
        "ren_wind_active" => ren_wind_active, "ren_wind_rating" => ren_wind_rating,
        "ren_nw_rating" => ren_nw_rating, "ren_nw_active" => ren_nw_active, "hydro" => hydro,
        "storage" => storage, "storage_cap" => storage_cap)
    region_base_data = DataFrame(
        ren_act = vec(ren_region_active_power),
        ren_rat = vec(ren_region_rating),
        thermal_act = vec(ther_region_active_power),
        thermal_rating = vec(ther_region_rating),
        storage_act = vec(stg_act),
        storage_cap = vec(stg_cap),
        hydro_act = vec(hydro_act),
        load = vec(ld_region_active_power)
    )
    CSV.write(ofile, region_base_data)
    return lg_dict, region_base_data
end


function load_scaled_data(input_fl, res)
    df = CSV.read(input_fl, DataFrame)
    if res == 60  # Get only hourly data
        df = df[1:2:size(df)[1],:]
    elseif res == 1440
        df = df[1:48:size(df)[1],:]
    end
    norm_df_15 = copy(df)
    norm_df_15[:, "WNV_demand_norm"] = df[:, "VIC_demand_norm"]
    norm_df_15[:, "MEL_demand_norm"] = df[:, "VIC_demand_norm"]
    norm_df_15[:, "SEV_demand_norm"] = df[:, "VIC_demand_norm"]
    norm_df_15[:, "NSA_demand_norm"] = df[:, "CSA_demand_norm"]
    norm_df_15 = select!(norm_df_15, Not(:VIC_demand_norm))
    println("Copied normalised data with 15 areas")
    return norm_df_15
end

function normalise_data(df)
    #zones = ["QLD", "NSW", "VIC", "SA", "TAS"]
    norm_df = copy(df)
    zones = names(norm_df)
    for zn in zones
        if zn == "timestamp"
            continue
        end
        for n in names(df)
            if occursin(zn, n)
                if occursin("demand", n)
                    new_col = n * "_norm"
                    norm_df[!,new_col] = normalize_to_range(df[!,n], 0, 1)   
                end
                if occursin("Solar", n)
                    new_col = n * "_norm"
                    norm_df[!,new_col] = normalize_to_range(df[!,n], 0, 1)    
                end
                if occursin("Wind", n)
                    new_col = n * "_norm"
                    norm_df[!, new_col] = normalize_to_range(df[!,n], 0, 1) 
                end 
                if occursin("hydro", n)
                    new_col = n * "_norm"
                    norm_df[!, new_col] = normalize_to_range(df[!,n], 0, 1) 
                end 
            end
        end  
    end
    return norm_df[!, r"timestamp|norm"]
end

function normalize_to_range(col, min_val, max_val)
    col_min = minimum(col)
    col_max = maximum(col)
    return (col .- col_min) ./ (col_max - col_min) * (max_val - min_val) .+ min_val
end

function build_time_series(norm_df, res)
    time_series_data = Dict()
    
    len = size(norm_df)[1] 
   
    #dates = range(DateTime("2024-07-01T00:00:00"), 
    #     step = resolution, length = length)
    dates = minimum(norm_df.timestamp):res:maximum(norm_df.timestamp)
    for nn in names(norm_df)[2:size(norm_df)[2]]
        data = TimeArray(dates, norm_df[!,nn])
        time_series = SingleTimeSeries("max_active_power", data,  
            scaling_factor_multiplier = get_max_active_power)
        push!(time_series_data, nn => time_series)  
    end
    return time_series_data
end

function load_all_ts_test(sys, time_series_data)

    ren_dist_dict = Dict("NSW" => [1,2,3,4], "VIC" => [5,6,7], "QLD" => [8,9,10,11],
    "SA" => [12,13,14], "TAS" => [15])

    zone_dict = Dict("1" => "NNSW", "2" => "CNSW", "3" => "SNW", "4" => "SNSW", "5" => "WNV",
        "6" => "MEL", "7" => "SEV",  "8" => "NQ", "9" => "CQ", "10" => "GG",
        "11" => "SQ", "12" => "NSA", "13" => "CSA", "14" => "SESA", "15" => "TAS")
    
    for ll in collect(PSY.get_components(PSY.RenewableGen, sys))
        add_ren_ts_15(sys, ll,  time_series_data, ren_dist_dict)  
    end
    for ll in collect(PSY.get_components(PSY.HydroEnergyReservoir, sys))
        add_ren_ts_15(sys, ll,  time_series_data, ren_dist_dict)
    end 
    for ll in collect(PSY.get_components(PSY.HydroDispatch, sys))
        add_ren_ts_15(sys, ll,  time_series_data, ren_dist_dict)
    end 
    for ll in collect(PSY.get_components(PSY.PowerLoad, sys))
        key = zone_dict[ll.bus.area.name] * "_demand_norm"
        PSY.add_time_series!(sys, ll, time_series_data[key])
    end   
end

function built_load_one_yearly_TSdata(sys)
    ISP_DATA_SUB_DIR = "ISP_data_processing/data/output"
# Data is of 30 minutes for whole year July 2024- June 2025
    res = 30 # minute. Raw data is available every 30 minutes.
    input_fl = joinpath(pwd(), ISP_DATA_SUB_DIR, "2024_ISP_Step_Change_1yr_scaled.csv") 
    norm_df = load_scaled_data(input_fl, res)
    
    norm_df.timestamp = DateTime.(norm_df.timestamp, "yyyy-mm-dd HH:MM:SS")
    input_fl = joinpath(pwd(), ISP_DATA_SUB_DIR, "2024_ISP_SC_hydro_20yrs.csv") 
    
    df = CSV.read(input_fl, DataFrame)
    df.timestamp = DateTime.(df.timestamp, "yyyy-mm-dd HH:MM:SS")
    target_date = DateTime("2025-07-01", "yyyy-mm-dd")

    df = df[df.timestamp .< target_date, :]
    hydro_norm_df = normalise_data(df)
    
    norm_df = innerjoin(norm_df, hydro_norm_df, on=:timestamp)
#scenario_type = "Typical summer"
    scenario_type = ""
    norm_df = get_scenario_data(norm_df, scenario_type)
#Build as per PS static TimeSeriesData
    time_series_data = build_time_series(norm_df, Dates.Minute(res))
# Load time series data for a scenario into the system
    load_all_ts_test(sys, time_series_data)
    println("Normalised and loaded 2024-25 year time series data, resoltion 30 min for load, solar, wind and hydro")
    return time_series_data
end


function built_load_twenty_years_TSdata(sys)
    ISP_DATA_SUB_DIR = "../../../data/ISP_data/output"
# Data is of 30 minutes for whole year July 2024- June 2025
    res = 60 # minute. Raw data is available every 30 minutes.
    input_fl = joinpath(pwd(), ISP_DATA_SUB_DIR, "2024_ISP_Step_Change_20yrs_scaled.csv") 
    norm_df = load_scaled_data(input_fl, res)
    norm_df.timestamp = DateTime.(norm_df.timestamp, "yyyy-mm-dd HH:MM:SS")
    input_fl = joinpath(pwd(), ISP_DATA_SUB_DIR, "2024_ISP_SC_hydro_20yrs.csv") 
    df = CSV.read(input_fl, DataFrame)
    df.timestamp = DateTime.(df.timestamp, "yyyy-mm-dd HH:MM:SS")
    target_date = DateTime("2044-07-01", "yyyy-mm-dd")

    df = df[df.timestamp .< target_date, :]
    hydro_norm_df = normalise_data(df)
    norm_df = innerjoin(norm_df, hydro_norm_df, on=:timestamp)
#scenario_type = "Typical summer"
    scenario_type = ""
    norm_df = get_scenario_data(norm_df, scenario_type)
#Build as per PS static TimeSeriesData
    time_series_data = build_time_series(norm_df, Dates.Minute(res))
# Load time series data for a scenario into the system
    load_all_ts_test(sys, time_series_data)
    println("Normalised and loaded 20 years time series data created for load, solar, wind and hydro")
    return time_series_data
end


function built_load_six_yearly_TSdata(sys)
    ISP_DATA_SUB_DIR = "ISP_data_processing/data/output"
# Data is of 30 minutes for whole year July 2024- June 2025
    res = 30 # minute. Raw data is available every 30 minutes.
    input_fl = joinpath(pwd(), ISP_DATA_SUB_DIR, "2024_ISP_Step_Change_6yrs_scaled.csv") 
    norm_df = load_scaled_data(input_fl, res)
    norm_df.timestamp = DateTime.(norm_df.timestamp, "yyyy-mm-dd HH:MM:SS")
    input_fl = joinpath(pwd(), ISP_DATA_SUB_DIR, "2024_ISP_SC_hydro_20yrs.csv") 

    df = CSV.read(input_fl, DataFrame)
    df.timestamp = DateTime.(df.timestamp, "yyyy-mm-dd HH:MM:SS")
    target_date = DateTime("2030-07-01", "yyyy-mm-dd")

    df = df[df.timestamp .< target_date, :]
    hydro_norm_df = normalise_data(df)
    
    norm_df = innerjoin(norm_df, hydro_norm_df, on=:timestamp)
#scenario_type = "Typical summer"
    scenario_type = ""
    norm_df = get_scenario_data(norm_df, scenario_type)
#Build as per PS static TimeSeriesData
    time_series_data = build_time_series(norm_df, Dates.Minute(res))
# Load time series data for a scenario into the system
    load_all_ts_test(sys, time_series_data)
    println("Normalised and loaded 2024-30 year time series data, resoltion 30 min for load, solar, wind and hydro")
    return time_series_data
end

function built_load_SUM_ED_TSdata(sys)
    ISP_DATA_SUB_DIR = "ISP_data_processing/data/output"
# Data is of 30 minutes for whole year July 2024- June 2025
    res = 4320 # minute Actual data for summer daily maximum.
    input_fl = joinpath(pwd(), ISP_DATA_SUB_DIR, "summer_daily_ED_scaled_2025_2030.csv") 
    norm_df = load_scaled_data(input_fl, res)
    norm_df = select(norm_df, Not(:original_daily_timestamp))

    norm_df = select(norm_df, Not(:Summer_Year))
    #norm_df.timestamp = DateTime.(norm_df.timestamp, "yyyy-mm-dd")
    input_fl = joinpath(pwd(), ISP_DATA_SUB_DIR, "summer_daily_peak_hydro_2025_2030.csv") 

    df = CSV.read(input_fl, DataFrame)
    df = select(df, Not(:original_daily_timestamp))
    df = select(df, Not(:Summer_Year))
    #df.timestamp = DateTime.(df.timestamp, "yyyy-mm-dd")
    #target_date = DateTime("2029-05-09", "yyyy-mm-dd")

    #df = df[df.timestamp .< target_date, :]
    hydro_norm_df = normalise_data(df)
    
    norm_df = innerjoin(norm_df, hydro_norm_df, on=:timestamp)
#scenario_type = "Typical summer"
    scenario_type = ""
    norm_df = get_scenario_data(norm_df, scenario_type)
#Build as per PS static TimeSeriesData
    time_series_data = build_time_series(norm_df, Day(3))
# Load time series data for a scenario into the system
    load_all_ts_test(sys, time_series_data)
    println("Normalised and loaded 2025-30 year time series data,for summer extreme")
    return time_series_data
end

function add_ren_ts_15(sys, ll, time_series, ren_dist_dict)
    area_no = parse(Int, ll.bus.area.name)
    zn = find_region(ren_dist_dict, area_no)
    if ll.prime_mover_type.value == 21      # Solar
        if zn != "TAS"
            key = zn * "_Solar_norm"
            PSY.add_time_series!(sys, ll, time_series[key])
        end
                   
    elseif ll.prime_mover_type.value == 22  # Wind
        key = zn * "_Wind_norm"
        PSY.add_time_series!(sys, ll, time_series[key])
    elseif ll.prime_mover_type.value == 16  # PrimeMovers.HY
        key = zn * "_hydro_norm"
        PSY.add_time_series!(sys, ll, time_series[key])
    end
end

function find_region(ren_dist_dict, area_no)
    for (k, value) in ren_dist_dict
        if in(area_no, value)
            return k 
        end
    end
end

function get_scenario_data(norm_df, scenario_type)
    myFormat = Dates.DateFormat("yyyy-mm-dd HH:MM:SS")
    # Convert the "DateString" column to DateTime
    if isa(norm_df.timestamp, String)
        norm_df.timestamp = Dates.DateTime.(norm_df.timestamp, myFormat)
    end
    start_dt = minimum(norm_df.timestamp)
    end_dt = maximum(norm_df.timestamp)
    if scenario_type == "Typical summer"
    # Define your start and end datetimes
        start_dt = DateTime(2024, 12, 1, 0, 0, 0)
        end_dt = DateTime(2025, 3, 1, 0, 0, 0)
        # Filter the DataFrame
        norm_df = norm_df[start_dt .<= norm_df.timestamp .< end_dt, :]
    end
    return norm_df
end

function create_bat_storage_all(bus, d)
    act_power = d["energy"]
    name = d["duid"]
    storage_cap = d["energy_rating"]
    base_power = 100.0
    in_eff = d["charge_efficiency"]
    out_eff = d["discharge_efficiency"]
    #storage_cap = act_power * duration/base_power
    #rating = act_power/base_power
    rating = act_power
    return EnergyReservoirStorage(
        name = name,
        prime_mover_type = PrimeMovers.BA,
        storage_technology_type = StorageTech.OTHER_CHEM,
        available = true,
        bus = bus,
        storage_capacity = storage_cap,
        storage_level_limits = (min = 5.0 / base_power, max = 1),
        initial_storage_capacity_level = 0.05,
        rating = rating,
        active_power = rating,
        input_active_power_limits = (min = 0.0, max = rating),
        output_active_power_limits = (min = 0.0, max = rating),
        efficiency = (in = in_eff, out = out_eff),
        reactive_power = 0.0,
        reactive_power_limits = (min = -rating, max = rating),
        base_power = base_power,
    )
end

function add_storage_from_dict(data, sys)
    buses = collect(get_components(PSY.ACBus, sys))
    for (d_key, d) in data       
        name = d["duid"]
        for bus in buses
            if bus.number == d["storage_bus"]
                storage = create_bat_storage_all(bus, d)
                add_component!(sys, storage; skip_validation = PSY.SKIP_PM_VALIDATION)
            end
        end
    end
end

function build_snem2000_hvdc_v3(file_path, config_file, generator_mapping)
    
    data_dir = dirname(dirname(file_path))
    pm_data = PSY.PowerModelsData(file_path)
    #new_area_code(pm_data.data)
    base_storage_data = deepcopy(pm_data.data["storage"])
    delete!(pm_data.data, "storage")
    
    for (i, branch) in pm_data.data["branch"]
        if branch["br_x"] == 0
            branch["br_x"] = 1E-3
        end
    end
    gen_types = Dict("Coal"=>"CT", 
        "Gas"=>"CC",
        "Solar"=>"PV",
        "Wind"=>"WT",
        "Hydro"=>"HY",
        "Storage"=>"BA",
        "Biomass" => "ST",
        "Oil" => "IC",
        "Distillate" => "IC"
        )
     if haskey(pm_data.data, "gen")
        
        for (i, gen) in pm_data.data["gen"]
            if gen["fuel"] ∈ ["Water" "hydrowater"]
                gen["fuel"] = "Hydro"    
            elseif gen["fuel"] ∈ ["naturalgas" "CapBank/SVC/StatCom/SynCon"]
                #println("xxxx", ",", gen)
                gen["fuel"] = "Gas"
            elseif gen["fuel"] ∈ ["blackcoal" "browncoal"]
                gen["fuel"] = "Coal"
            elseif gen["fuel"] ∈ ["wind", "offshore_wind"]
                gen["fuel"] = "Wind"
            elseif gen["fuel"] == "solar"
                gen["fuel"] = "Solar"
            elseif gen["fuel"] == "Distillate"
                gen["fuel"] = "Oil"
            end
            gen["type"] = gen_types[gen["fuel"]]
            if gen["gen_status"] == 0
                delete!(pm_data.data["gen"], i)
            end   
        end
    end 
    sys = PSY.System(pm_data, frequency=50, config_path=config_file,
        generator_mapping=generator_mapping)
    add_storage_from_dict(base_storage_data, sys)
    return sys, pm_data, base_storage_data
end

function initialise_system_v3(file_path)
    
    config_file = "power_system_structs.json"
    generator_mapping = "generator_mapping.yaml"
    sys, pm_data, base_storage_data = build_snem2000_hvdc_v3(file_path, 
        config_file, generator_mapping)
    sys.metadata.name = "snem_15_regions"
    sys.metadata.description = "15-regions SNEM ACDC model, "*
"this representation "*"is based on clustering data from 15 regions"
    #PSY.set_units_base_system!(sys, PSY.UnitSystem.NATURAL_UNITS)
    
    return sys, pm_data, base_storage_data
end

function calculate_gen_rating(act, react, base_conversion)
    rating = sqrt(act^2 + react^2)
    if rating == 0.0
        return 1.0
    end
    return rating * base_conversion
end

function create_hydro_dispatch(d::Dict, bus::ACBus)
    sys_mbase = 100
    base_conversion = sys_mbase / d["mbase"]
    rating = calculate_gen_rating(d["pmax"], d["qmax"], base_conversion)
    return HydroDispatch(
        name = d["name"],
        available = true,
        bus = bus,
        active_power = d["pg"] * base_conversion,
        reactive_power = d["qg"] * base_conversion,
        rating = rating,
        prime_mover_type = PrimeMovers.HY,
        active_power_limits = (
            min=d["pmin"] * base_conversion,
            max=d["pmax"] * base_conversion,
        ),
        reactive_power_limits = (
            min=d["qmin"] * base_conversion,
            max=d["qmax"] * base_conversion,
        ),
        ramp_limits = (up=abs(d["pmax"]), down=abs(d["pmax"])),
        time_limits = nothing,
        operation_cost = HydroGenerationCost(nothing),
        base_power = d["mbase"],
    )
end

function create_thermal_gen(d::Dict, bus::ACBus)
    sys_mbase = 100
    base_conversion = sys_mbase / d["mbase"]
    rating = calculate_gen_rating(d["pmax"], d["qmax"], base_conversion)
    if d["fuel"] == "naturalgas"
        prime_mover_type = PrimeMovers.CC
        fuel_cat = ThermalFuels.NATURAL_GAS
    elseif d["fuel"] == "blackcoal" || d["fuel"] == "browncoal"
        prime_mover_type = PrimeMovers.ST
        fuel_cat = ThermalFuels.COAL
    else
        println("Unknown fuel category is noticed, not processing it..")
        return
    end
    return ThermalStandard(
        name = d["name"],
        available = true,
        status = true,
        bus = bus,
        active_power = d["pg"] * base_conversion,
        reactive_power = d["qg"] * base_conversion,
        rating = rating,
        prime_mover_type = prime_mover_type,
        fuel = fuel_cat,
        active_power_limits = (min=d["pmin"] * base_conversion, max=d["pmax"] * base_conversion),
        reactive_power_limits = (min=d["qmin"] * base_conversion, max=d["qmax"] * base_conversion),
        time_limits = nothing,
        ramp_limits = (up = abs(d["pmax"]), down = abs(d["pmax"])),
        operation_cost = ThermalGenerationCost(nothing),
        base_power = d["mbase"],
    )
end

function create_solar_wind_rez(d::Dict, bus::ACBus)
    sys_mbase = 100
    base_conversion = sys_mbase / d["mbase"]
    rating = calculate_gen_rating(d["pmax"], d["qmax"], base_conversion)
    if lowercase(d["fuel_type"]) == "solar"
        prime_mover_type = PrimeMovers.PVe
    elseif lowercase(d["fuel_type"]) == "wind" || lowercase(d["fuel_type"]) == "offshore_wind"
        prime_mover_type = PrimeMovers.WT    
    end    
    return RenewableDispatch(
        name = d["name"],
        available = true,
        bus = bus,
        active_power = d["pg"] * base_conversion, 
        reactive_power = d["qg"] * base_conversion, 
        rating = rating, 
        prime_mover_type = prime_mover_type,
        reactive_power_limits = (min=d["qmin"] * base_conversion, max=d["qmax"] * base_conversion), 
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),
        base_power = d["mbase"]
    )
end

function make_res_storage(d::Dict, bus::ACBus)
    energy_rating = iszero(d["energy_rating"]) ? d["energy"] : d["energy_rating"]
    base_power = 100.0
    pu_power = d["energy"]/base_power
    storage = EnergyReservoirStorage(;
        name = d["name"],
        available = true,
        bus = bus,
        prime_mover_type = PrimeMovers.BA,
        storage_technology_type = StorageTech.OTHER_CHEM,
        storage_capacity = energy_rating / base_power,
        storage_level_limits = (min = 5.0 / base_power, max = 1),
        initial_storage_capacity_level = d["energy"] / energy_rating,
        rating = pu_power,
        active_power = pu_power,
        input_active_power_limits = (min = 0.0, max = pu_power),
        output_active_power_limits = (min = 0.0, max = pu_power),
        efficiency = (in = d["charge_efficiency"], out = d["charge_efficiency"]),
        reactive_power = 0.0,
        reactive_power_limits = (min = -pu_power, max = pu_power),
        base_power = base_power,
    )
    return storage
end

function add_future_gen(sys, scenario, location)
    if scenario == "ST"
        file_path = joinpath(location, "future_gen_2025_pp.csv")
    elseif scenario == "MT" || scenario == "SUM_ED"
        file_path = joinpath(location, "future_gen_2030_pp.csv")
    else
        file_path = joinpath(location, "future_gen_pp.csv")
    end
            
    fut_gn = CSV.File(file_path)
    for row in fut_gn
        row_dict = Dict(String(k) => v for (k, v) in pairs(row))
        bus_name = row_dict["bus_name"]
        gen_name = row_dict["name"]
        bus = get_component(ACBus, sys, bus_name)
        fuel_type = lowercase(row_dict["fuel_type"])
        
        if fuel_type == "solar" || fuel_type == "wind" || fuel_type == "offshore_wind"
            gen_com = create_solar_wind_rez(row_dict, bus)
        elseif fuel_type == "hydro"
            gen_com = create_hydro_dispatch(row_dict, bus)
        else
            gen_com = create_thermal_gen(row_dict, bus)
        end
        try
            add_component!(sys, gen_com)
            #println("Generator added: ", gen_name,",", fuel_type)
        catch e
            if e isa ArgumentError
                println("Generator is already exist: ", gen_name)
            end
        end
    end
end

function add_future_storage(sys, scenario, location)
    if scenario == "ST"
        file_path = joinpath(location, "future_storage_2025_pp.csv")
    elseif scenario == "MT" || scenario == "SUM_ED"
        file_path = joinpath(location, "future_storage_2030_pp.csv")
    else
        file_path = joinpath(location, "future_storage_pp.csv")
    end
    fut_st = CSV.File(file_path)
    for row in fut_st
        row_dict = Dict(String(k) => v for (k, v) in pairs(row))
        bus_name = row_dict["bus_name"]
        st_name = row_dict["name"]
        bus = get_component(ACBus, sys, bus_name)
        stg_com = make_res_storage(row_dict, bus)
        try
            add_component!(sys, stg_com)
            #println("Storage added: ", st_name)
        catch e
            if e isa ArgumentError
                println("Storage is already exist: ", st_name)
            end
            println("error occured: ", e)
        end
    end
end

function add_future_status_therm_stor(sys, scenario, file_path, gen_stg_type="gen",
        resolution=nothing,
        start_date=DateTime(2024, 7, 1, 0, 0, 0), 
        end_date=DateTime(2030, 6, 30, 23, 30, 0))
    if gen_stg_type == "gen"
        disp_name = PSY.ThermalStandard
    else
        disp_name = PSY.EnergyReservoirStorage
    end
    start_date = start_date
    if resolution == nothing
        resolution = Dates.Minute(30)
    end
    if scenario == "ST"
        end_date = DateTime(2025, 6, 30, 23, 30, 0)
    elseif scenario == "MT"
        end_date = DateTime(2030, 6, 30, 23, 30, 0)
    elseif scenario == "LT"
        resolution = Dates.Hour(1)
        end_date = DateTime(2044, 6, 30, 23, 0, 0)
    elseif scenario == "SUM_ED"
        resolution = Dates.Day(3)
        start_date = DateTime(2024, 12, 1, 0, 0, 0) 
        end_date = DateTime(2029, 5, 9, 23, 30, 0)  
    end
    expiry_data = CSV.File(file_path; missingstring=nothing)
    if gen_stg_type == "gen"
        target_date_index = 11
    else
        target_date_index = 10
    end
    
    for row in expiry_data
        name = String(row[1])
        target_date = row[target_date_index]
        if DateTime(target_date) >= end_date
              target_date = end_date
        end
        start_date_2 = DateTime(target_date) + resolution
        dates = start_date:resolution:DateTime(target_date)
        one_array = floor.(Int, ones(length(dates)))
        zero_array = floor.(Int, zeros(length(dates)))
        if gen_stg_type == "gen"
            ts_data = TimeArray(dates, one_array, ["Value"])
        else
            ts_data = TimeArray(dates, zero_array, ["Value"])
        end
        dates = start_date_2:resolution:end_date
        zero_array = floor.(Int, zeros(length(dates)))
        one_array = floor.(Int, ones(length(dates)))
        if gen_stg_type == "gen"
            ts_data = vcat(ts_data, TimeArray(dates, zero_array, ["Value"]))
        else
            ts_data = vcat(ts_data, TimeArray(dates, one_array, ["Value"]))
        end
        ts = SingleTimeSeries("max_active_power", ts_data, 
            scaling_factor_multiplier = get_max_active_power)
        if !isnothing(get_component(disp_name, sys, name))
            component = get_component(disp_name, sys, name)
            if !PSY.has_time_series(component)
                add_time_series!(sys, component, ts)
            end
        end
    end
end

function get_gen_info(ts, disp_type)
    ts_info = []
    for k in collect(ts)
    #nested_dict = Dict{Int, Int, Float32, Float32, Int}()
        if k.available
            if disp_type == "PowerLoad"
                prime_mover = 0
                rating = 0
            else
                prime_mover = get_prime_mover_type(k).value
                rating = get_rating(k)
            end
            nested_dict = OrderedDict( "name" => get_name(k),
                "bus_name" => get_bus(k).name, "rating" => rating,
                "active_power" => get_active_power(k),
                "reactive_power" => get_reactive_power(k),
                "prime_mover_type" => prime_mover,
                "comp_type" => disp_type
            )
            push!(ts_info, nested_dict)
        end   
    end
    ts_df = vcat(DataFrame.(ts_info)...)
    return ts_df
end

function get_all_coord_info(all_gen_load_df, sys)
    bus_coord_info = collect_coords_snem2000()
    println("bus coords extracted")
    coord_df = bus_coord_info[:, ["bus_names", "x", "y"]]
# filter_starbus = filter(:bus_names => n -> contains(n, "starbus"), coord_df)
    acdc_line = collect_line_info(sys)
    merged_df = leftjoin(acdc_line, coord_df, on = [:name_from => :bus_names]; makeunique=true)
    acdc_line = leftjoin(merged_df, coord_df, on = [:name_to => :bus_names]; makeunique=true)
# Rename columns in merged_df to add a suffix
    acdc_line = DataFrames.rename(acdc_line, :x => :x_from, :y => :y_from, :x_1 => :x_to, :y_1 => :y_to)
    create_linestring_geom(x1,y1,x2,y2) = "LINESTRING ("* "$x1 "* "$y1, "*"$x2 "*"$y2)"
    transform!(acdc_line, [:x_from	, :y_from, :x_to, :y_to] => ByRow(create_linestring_geom) => :geometry)
    acdc_bus = collect_bus_info(sys)
    acdc_bus = leftjoin(acdc_bus, coord_df, on = [:name => :bus_names])
    subset_coords = bus_coord_info[:, ["bus_names", "x", "y", "base_kv", "area"]]
    all_gl_coord = leftjoin(all_gen_load_df, subset_coords, on = [:bus_name => :bus_names]; makeunique=true)
    sb = acdc_bus[:, ["name", "area"]]
    all_gl_coord_sb = select!(all_gl_coord, Not(:area))
    all_gl_coord = leftjoin(all_gl_coord_sb, sb,
        on = [:bus_name => :name]; makeunique=true)
    println("done")
    return acdc_line, acdc_bus, all_gl_coord, coord_df
end

function get_load_gen_info(sys)
    ts_df = get_gen_info(get_components(ThermalStandard, sys), "ThermalStandard")
    hd_df = get_gen_info(get_components(HydroDispatch, sys), "HydroDispatch")
    rd_df = get_gen_info(get_components(RenewableDispatch, sys), "RenewableDispatch")
    pl_df = get_gen_info(get_components(PowerLoad, sys), "PowerLoad")
    all_gen_load_df  = vcat(rd_df, hd_df, ts_df, pl_df)
    er_df = get_gen_info(get_components(EnergyReservoirStorage, sys),
        "EnergyReservoirStorage")
    hr_df = get_gen_info(get_components(HydroEnergyReservoir, sys), "HydroEnergyReservoir")
    if !isempty(er_df)
        all_gen_load_df  = vcat(all_gen_load_df, er_df)
    end
    if !isempty(hr_df)
        all_gen_load_df  = vcat(all_gen_load_df, hr_df)
    end               
    println("done")
    return all_gen_load_df
end

function save_data(all_gen_load_df, sys, scenario)
    acdc_line, acdc_bus, all_gl_coord, coord_df =  get_all_coord_info(all_gen_load_df, sys)
    out_path = joinpath(pwd(), "data", "output")
    out_file = joinpath(out_path, "all_bus_coords.csv")
    CSV.write(out_file, coord_df)
    out_path = joinpath(pwd(), "data", "output")
    if scenario == "test"
        out_file = joinpath(out_path, "acdc_load_gen_bus_orig.csv")
    else
        out_file = joinpath(out_path, "acdc_load_gen_bus.csv")
    end
    CSV.write(out_file, all_gl_coord)
    out_path = joinpath(pwd(), "data", "output")
    out_file = joinpath(out_path, "acdc_line.csv")
    CSV.write(out_file, acdc_line)
    out_file = joinpath(out_path, "acdc_bus.csv")
    CSV.write(out_file, acdc_bus)
end

function collect_line_info(sys)
    lines = get_components(PSY.Line, sys)
#collect(buses)[1]
    line_info = []
    line_type = "ac"
    get_lines(lines, line_info, line_type)
    lines = get_components(PSY.TwoTerminalHVDCLine, sys)
    line_type = "dc"
    get_lines(lines, line_info, line_type)
    return vcat(DataFrame.(line_info)...)
end  

function get_lines(lines, line_info, line_type)
    rating = 1 
    for line in collect(lines)
        if line_type == "ac"
            rating = line.rating * 100
        else
            rating = line.active_power_flow * 100
        end
        
    #nested_dict = Dict{Int, Int, Float32, Float32, Int}()
        nested_dict = OrderedDict("name" => line.name, 
            "number_from" => line.arc.from.number,
            "name_from" => line.arc.from.name,
            "base_voltage_from" => line.arc.from.base_voltage, 
            "angle_from" => line.arc.from.angle,
            "magnitude_from" => line.arc.from.magnitude,
            "area_from" => parse(Int, line.arc.from.area.name),
            "number_to" => line.arc.to.number,
            "name_to" => line.arc.to.name,
            "base_voltage_to" => line.arc.to.base_voltage, 
            "angle_to" => line.arc.to.angle,
            "magnitude_to" => line.arc.to.magnitude,
            "area_to" => parse(Int, line.arc.to.area.name),
            "line_type" => line_type,
            "rating" => rating  
        )

        push!(line_info, nested_dict)
    end 
end

function collect_bus_info(sys)
    buses = get_components(PSY.ACBus, sys)
#collect(buses)[1]
    bus_info = []
    for bus in collect(buses)
    #nested_dict = Dict{Int, Int, Float32, Float32, Int}()
        nested_dict = OrderedDict("number" => bus.number, "name" => bus.name,
            "base_voltage" => bus.base_voltage, "angle" => bus.angle,
            "magnitude" => bus.magnitude, "area" => parse(Int, bus.area.name))

        push!(bus_info, nested_dict)
    
    end
    return vcat(DataFrame.(bus_info)...)
end

function collect_coords_snem2000()
    location = joinpath(pwd(), "data", "sc_data")
    file_path = joinpath(location, "snem2000_v2.m")
    nd_2000 = PowerModels.parse_file(file_path)
    bus_info = []
    for (k,v) in nd_2000["bus"]
    #nested_dict = Dict{Int, Int, Float32, Float32, Int}()
        nested_dict = OrderedDict("bus_i" => v["bus_i"],
        "bus_names" => v["name"], "x" => v["x"], "y" => v["y"],
        "base_kv" => v["base_kv"], "area" => v["area"])
        push!(bus_info, nested_dict)
    end
    return vcat(DataFrame.(bus_info)...)
end

function extract_all_branch_info()
    location = joinpath(pwd(),   "data", "sc_data")
    #file_path = joinpath(location, "nem_2000bus_hvdc_v2.m")
    file_path = joinpath(location, "nw_2044_prod_v1.m")
    new_nd = PowerModels.parse_file(file_path)
    bus_all = DataFrame(vcat(values(new_nd["bus"])...))
    bus_all =  select(bus_all, "bus_i", "name")
    my_data = Dict()
    for k in new_nd["branch"]
        my_data[k[1]] = DataFrame(name=new_nd["branch"][k[1]]["name"], 
            transformer=new_nd["branch"][k[1]]["transformer"],
            f_bus_index=new_nd["branch"][k[1]]["f_bus"],
            t_bus_index=new_nd["branch"][k[1]]["t_bus"])
    end
    my_data = vcat(values(my_data)...)  
    println("all branch data collected") 
    xx = leftjoin(my_data, bus_all, on = [:f_bus_index => :bus_i]; makeunique=true)
    xx = leftjoin(xx, bus_all, on = [:t_bus_index => :bus_i]; makeunique=true)
    bus_coord_info = collect_coords_snem2000()
    
    coord_df = bus_coord_info[:, ["bus_names", "x", "y"]]
    line_geom  = leftjoin(xx, coord_df, on = [:name_1 => :bus_names]; makeunique=true)
    line_geom  = leftjoin(line_geom, coord_df, on = [:name_2 => :bus_names]; makeunique=true)
    line_geom = DataFrames.rename(line_geom, :x => :x_from, :y => :y_from, :x_1 => :x_to, :y_1 => :y_to)
    create_linestring_geom(x1,y1,x2,y2) = "LINESTRING ("* "$x1 "* "$y1, "*"$x2 "*"$y2)"
    transform!(line_geom, [:x_from	, :y_from, :x_to, :y_to] => ByRow(create_linestring_geom) => :geometry)
    line_geom = select(line_geom, "geometry", "name", "name_1", "name_2", "transformer")
    DataFrames.rename!(line_geom, :name_1 => :from_bus, :name_2 => :to_bus)
    ofile = joinpath(pwd(), "data", "output", "hvdc_all_branches.csv")
    CSV.write(ofile, line_geom)
    println("bus coords extracted and saved")   
end


function save_newly_built_system(sys, scenario)
    all_gen_load_df = get_load_gen_info(sys)
    println("collected all components")
    acdc_line, acdc_bus, all_gl_coord, coord_df =  get_all_coord_info(all_gen_load_df, sys)
    save_data(all_gen_load_df, sys, scenario)
    println("acdc all info collected")
    extract_all_branch_info()
    println("system information saved ")
end


function extract_data(sim_st)
    sim_result = SimulationResults(sim_st)
    uc_results = get_decision_problem_results(sim_result, "SNEM-SYS")

    gen = PA.get_generation_data(uc_results, curtailment=false)
    sys_1 = PA.PSI.get_system(uc_results)
    cat = PA.make_fuel_dictionary(sys_1, curtailment=false, generator_mapping_file="gen_mapping_pg.yaml")
    fuel = PA.categorize_data(gen.data, cat; curtailment = false)
    res_dict = read_variables(uc_results)

    gas = sum.(eachrow(fuel["Natural Gas CC"]))
    hydro = sum.(eachrow(fuel["Hydropower"]))
#biomass = sum.(eachrow(fuel["Biomass ST"]))
    PV = sum.(eachrow(fuel["PV"]))
    Battery = sum.(eachrow(fuel["Battery"]))
    Wind = sum.(eachrow(fuel["Wind"]))
#Distillate = sum.(eachrow(fuel["Distillate"]))
    Coal = sum.(eachrow(fuel["Coal"]))
    numeric_cols = names(fuel["Unserved Energy"], Not("DateTime"))
    unserved_energy = sum.(eachrow(fuel["Unserved Energy"][!, numeric_cols]))
    numeric_cols = names(fuel["Over Generation"], Not("DateTime"))
    over_gen = sum.(eachrow(fuel["Over Generation"][!, numeric_cols]))
    fuel_mix = DataFrame(timestamp = fuel["Over Generation"][!,"DateTime"], gas = gas, 
        Coal=Coal, hydro=hydro,
        PV = PV, Battery=Battery,Wind=Wind,
        unserved_energy=unserved_energy,over_gen=over_gen)

    hydro_gen = PA.calc_active_power(make_selector(HydroDispatch), uc_results)
    numeric_cols = names(hydro_gen, Not("DateTime"))
    hg = sum.(eachrow(hydro_gen[!, numeric_cols]))
    renewable_generation = PA.calc_active_power(make_selector(RenewableGen), uc_results)
    thermal_gen = PA.calc_active_power(make_selector(ThermalStandard), uc_results)
    load = PA.get_load_data(uc_results)
    load_agg = PA.combine_categories(load.data)
    numeric_cols = names(thermal_gen, Not("DateTime"))
    tg = sum.(eachrow(thermal_gen[!, numeric_cols]))
    numeric_cols = names(renewable_generation, Not("DateTime"))
    rg = sum.(eachrow(renewable_generation[!, numeric_cols]))
#load_df = DataFrame(timestamp = load.time, load = load_agg[:, "Load"], thermal = tg, renewable = rg, hydro = hg)
    storage_area_selector =
        make_selector(EnergyReservoirStorage; groupby = (x -> get_name(get_area(get_bus(x)))))
    df = PA.compute_all(uc_results,
        (
            PA.calc_active_power_in,
            rebuild_selector(storage_area_selector; groupby = :all),
            "Storage Charging",
        ),
        (
            PA.calc_active_power_out,
            rebuild_selector(storage_area_selector; groupby = :all),
            "Storage Discharging",
        ),
        (
            PA.calc_stored_energy,
            rebuild_selector(storage_area_selector; groupby = :all),
            "Stored Energy",
        ),
    );
    df[!, "load"] = load_agg[:, "Load"]
    merged_df = innerjoin(fuel_mix, df, on = :timestamp => :DateTime)
    return merged_df
end

function get_template_standard_uc_simulation()
    template = ProblemTemplate(NetworkModel(CopperPlatePowerModel;use_slacks=true,))
    PSI.set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
    PSI.set_device_model!(template, PowerLoad, StaticPowerLoad)
    PSI.set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
    device_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict{String, Any}(
            "reservation" => true,
            "cycling_limits" => false,
            "energy_target" => true,
            "complete_coverage" => false,
            "regularization" => false,
        ),
    )
    PSI.set_device_model!(template, device_model)
    PSI.set_device_model!(template, TapTransformer, StaticBranch)
    PSI.set_device_model!(template, Transformer2W, StaticBranch)
    PSI.set_device_model!(template, device_model)
    PSI.set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
    PSI.set_device_model!(template, DeviceModel(Line, StaticBranch))
    PSI.set_device_model!(template, DeviceModel(TwoTerminalHVDCLine, HVDCTwoTerminalDispatch))
    return template
end

function formulate_decision_model(sys, pasa)
  # Transform it to Deterministic
  # Resolution:
  # Short Term PASA: Half-hourly resolution. six days
  # Medium Term PASA: Daily resolution. Two years
    
    if pasa == "ST"
        PSY.transform_single_time_series!(sys, Hour(48), Hour(24))
        
    elseif pasa == "MT"
        PSY.transform_single_time_series!(sys, Day(365), Day(1), resolution=Day(1))  
    end
    template = get_template_standard_uc_simulation()
    solver = optimizer_with_attributes(HiGHS.Optimizer,  "mip_rel_gap" => 0.05)
    problem = DecisionModel(template, sys; optimizer = solver,
        name="SNEM-SYS", allow_fails = true,)
    build!(problem; output_dir = mktempdir(; cleanup = true))
    return problem
end 


function run_simulation(sys, pasa, name, steps)
    steps = steps
    #set_run_flag(sys)
    problem = formulate_decision_model(sys, pasa)
    models = SimulationModels(;
        decision_models = [
            problem
        ],
    )
    sequence = SimulationSequence(;
        models = models,
        ini_cond_chronology = InterProblemChronology(),
    )
   
    sim = Simulation(;
        name = name,
        steps = steps,
        models = models,
        sequence = sequence,
        initial_time = DateTime("2025-01-10T00:00:00"),
        simulation_folder = mktempdir(; cleanup = true),
    )
    build_out = build!(sim)
    execute_out = execute!(sim, enable_progress_bar = true)
    return sim
end