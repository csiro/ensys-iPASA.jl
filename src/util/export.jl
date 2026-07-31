#############################################################################
# System information export (bus/line/generator tables with coordinates)
#
# These helpers flatten a PowerSystems `System` into CSV tables (with
# geographic coordinates from the SNEM2000 case) for visualisation in the
# Python notebooks.
#############################################################################

"""
    get_gen_info(components, disp_type::AbstractString)

Flatten an iterator of available devices into a `DataFrame` with name,
bus, rating, active/reactive power, prime mover and component type.
`disp_type` is the component type label (e.g. `"ThermalStandard"`);
loads carry `rating = 0` and `prime_mover = 0`.
"""
function get_gen_info(ts, disp_type::AbstractString)
    ts_info = []
    for k in collect(ts)
        if k.available
            if disp_type == "PowerLoad"
                prime_mover = 0
                rating = 0
            else
                prime_mover = get_prime_mover_type(k).value
                rating = get_rating(k)
            end
            nested_dict = OrderedDict("name" => get_name(k),
                "bus_name" => get_bus(k).name, "rating" => rating,
                "active_power" => get_active_power(k),
                "reactive_power" => get_reactive_power(k),
                "prime_mover_type" => prime_mover,
                "comp_type" => disp_type,
            )
            push!(ts_info, nested_dict)
        end
    end
    return vcat(DataFrame.(ts_info)...)
end

"""
    get_load_gen_info(sys::System)

Collect all generators, loads and storage devices of `sys` into a single
`DataFrame` (see [`get_gen_info`](@ref) for the columns).
"""
function get_load_gen_info(sys::System)
    ts_df = get_gen_info(get_components(ThermalStandard, sys), "ThermalStandard")
    hd_df = get_gen_info(get_components(HydroDispatch, sys), "HydroDispatch")
    rd_df = get_gen_info(get_components(RenewableDispatch, sys), "RenewableDispatch")
    pl_df = get_gen_info(get_components(PowerLoad, sys), "PowerLoad")
    all_gen_load_df = vcat(rd_df, hd_df, ts_df, pl_df)
    er_df = get_gen_info(get_components(EnergyReservoirStorage, sys), "EnergyReservoirStorage")
    hr_df = get_gen_info(get_components(HydroEnergyReservoir, sys), "HydroEnergyReservoir")
    if !isempty(er_df)
        all_gen_load_df = vcat(all_gen_load_df, er_df)
    end
    if !isempty(hr_df)
        all_gen_load_df = vcat(all_gen_load_df, hr_df)
    end
    @info "Collected component info" components = nrow(all_gen_load_df)
    return all_gen_load_df
end

"""
    collect_coords_snem2000(; sc_dir=joinpath(default_data_dir(), "sc_data"))

Parse the SNEM2000 case (`snem2000_v2.m`) and return a `DataFrame` of bus
coordinates (`bus_i`, `bus_names`, `x`, `y`, `base_kv`, `area`).
"""
function collect_coords_snem2000(;
        sc_dir::AbstractString = joinpath(default_data_dir(), "sc_data"))
    file_path = joinpath(sc_dir, "snem2000_v2.m")
    isfile(file_path) || throw(ArgumentError("Coordinate case not found: $file_path"))
    nd_2000 = _PM.parse_file(file_path)
    bus_info = []
    for (k, v) in nd_2000["bus"]
        nested_dict = OrderedDict("bus_i" => v["bus_i"],
            "bus_names" => v["name"], "x" => v["x"], "y" => v["y"],
            "base_kv" => v["base_kv"], "area" => v["area"])
        push!(bus_info, nested_dict)
    end
    return vcat(DataFrame.(bus_info)...)
end

"""
    _append_lines!(line_info, lines, line_type)

Append an `OrderedDict` describing each line in `lines` to `line_info`.
`line_type` is `"ac"` (rating from the line rating) or `"dc"` (rating
from the active power flow); ratings are converted to MW on the
$(SYSTEM_BASE_MVA) MVA base.
"""
function _append_lines!(line_info, lines, line_type::AbstractString)
    for line in collect(lines)
        rating = line_type == "ac" ? line.rating * 100 : line.active_power_flow * 100
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
            "rating" => rating,
        )
        push!(line_info, nested_dict)
    end
    return line_info
end

"""
    collect_line_info(sys::System)

Return a `DataFrame` describing every AC line and two-terminal HVDC line
of `sys`, including endpoint bus attributes and ratings.
"""
function collect_line_info(sys::System)
    line_info = []
    _append_lines!(line_info, get_components(PSY.Line, sys), "ac")
    _append_lines!(line_info, get_components(PSY.TwoTerminalHVDCLine, sys), "dc")
    return vcat(DataFrame.(line_info)...)
end

