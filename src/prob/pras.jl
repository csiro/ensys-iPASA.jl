#############################################################################
# PRAS resource-adequacy assessment
#############################################################################

"""
    default_ra_template()

Return the default `RATemplate` mapping PowerSystems device types onto
PRAS model formulations: AC and HVDC lines as PRAS lines, static loads as
PRAS loads, thermal/renewable/hydro generators as PRAS generators and
battery storage as lossless energy reservoirs. Regions are aggregated by
`Area`.
"""
function default_ra_template()
    device_models = [
        DeviceRAModel(PSY.Line, LinePRAS),
        DeviceRAModel(PSY.TwoTerminalHVDCLine, LinePRAS),
        DeviceRAModel(PSY.StaticLoad, StaticLoadPRAS),
        DeviceRAModel(PSY.ThermalGen, GeneratorPRAS),
        DeviceRAModel(PSY.RenewableGen, GeneratorPRAS),
        DeviceRAModel(PSY.HydroDispatch, GeneratorPRAS),
        DeviceRAModel(PSY.EnergyReservoirStorage, EnergyReservoirLossless),
    ]
    return RATemplate(PSY.Area, device_models)
end

"""
    generate_pras_model(sys::System; template=default_ra_template())

Translate a PowerSystems `System` into a PRAS `SystemModel` using
`SiennaPRASInterface.generate_pras_system`.
"""
function generate_pras_model(sys::System; template = default_ra_template())
    @info "Generating PRAS model.."
    gps = generate_pras_system(sys, template)
    @info "PRAS model created" regions = length(gps.regions) generators = length(gps.generators) storages = length(gps.storages) lines = length(gps.lines)
    return gps
end

"""
    apply_storage_timeseries!(gps, sys::System)

Scale the energy/charge/discharge capacities of every storage device in
the PRAS model `gps` by its `max_active_power` time series from `sys`.

This works around PowerSystems not applying scaling factors to storage
power/energy limits, so commissioning-status series (see
[`add_retirement_status!`](@ref)) take effect in the PRAS model.
"""
function apply_storage_timeseries!(gps, sys::System)
    for (i, kk) in enumerate(gps.storages.names)
        comp_data = get_component(EnergyReservoirStorage, sys, kk)
        if comp_data === nothing || !PSY.has_time_series(comp_data)
            @warn "No max_active_power time series for storage; capacities left unscaled" name = kk
            continue
        end
        ts_data = get_time_series(SingleTimeSeries, comp_data, "max_active_power").data
        gps.storages.energy_capacity[i, :] = gps.storages.energy_capacity[i, :] .* values(ts_data)
        gps.storages.charge_capacity[i, :] = gps.storages.charge_capacity[i, :] .* values(ts_data)
        gps.storages.discharge_capacity[i, :] = gps.storages.discharge_capacity[i, :] .* values(ts_data)
    end
    @info "Storage time series applied to the PRAS model"
    return gps
end

"""
    run_pras_assessment(gps; samples=100, seed=123, threaded=true)

Run a PRAS `SequentialMonteCarlo` adequacy assessment on the PRAS system
`gps` and return a `NamedTuple` of results with fields:

`shortfall`, `surplus`, `flow`, `utilization`, `storage_energy`,
`gs_energy` (generator-storage energy), `gen_availability`,
`line_availability`, `storage_availability`, `gs_availability`.

Reduce `samples` (e.g. to 2-5) for quick smoke tests; production studies
typically use 100 or more samples.
"""
function run_pras_assessment(gps; samples::Integer = 100, seed::Integer = 123,
        threaded::Bool = true)
    samples >= 1 || throw(ArgumentError("samples must be >= 1, got $samples"))
    resultspecs = (Shortfall(), Surplus(), Flow(), Utilization(), StorageEnergy(),
        GeneratorStorageEnergy(), GeneratorAvailability(), LineAvailability(),
        StorageAvailability(), GeneratorStorageAvailability())
    @info "Running PRAS simulation" samples seed threaded
    method = SequentialMonteCarlo(samples = samples, seed = seed, threaded = threaded)
    shortfall_rs, surplus_rs, flow_rs, util_rs, energy, gs_energy, ga, la, sa, gsa =
        assess(gps, method, resultspecs...)
    @info "PRAS simulation done"
    return (shortfall = shortfall_rs, surplus = surplus_rs, flow = flow_rs,
        utilization = util_rs, storage_energy = energy, gs_energy = gs_energy,
        gen_availability = ga, line_availability = la, storage_availability = sa,
        gs_availability = gsa)
