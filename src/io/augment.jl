#############################################################################
# System augmentation: base loads, future generators, storage and
# retirement/commissioning status time series
#############################################################################

"""
    _future_file(scenario, location, st_file, mt_file, lt_file)

Select the scenario-appropriate CSV inside `location`: `st_file` for
`"ST"`, `mt_file` for `"MT"`/`"SUM_ED"` and `lt_file` otherwise (LT
variants).
"""
function _future_file(scenario, location, st_file, mt_file, lt_file)
    file = scenario == "ST" ? st_file :
           (scenario == "MT" || scenario == "SUM_ED") ? mt_file : lt_file
    path = joinpath(location, file)
    isfile(path) || throw(ArgumentError("Input data file not found: $path"))
    return path
end

"""
    add_baseload!(sys::System, location=joinpath(default_data_dir(), "sc_data"))

Set the 2025 base-year active/reactive power on the existing `PowerLoad`
components of `sys` from `base_load_2025.csv` in `location`.
"""
function add_baseload!(sys::System,
        location::AbstractString = joinpath(default_data_dir(), "sc_data"))
    file_path = joinpath(location, "base_load_2025.csv")
    isfile(file_path) || throw(ArgumentError("Base load file not found: $file_path"))
    base_load = CSV.File(file_path)
    n = 0
    for row in base_load
        row_dict = Dict(String(k) => v for (k, v) in pairs(row))
        load = get_component(PowerLoad, sys, row_dict["name"])
        if load === nothing
            @warn "Load not found in system; skipping" name = row_dict["name"]
            continue
        end
        set_active_power!(load, row_dict["pd"])
        set_max_active_power!(load, row_dict["pd"])
        set_reactive_power!(load, row_dict["qd"])
        set_max_reactive_power!(load, row_dict["qd"])
        n += 1
    end
    @info "Base load applied to $n loads"
    return sys
end

"""
    add_future_generators!(sys::System, scenario, location=joinpath(default_data_dir(), "sc_data"))

Add the future (committed/anticipated) generators for `scenario` to `sys`.
The generator list is read from `future_gen_2025_pp.csv` (ST),
`future_gen_2030_pp.csv` (MT / SUM_ED) or `future_gen_pp.csv` (LT).
Devices that already exist in the system are skipped with a warning.
"""
function add_future_generators!(sys::System, scenario::AbstractString,
        location::AbstractString = joinpath(default_data_dir(), "sc_data"))
    file_path = _future_file(scenario, location,
        "future_gen_2025_pp.csv", "future_gen_2030_pp.csv", "future_gen_pp.csv")
    fut_gn = CSV.File(file_path)
    added = 0
    for row in fut_gn
        row_dict = Dict(String(k) => v for (k, v) in pairs(row))
        bus = get_component(ACBus, sys, row_dict["bus_name"])
        if bus === nothing
            @warn "Bus not found; skipping generator" bus = row_dict["bus_name"] gen = row_dict["name"]
            continue
        end
        fuel_type = lowercase(row_dict["fuel_type"])
        gen_com = if fuel_type in ("solar", "wind", "offshore_wind")
            create_renewable_dispatch(row_dict, bus)
        elseif fuel_type == "hydro"
            create_hydro_dispatch(row_dict, bus)
        else
            create_thermal_gen(row_dict, bus)
        end
        try
            add_component!(sys, gen_com)
            added += 1
        catch e
            if e isa ArgumentError
                @warn "Generator already exists; skipping" name = row_dict["name"]
            else
                rethrow(e)
            end
        end
    end
    @info "Future generators added" scenario added source = basename(file_path)
    return sys
end

