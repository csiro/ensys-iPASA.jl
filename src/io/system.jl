#############################################################################
# System construction from MATPOWER-style network cases
#############################################################################

"""
    _remap_fuel_categories!(pm_data::Dict)

Normalise the free-form fuel strings found in the SNEM MATPOWER cases
(e.g. `"blackcoal"`, `"hydrowater"`) into canonical categories and set a
matching generator `type` code. Out-of-service generators
(`gen_status == 0`) are removed.
"""
function _remap_fuel_categories!(pm_data::Dict)
    gen_types = Dict(
        "Coal" => "CT",
        "Gas" => "CC",
        "Solar" => "PV",
        "Wind" => "WT",
        "Hydro" => "HY",
        "Storage" => "BA",
        "Biomass" => "ST",
        "Oil" => "IC",
        "Distillate" => "IC",
    )
    haskey(pm_data, "gen") || return pm_data
    for (i, gen) in pm_data["gen"]
        if gen["fuel"] ∈ ["Water" "hydrowater"]
            gen["fuel"] = "Hydro"
        elseif gen["fuel"] ∈ ["naturalgas" "CapBank/SVC/StatCom/SynCon"]
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
            delete!(pm_data["gen"], i)
        end
    end
    return pm_data
end

"""
    add_storage_from_dict!(sys::System, data::Dict)

Attach battery storage devices described by the MATPOWER `storage` table
`data` to the matching buses of `sys` (matched on bus number).
"""
function add_storage_from_dict!(sys::System, data::Dict)
    buses = collect(get_components(PSY.ACBus, sys))
    for (_, d) in data
        for bus in buses
            if bus.number == d["storage_bus"]
                storage = create_battery_storage(bus, d)
                add_component!(sys, storage; skip_validation = PSY.SKIP_PM_VALIDATION)
            end
        end
    end
    return sys
end

"""
    build_system(case_file; config_file, generator_mapping, name, description)

Parse the MATPOWER-style network case `case_file` and construct a
`PowerSystems.System` for the 15-region SNEM ACDC model.

The `storage` table of the case is removed before system construction
(PowerSystems does not parse it from MATPOWER data) and re-attached as
`EnergyReservoirStorage` devices. Zero branch reactances are floored at
`1e-3` to avoid singular admittances, and fuel categories are normalised.

# Arguments
- `case_file`: path to the `.m` network case.
- `config_file`: PowerSystems struct-validation descriptor (defaults to the
  bundled `data/config/power_system_structs.json`).
- `generator_mapping`: fuel/type to device-type mapping YAML (defaults to
  the bundled `data/config/generator_mapping.yaml`).
- `name` / `description`: metadata stored on the returned system.

# Returns
`(sys, pm_data, base_storage_data)` where `pm_data` is the parsed
`PowerModelsData` (with storage removed) and `base_storage_data` is the
original storage table.
"""
function build_system(case_file::AbstractString;
        config_file::AbstractString = joinpath(default_data_dir(), "config", "power_system_structs.json"),
        generator_mapping::AbstractString = joinpath(default_data_dir(), "config", "generator_mapping.yaml"),
        name::AbstractString = "snem_15_regions",
        description::AbstractString = "15-regions SNEM ACDC model; this representation " *
            "is based on clustering data from 15 regions")
    isfile(case_file) || throw(ArgumentError("Network case not found: $case_file"))
    isfile(config_file) || throw(ArgumentError("Config file not found: $config_file"))
    isfile(generator_mapping) || throw(ArgumentError("Generator mapping not found: $generator_mapping"))

    @info "Parsing network case" case_file
    pm_data = PSY.PowerModelsData(case_file)

    # Keep the storage table aside: it is attached manually below.
    base_storage_data = deepcopy(get(pm_data.data, "storage", Dict()))
    delete!(pm_data.data, "storage")

    # Floor zero reactances to avoid singular branch admittances.
    for (_, branch) in pm_data.data["branch"]
        if branch["br_x"] == 0
            branch["br_x"] = 1E-3
        end
    end

    _remap_fuel_categories!(pm_data.data)

    sys = PSY.System(pm_data; frequency = 50, config_path = config_file,
        generator_mapping = generator_mapping)
    add_storage_from_dict!(sys, base_storage_data)

    sys.metadata.name = name
    sys.metadata.description = description
    @info "System constructed" name buses = length(get_components(ACBus, sys))
    return sys, pm_data, base_storage_data
end

"""
    save_case_file(pm_data, base_storage_data, out_file; case_name)

Export a network case (with the storage table re-attached) back to a
MATPOWER `.m` file in mixed units. Used to produce consolidated "final"
case files after modifications.
"""
function save_case_file(pm_data, base_storage_data::Dict, out_file::AbstractString;
        case_name::AbstractString = "snem_step_change_base_case_2044")
    for (kk, my_dict) in pm_data.data
        if my_dict isa Dict{Int64, Any}
            pm_data.data[kk] = stringify_keys(my_dict)
        end
    end
    for (_, vv) in base_storage_data
        vv["name"] = vv["duid"]
    end
    pm_data.data["storage"] = stringify_keys(base_storage_data)
    pm_data.data["name"] = case_name

    mkpath(dirname(abspath(out_file)))
    _PM.make_mixed_units!(pm_data.data)
    _PM.export_matpower(out_file, pm_data.data)
    @info "Exported network case" out_file
    return out_file
end