end

"""
    default_case_file(scenario; sc_dir=joinpath(default_data_dir(), "sc_data"))

Return the network case path for `scenario`. LT variants map to their
dedicated step-change case (`typical`/`best`/`worst`); everything else
uses the base case. If a variant case is missing from `sc_dir`, the base
case is used with a warning.
"""
function default_case_file(scenario::AbstractString;
        sc_dir::AbstractString = joinpath(default_data_dir(), "sc_data"))
    base = joinpath(sc_dir, "snem_step_change_base_case_2044-final.m")
    variant = if contains(scenario, "TYP")
        joinpath(sc_dir, "snem_step_change_typical_case_2044.m")
    elseif contains(scenario, "BEST")
        joinpath(sc_dir, "snem_step_change_best_case_2044.m")
    elseif contains(scenario, "WORST")
        joinpath(sc_dir, "snem_step_change_worst_case_2044.m")
    else
        base
    end
    if !isfile(variant)
        @warn "Scenario case file not found; falling back to base case" scenario missing_case = variant
        variant = base
    end
    return variant
end

"""
    run_scenario(scenario; case_file=default_case_file(scenario),
                 data_dir=default_data_dir(), output_dir=nothing,
                 samples=100, seed=123, threaded=true, save_outputs=true)

End-to-end iPASA pipeline for one scenario:

1. build the SNEM system from the MATPOWER case ([`build_system`](@ref));
2. apply base loads and add future generators/storage with their
   commissioning/retirement status series;
3. attach the ISP demand/solar/wind/hydro traces for the scenario;
4. translate to a PRAS model and apply storage status series;
5. run the sequential Monte Carlo adequacy assessment;
6. optionally save shortfall/EUE metrics, flow/utilisation series and
   generator/storage data to `output_dir` (defaults to
   `data/pras_metrics_output/shortfall_data/<scenario>`).

Returns `(sys = ..., gps = ..., results = <NamedTuple>)`.

# Example
```julia
using iPASA
out = run_scenario("ST"; samples = 5)         # quick smoke run
out = run_scenario("LT_BASE"; samples = 100)  # production run (slow)
```
"""
function run_scenario(scenario::AbstractString;
        case_file::AbstractString = default_case_file(scenario),
        data_dir::AbstractString = default_data_dir(),
        output_dir::Union{Nothing, AbstractString} = nothing,
        samples::Integer = 100, seed::Integer = 123, threaded::Bool = true,
        save_outputs::Bool = true)
    sclass = scenario_class(scenario)  # validates the label early
    sc_dir = joinpath(data_dir, "sc_data")
    isp_dir = joinpath(data_dir, "isp", "output")

    @info "Starting iPASA scenario run" scenario case_file samples

    sys, pm_data, base_storage_data = build_system(case_file)

    add_baseload!(sys, sc_dir)
    add_future_generators!(sys, sclass, sc_dir)
    add_future_storage!(sys, sclass, sc_dir)
    add_retirement_status!(sys, sclass, joinpath(sc_dir, "future_gen_thermal_exp_pp.csv"), "gen")
    add_retirement_status!(sys, sclass, joinpath(sc_dir, "future_storage_pp.csv"), "storage")
    @info "Added thermal generators and storage status time series"

    build_scenario_timeseries!(sys, scenario; isp_dir = isp_dir)

    gps = generate_pras_model(sys)
    apply_storage_timeseries!(gps, sys)

    results = run_pras_assessment(gps; samples = samples, seed = seed, threaded = threaded)

    if save_outputs
        odir = output_dir === nothing ?
            joinpath(data_dir, "pras_metrics_output", "shortfall_data", scenario) :
            String(output_dir)
        mkpath(odir)
        @info "Saving PRAS simulation outputs" odir
        save_shortfall_eue_metrics(gps, results.shortfall, scenario, odir)
        save_shortfall_time_series_data(scenario, results.shortfall, gps,
            results.flow, results.utilization, odir)
        save_generator_storage_data(results.gen_availability, gps,
            results.storage_energy, scenario, odir)
        @info "Saved PRAS time series metrics data"
    end

    @info "Scenario run completed" scenario
    return (sys = sys, gps = gps, results = results)
end
