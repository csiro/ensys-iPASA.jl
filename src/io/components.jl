#############################################################################
# PowerSystems.jl component constructors
#
# These helpers build individual PowerSystems.jl devices from row
# dictionaries read out of the future generation / storage CSV files
# (see `data/sc_data/*.csv`).
#############################################################################

"""
    calculate_gen_rating(act, react, base_conversion)

Compute an apparent-power rating `sqrt(act^2 + react^2) * base_conversion`
for a generator. Returns `1.0` when both inputs are zero so that
downstream per-unit conversions never divide by zero.
"""
function calculate_gen_rating(act::Real, react::Real, base_conversion::Real)
    rating = sqrt(act^2 + react^2)
    if rating == 0.0
        return 1.0
    end
    return rating * base_conversion
end

"""
    create_hydro_dispatch(d::Dict, bus::ACBus)

Build a `HydroDispatch` device from a row dictionary `d` with keys
`name`, `mbase`, `pg`, `qg`, `pmin`, `pmax`, `qmin`, `qmax`.
Power values are converted from the device base (`mbase`) to the
system base of $(SYSTEM_BASE_MVA) MVA.
"""
function create_hydro_dispatch(d::Dict, bus::ACBus)
    base_conversion = SYSTEM_BASE_MVA / d["mbase"]
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
            min = d["pmin"] * base_conversion,
            max = d["pmax"] * base_conversion,
        ),
        reactive_power_limits = (
            min = d["qmin"] * base_conversion,
            max = d["qmax"] * base_conversion,
        ),
        ramp_limits = (up = abs(d["pmax"]), down = abs(d["pmax"])),
        time_limits = nothing,
        operation_cost = HydroGenerationCost(nothing),
        base_power = d["mbase"],
    )
end

"""
    create_thermal_gen(d::Dict, bus::ACBus)

Build a `ThermalStandard` device from a row dictionary `d`. The fuel is
inferred from `d["fuel"]`: natural gas maps to a combined-cycle unit and
coal to a steam turbine.

Throws an `ArgumentError` for unrecognised fuel categories.
"""
function create_thermal_gen(d::Dict, bus::ACBus)
    base_conversion = SYSTEM_BASE_MVA / d["mbase"]
    rating = calculate_gen_rating(d["pmax"], d["qmax"], base_conversion)
    if d["fuel"] == "naturalgas"
        prime_mover_type = PrimeMovers.CC
        fuel_cat = ThermalFuels.NATURAL_GAS
    elseif d["fuel"] == "blackcoal" || d["fuel"] == "browncoal"
        prime_mover_type = PrimeMovers.ST
        fuel_cat = ThermalFuels.COAL
    else
        throw(ArgumentError(
            "Unknown fuel category \"$(d["fuel"])\" for generator \"$(d["name"])\""))
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
        active_power_limits = (min = d["pmin"] * base_conversion, max = d["pmax"] * base_conversion),
        reactive_power_limits = (min = d["qmin"] * base_conversion, max = d["qmax"] * base_conversion),
        time_limits = nothing,
        ramp_limits = (up = abs(d["pmax"]), down = abs(d["pmax"])),
        operation_cost = ThermalGenerationCost(nothing),
        base_power = d["mbase"],
    )
end

"""
    create_renewable_dispatch(d::Dict, bus::ACBus)

Build a `RenewableDispatch` device (solar PV or wind, including offshore
wind and renewable energy zone entries) from a row dictionary `d` with a
`fuel_type` key of `"solar"`, `"wind"` or `"offshore_wind"`.
"""
function create_renewable_dispatch(d::Dict, bus::ACBus)
    base_conversion = SYSTEM_BASE_MVA / d["mbase"]
    rating = calculate_gen_rating(d["pmax"], d["qmax"], base_conversion)
    fuel_type = lowercase(d["fuel_type"])
    if fuel_type == "solar"
        prime_mover_type = PrimeMovers.PVe
    elseif fuel_type == "wind" || fuel_type == "offshore_wind"
        prime_mover_type = PrimeMovers.WT
    else
        throw(ArgumentError(
            "Unknown renewable fuel type \"$(d["fuel_type"])\" for \"$(d["name"])\""))
    end
    return RenewableDispatch(
        name = d["name"],
        available = true,
        bus = bus,
        active_power = d["pmax"] * base_conversion,
        reactive_power = d["qmax"] * base_conversion,
        rating = rating,
        prime_mover_type = prime_mover_type,
        reactive_power_limits = (min = d["qmin"] * base_conversion, max = d["qmax"] * base_conversion),
        power_factor = 1.0,
        operation_cost = RenewableGenerationCost(nothing),
        base_power = d["mbase"],
    )
end

"""
    make_res_storage(d::Dict, bus::ACBus)

Build an `EnergyReservoirStorage` battery device from a *future storage*
row dictionary `d` (keys `name`, `energy`, `energy_rating`,
`charge_efficiency`). Quantities are converted to per-unit on the
$(SYSTEM_BASE_MVA) MVA system base. When `energy_rating` is zero the
power rating `energy` is used as the energy capacity.
"""
function make_res_storage(d::Dict, bus::ACBus)
    energy_rating = iszero(d["energy_rating"]) ? d["energy"] : d["energy_rating"]
    base_power = SYSTEM_BASE_MVA
    pu_power = d["energy"] / base_power
    return EnergyReservoirStorage(;
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
end

"""
    create_battery_storage(bus::ACBus, d::Dict)

Build an `EnergyReservoirStorage` battery device from a *MATPOWER base
case* storage dictionary `d` (keys `duid`, `energy`, `energy_rating`,
`charge_efficiency`, `discharge_efficiency`). Used when re-attaching the
storage table parsed out of the network `.m` file.
"""
function create_battery_storage(bus::ACBus, d::Dict)
    act_power = d["energy"]
    name = d["duid"]
    storage_cap = d["energy_rating"]
    base_power = SYSTEM_BASE_MVA
    in_eff = d["charge_efficiency"]
    out_eff = d["discharge_efficiency"]
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