"""
    collect_bus_info(sys::System)

Return a `DataFrame` of every AC bus of `sys` (number, name, base
voltage, angle, magnitude, area).
"""
function collect_bus_info(sys::System)
    bus_info = []
    for bus in collect(get_components(PSY.ACBus, sys))
        nested_dict = OrderedDict("number" => bus.number, "name" => bus.name,
            "base_voltage" => bus.base_voltage, "angle" => bus.angle,
            "magnitude" => bus.magnitude, "area" => parse(Int, bus.area.name))
        push!(bus_info, nested_dict)
    end
    return vcat(DataFrame.(bus_info)...)
end

# WKT LINESTRING helper used for GIS exports.
_linestring_geom(x1, y1, x2, y2) = "LINESTRING (" * "$x1 " * "$y1, " * "$x2 " * "$y2)"

"""
    get_all_coord_info(all_gen_load_df, sys; sc_dir=joinpath(default_data_dir(), "sc_data"))

Join bus coordinates onto the line, bus and component tables of `sys`.
Returns `(acdc_line, acdc_bus, all_gl_coord, coord_df)` where `acdc_line`
carries WKT `LINESTRING` geometries for GIS plotting.
"""
function get_all_coord_info(all_gen_load_df::DataFrame, sys::System;
        sc_dir::AbstractString = joinpath(default_data_dir(), "sc_data"))
    bus_coord_info = collect_coords_snem2000(; sc_dir = sc_dir)
    @info "Bus coordinates extracted" buses = nrow(bus_coord_info)
    coord_df = bus_coord_info[:, ["bus_names", "x", "y"]]

    acdc_line = collect_line_info(sys)
    merged_df = leftjoin(acdc_line, coord_df, on = [:name_from => :bus_names]; makeunique = true)
    acdc_line = leftjoin(merged_df, coord_df, on = [:name_to => :bus_names]; makeunique = true)
    acdc_line = DataFrames.rename(acdc_line, :x => :x_from, :y => :y_from, :x_1 => :x_to, :y_1 => :y_to)
    transform!(acdc_line, [:x_from, :y_from, :x_to, :y_to] => ByRow(_linestring_geom) => :geometry)

    acdc_bus = collect_bus_info(sys)
    acdc_bus = leftjoin(acdc_bus, coord_df, on = [:name => :bus_names])

    subset_coords = bus_coord_info[:, ["bus_names", "x", "y", "base_kv", "area"]]
    all_gl_coord = leftjoin(all_gen_load_df, subset_coords, on = [:bus_name => :bus_names]; makeunique = true)
    sb = acdc_bus[:, ["name", "area"]]
    all_gl_coord_sb = select!(all_gl_coord, Not(:area))
    all_gl_coord = leftjoin(all_gl_coord_sb, sb, on = [:bus_name => :name]; makeunique = true)
    return acdc_line, acdc_bus, all_gl_coord, coord_df
end

"""
    extract_all_branch_info(; sc_dir=joinpath(default_data_dir(), "sc_data"),
                              out_dir=joinpath(default_data_dir(), "output"),
                              case_file="nw_2044_prod_v1.m")

Extract every branch of `case_file` with endpoint names and WKT
geometries and write the result to `hvdc_all_branches.csv` in `out_dir`.
"""
function extract_all_branch_info(;
        sc_dir::AbstractString = joinpath(default_data_dir(), "sc_data"),
        out_dir::AbstractString = joinpath(default_data_dir(), "output"),
        case_file::AbstractString = "nw_2044_prod_v1.m")
    file_path = joinpath(sc_dir, case_file)
    isfile(file_path) || throw(ArgumentError("Case file not found: $file_path"))
    new_nd = _PM.parse_file(file_path)
    bus_all = DataFrame(vcat(values(new_nd["bus"])...))
    bus_all = select(bus_all, "bus_i", "name")
    my_data = Dict()
    for k in new_nd["branch"]
        my_data[k[1]] = DataFrame(name = new_nd["branch"][k[1]]["name"],
            transformer = new_nd["branch"][k[1]]["transformer"],
            f_bus_index = new_nd["branch"][k[1]]["f_bus"],
            t_bus_index = new_nd["branch"][k[1]]["t_bus"])
    end
    my_data = vcat(values(my_data)...)
    @info "All branch data collected" branches = nrow(my_data)
    xx = leftjoin(my_data, bus_all, on = [:f_bus_index => :bus_i]; makeunique = true)
    xx = leftjoin(xx, bus_all, on = [:t_bus_index => :bus_i]; makeunique = true)
    bus_coord_info = collect_coords_snem2000(; sc_dir = sc_dir)

    coord_df = bus_coord_info[:, ["bus_names", "x", "y"]]
    line_geom = leftjoin(xx, coord_df, on = [:name_1 => :bus_names]; makeunique = true)
    line_geom = leftjoin(line_geom, coord_df, on = [:name_2 => :bus_names]; makeunique = true)
    line_geom = DataFrames.rename(line_geom, :x => :x_from, :y => :y_from, :x_1 => :x_to, :y_1 => :y_to)
    transform!(line_geom, [:x_from, :y_from, :x_to, :y_to] => ByRow(_linestring_geom) => :geometry)
    line_geom = select(line_geom, "geometry", "name", "name_1", "name_2", "transformer")
    DataFrames.rename!(line_geom, :name_1 => :from_bus, :name_2 => :to_bus)
    mkpath(out_dir)
    ofile = joinpath(out_dir, "hvdc_all_branches.csv")
    CSV.write(ofile, line_geom)
    @info "Branch geometries saved" ofile
    return line_geom