"""
    add_future_storage!(sys::System, scenario, location=joinpath(default_data_dir(), "sc_data"))

Add the future battery storage devices for `scenario` to `sys`. The list
is read from `future_storage_2025_pp.csv` (ST), `future_storage_2030_pp.csv`
(MT / SUM_ED) or `future_storage_pp.csv` (LT). Devices that already exist
are skipped with a warning.
"""
function add_future_storage!(sys::System, scenario::AbstractString,
        location::AbstractString = joinpath(default_data_dir(), "sc_data"))
    file_path = _future_file(scenario, location,
        "future_storage_2025_pp.csv", "future_storage_2030_pp.csv", "future_storage_pp.csv")
    fut_st = CSV.File(file_path)
    added = 0
    for row in fut_st
        row_dict = Dict(String(k) => v for (k, v) in pairs(row))
        bus = get_component(ACBus, sys, row_dict["bus_name"])
        if bus === nothing
            @warn "Bus not found; skipping storage" bus = row_dict["bus_name"] storage = row_dict["name"]
            continue
        end
        stg_com = make_res_storage(row_dict, bus)
        try
            add_component!(sys, stg_com)
            added += 1
        catch e
            if e isa ArgumentError
                @warn "Storage already exists; skipping" name = row_dict["name"]
            else
                rethrow(e)
            end
        end
    end
    @info "Future storage added" scenario added source = basename(file_path)
    return sys
end

"""
    add_retirement_status!(sys, scenario, file_path, device_kind="gen";
                           resolution=nothing,
                           start_date=DateTime(2024, 7, 1),
                           end_date=DateTime(2030, 6, 30, 23, 30, 0))

Attach 0/1 `max_active_power` status time series to thermal generators
(`device_kind = "gen"`) or battery storage (`device_kind = "storage"`)
encoding commissioning/retirement dates read from `file_path`.

For generators the series is 1 until the expiry date (`exp_time` column)
and 0 afterwards; for storage it is 0 until the commissioning date
(`datetime` column) and 1 afterwards.

The simulation window and resolution are set from `scenario`
(`"ST"`, `"MT"`, `"LT"`, `"SUM_ED"`); explicit `resolution`/`start_date`/
`end_date` keywords override the defaults. Components without an entry in
the file, or that already carry time series, are left untouched.
"""
function add_retirement_status!(sys::System, scenario::AbstractString,
        file_path::AbstractString, device_kind::AbstractString = "gen";
        resolution = nothing,
        start_date::DateTime = DateTime(2024, 7, 1, 0, 0, 0),
        end_date::DateTime = DateTime(2030, 6, 30, 23, 30, 0))
    device_kind in ("gen", "storage") ||
        throw(ArgumentError("device_kind must be \"gen\" or \"storage\", got \"$device_kind\""))
    isfile(file_path) || throw(ArgumentError("Status data file not found: $file_path"))

    disp_name = device_kind == "gen" ? PSY.ThermalStandard : PSY.EnergyReservoirStorage
    date_column = device_kind == "gen" ? :exp_time : :datetime

    if resolution === nothing
        resolution = Dates.Minute(30)
    end
    sclass = scenario_class(scenario)
    if sclass == "ST"
        end_date = DateTime(2025, 6, 30, 23, 30, 0)
    elseif sclass == "MT"
        end_date = DateTime(2030, 6, 30, 23, 30, 0)
    elseif sclass == "LT"
        resolution = Dates.Hour(1)
        end_date = DateTime(2044, 6, 30, 23, 0, 0)
    elseif sclass == "SUM_ED"
        resolution = Dates.Day(3)
        start_date = DateTime(2024, 12, 1, 0, 0, 0)
        end_date = DateTime(2029, 5, 9, 23, 30, 0)
    end

    expiry_data = CSV.File(file_path; missingstring = nothing)
    attached = 0
    for row in expiry_data
        name = String(row[1])
        target_date = getproperty(row, date_column)
        if DateTime(target_date) >= end_date
            target_date = end_date
        end

        # Status before/after the target date:
        #   generators: 1 (in service) then 0 (retired)
        #   storage:    0 (not yet built) then 1 (commissioned)
        dates_before = start_date:resolution:DateTime(target_date)
        dates_after = (DateTime(target_date) + resolution):resolution:end_date
        before_val = device_kind == "gen" ? 1 : 0
        after_val = 1 - before_val
        ts_data = vcat(
            TimeArray(dates_before, fill(before_val, length(dates_before)), ["Value"]),
            TimeArray(dates_after, fill(after_val, length(dates_after)), ["Value"]),
        )
        ts = SingleTimeSeries("max_active_power", ts_data,
            scaling_factor_multiplier = get_max_active_power)

        component = get_component(disp_name, sys, name)
        if component !== nothing && !PSY.has_time_series(component)
            add_time_series!(sys, component, ts)
            attached += 1
        end
    end
    @info "Status time series attached" device_kind scenario attached
    return sys
end
