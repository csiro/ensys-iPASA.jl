#############################################################################
# Production-cost (unit commitment) simulation with PowerSimulations.jl
#
# These routines support the ST/MT PASA-style production-cost runs used
# for cross-checking the PRAS adequacy results (see
# notebooks/power_simulation_res.ipynb).
#############################################################################

"""
    get_uc_template()

Build the standard unit-commitment `ProblemTemplate` on a copper-plate
network with slacks: full renewable dispatch, static loads, thermal unit
commitment, storage dispatch with reserves, run-of-river hydro, static AC
branches/transformers and dispatched two-terminal HVDC lines.
"""
function get_uc_template()
    template = ProblemTemplate(NetworkModel(CopperPlatePowerModel; use_slacks = true))
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
    PSI.set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)
    PSI.set_device_model!(template, DeviceModel(Line, StaticBranch))
    PSI.set_device_model!(template, DeviceModel(TwoTerminalHVDCLine, HVDCTwoTerminalDispatch))
    return template
end

"""
    formulate_decision_model(sys::System, pasa; mip_gap=0.05, optimizer=nothing)

Transform the single time series of `sys` into the deterministic forecast
window required for the PASA horizon and build the decision model:

* `pasa == "ST"`: half-hourly resolution, 48-hour window advanced daily;
* `pasa == "MT"`: daily resolution, 365-day window advanced daily.

Uses HiGHS with relative MIP gap `mip_gap` unless another `optimizer` is
supplied. Returns the built `DecisionModel`.
"""
function formulate_decision_model(sys::System, pasa::AbstractString;
        mip_gap::Real = 0.05, optimizer = nothing)
    if pasa == "ST"
        PSY.transform_single_time_series!(sys, Hour(48), Hour(24))
    elseif pasa == "MT"
        PSY.transform_single_time_series!(sys, Day(365), Day(1), resolution = Day(1))
    else
        throw(ArgumentError("pasa must be \"ST\" or \"MT\", got \"$pasa\""))
    end
    template = get_uc_template()
    solver = optimizer === nothing ?
        optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => mip_gap) : optimizer
    problem = DecisionModel(template, sys; optimizer = solver,
        name = "SNEM-SYS", allow_fails = true)
    build!(problem; output_dir = mktempdir(; cleanup = true))
    return problem
end

"""
    run_production_simulation(sys, pasa, name, steps;
                              initial_time=DateTime("2025-01-10T00:00:00"),
                              simulation_folder=mktempdir(; cleanup=true))

Build and execute a PowerSimulations sequential simulation of the
unit-commitment decision model over `steps` steps. Returns the
`Simulation` object; pass it to [`extract_simulation_data`](@ref) to
collect generation/load/storage results.
"""
function run_production_simulation(sys::System, pasa::AbstractString,
        name::AbstractString, steps::Integer;
        initial_time::DateTime = DateTime("2025-01-10T00:00:00"),
        simulation_folder::AbstractString = mktempdir(; cleanup = true))
    steps >= 1 || throw(ArgumentError("steps must be >= 1, got $steps"))
    problem = formulate_decision_model(sys, pasa)
    models = SimulationModels(; decision_models = [problem])
    sequence = SimulationSequence(;
        models = models,
        ini_cond_chronology = InterProblemChronology(),
    )
    sim = Simulation(;
        name = name,
        steps = steps,
        models = models,
        sequence = sequence,
        initial_time = initial_time,
        simulation_folder = simulation_folder,
    )
    build!(sim)
    execute!(sim, enable_progress_bar = true)
    return sim
end

"""
    extract_simulation_data(sim; generator_mapping_file=nothing)

Post-process an executed simulation: aggregate generation by fuel
category, compute storage charging/discharging/stored energy and total
load, and return everything merged into a single `DataFrame` indexed by
timestamp.

`generator_mapping_file` is forwarded to
`PowerAnalytics.make_fuel_dictionary` when provided; otherwise the
PowerAnalytics default fuel mapping is used.
"""
function extract_simulation_data(sim;
        generator_mapping_file::Union{Nothing, AbstractString} = nothing)
    sim_result = SimulationResults(sim)
    uc_results = get_decision_problem_results(sim_result, "SNEM-SYS")

    gen = PA.get_generation_data(uc_results, curtailment = false)
    sys_1 = PA.PSI.get_system(uc_results)
    cat = generator_mapping_file === nothing ?
        PA.make_fuel_dictionary(sys_1, curtailment = false) :
        PA.make_fuel_dictionary(sys_1, curtailment = false,
            generator_mapping_file = generator_mapping_file)
    fuel = PA.categorize_data(gen.data, cat; curtailment = false)

    gas = sum.(eachrow(fuel["Natural Gas CC"]))
    hydro = sum.(eachrow(fuel["Hydropower"]))
    PV = sum.(eachrow(fuel["PV"]))
    Battery = sum.(eachrow(fuel["Battery"]))
    Wind = sum.(eachrow(fuel["Wind"]))
    Coal = sum.(eachrow(fuel["Coal"]))
    numeric_cols = names(fuel["Unserved Energy"], Not("DateTime"))
    unserved_energy = sum.(eachrow(fuel["Unserved Energy"][!, numeric_cols]))
    numeric_cols = names(fuel["Over Generation"], Not("DateTime"))
    over_gen = sum.(eachrow(fuel["Over Generation"][!, numeric_cols]))
    fuel_mix = DataFrame(timestamp = fuel["Over Generation"][!, "DateTime"],
        gas = gas, Coal = Coal, hydro = hydro, PV = PV, Battery = Battery,
        Wind = Wind, unserved_energy = unserved_energy, over_gen = over_gen)

    load = PA.get_load_data(uc_results)
    load_agg = PA.combine_categories(load.data)

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
    )
    df[!, "load"] = load_agg[:, "Load"]
    merged_df = innerjoin(fuel_mix, df, on = :timestamp => :DateTime)
    return merged_df
end