end

"""
    save_system_snapshot(sys::System, scenario;
                         out_dir=joinpath(default_data_dir(), "output"),
                         sc_dir=joinpath(default_data_dir(), "sc_data"))

Export a full snapshot of `sys` for visualisation: bus coordinates,
generator/load/storage tables with coordinates, AC/DC line geometries and
all-branch geometries. Files are written to `out_dir`; when
`scenario == "test"` the component table is written to
`acdc_load_gen_bus_orig.csv` instead of `acdc_load_gen_bus.csv`.
"""
function save_system_snapshot(sys::System, scenario::AbstractString;
        out_dir::AbstractString = joinpath(default_data_dir(), "output"),
        sc_dir::AbstractString = joinpath(default_data_dir(), "sc_data"))
    mkpath(out_dir)
    all_gen_load_df = get_load_gen_info(sys)
    acdc_line, acdc_bus, all_gl_coord, coord_df =
        get_all_coord_info(all_gen_load_df, sys; sc_dir = sc_dir)

    CSV.write(joinpath(out_dir, "all_bus_coords.csv"), coord_df)
    gl_name = scenario == "test" ? "acdc_load_gen_bus_orig.csv" : "acdc_load_gen_bus.csv"
    CSV.write(joinpath(out_dir, gl_name), all_gl_coord)
    CSV.write(joinpath(out_dir, "acdc_line.csv"), acdc_line)
    CSV.write(joinpath(out_dir, "acdc_bus.csv"), acdc_bus)
    @info "AC/DC system tables saved" out_dir

    extract_all_branch_info(; sc_dir = sc_dir, out_dir = out_dir)
    @info "System snapshot saved" out_dir
    return nothing
end

"""
    get_load_gen_storage_totals(sys::System, ofile)

Aggregate system-wide and per-region load, generation, storage and
rating totals (in natural units). Writes the per-region table to `ofile`
and returns `(totals::Dict, region_table::DataFrame)`.
"""
function get_load_gen_storage_totals(sys::System, ofile::AbstractString)
    PSY.set_units_base_system!(sys, PSY.UnitSystem.NATURAL_UNITS)
    gen = 0.0
    load = 0.0
    hydro = 0.0
    storage = 0.0
    thermal_rating = 0.0
    storage_cap = 0.0
    thermal_active = 0.0
    ren_wind_active = 0.0
    ren_wind_rating = 0.0
    ren_nw_active = 0.0
    ren_nw_rating = 0.0
    ren_region_active_power = zeros(N_REGIONS, 1)
    ren_region_rating = zeros(N_REGIONS, 1)
    ther_region_active_power = zeros(N_REGIONS, 1)
    ther_region_rating = zeros(N_REGIONS, 1)
    ld_region_active_power = zeros(N_REGIONS, 1)
    hydro_act = zeros(N_REGIONS, 1)
    stg_act = zeros(N_REGIONS, 1)
    stg_cap = zeros(N_REGIONS, 1)

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

    lg_dict = Dict("load" => load, "thermal_rating" => thermal_rating,
        "thermal_active" => thermal_active,
        "ren_wind_active" => ren_wind_active, "ren_wind_rating" => ren_wind_rating,
        "ren_nw_rating" => ren_nw_rating, "ren_nw_active" => ren_nw_active,
        "hydro" => hydro, "storage" => storage, "storage_cap" => storage_cap)
    region_base_data = DataFrame(
        ren_act = vec(ren_region_active_power),
        ren_rat = vec(ren_region_rating),
        thermal_act = vec(ther_region_active_power),
        thermal_rating = vec(ther_region_rating),
        storage_act = vec(stg_act),
        storage_cap = vec(stg_cap),
        hydro_act = vec(hydro_act),
        load = vec(ld_region_active_power),
    )
    CSV.write(ofile, region_base_data)
    @info "Regional load/generation summary saved" ofile
    return lg_dict, region_base_data
end
