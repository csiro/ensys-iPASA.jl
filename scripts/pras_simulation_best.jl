using PowerSystems
using CSV
using HDF5
using DataFrames
using Dates
using PRAS
using JuMP
using PowerModels
using PowerSimulations
using PowerSystemCaseBuilder
using PowerNetworkMatrices
using StorageSystemsSimulations
using HiGHS
using TimeSeries
using Dates: DateTime
using Logging
using LoggingExtras
using DataStructures
using PowerModelsACDC, Ipopt
import InfrastructureSystems
#const IS = InfrastructureSystems
#import InfrastructureModels as _IM

#Logging.disable_logging(Logging.Warn)
PowerModels.silence()

import DataStructures: SortedDict
const PSY = PowerSystems
#const PSI = PowerSimulations
#const PSB = PowerSystemCaseBuilder
#const PNM = PowerNetworkMatrices
const date_format = "yyyy-mm-dd HH:MM:SS"

ENV["TMPDIR"] = "/tmp"

include("src/utility.jl")
include("src/pras_utility.jl")

# Choose your scenarios, Currently it supports ST (one year 2024-25, 30 minutes resolution)
# MT (six years 2024 to 2030 30 minutes reslution), LT (20 years 2024 to 2044 60 minutes resolution) 
# and SUM_ED (summer extreme days for MT scenario) 

scenario = "LT_BEST"

# Define the log file path
logfile_path = "log/pras_simulation_best.log"

# Create a FileLogger for the log file
file_logger = FileLogger(logfile_path)

# Create a TransformerLogger to add timestamps to messages
# This function modifies the log message to include the current timestamp
timestamp_transformer = TransformerLogger(file_logger) do log
  merge(log, (; message = "$(Dates.format(now(), date_format)) $(log.message)"))
end

# Combine loggers with TeeLogger
# This sends logs to both the console and the timestamped file logger
global_logger(timestamp_transformer)

@info "Starting the application.."
file_path = joinpath(pwd(), "../../../data", "sc_data", "snem_step_change_best_case_2044.m")
sys, pm_data, base_storage_data = initialise_system_v3(file_path)
println("system loaded")
# Add future generators and storage


location = joinpath(pwd(), "data", "sc_data")
add_baseload(sys, scenario, location)

if contains(scenario, "LT")
    add_future_gen(sys, "LT", location)
    add_future_storage(sys, "LT", location)
    file_path = joinpath(location, "future_gen_thermal_exp_pp.csv")
    add_future_status_therm_stor(sys, "LT", file_path, "gen")
    file_path = joinpath(location, "future_storage_pp.csv")
    add_future_status_therm_stor(sys, "LT", file_path, "storage")
else
    add_future_gen(sys, scenario, location)
    add_future_storage(sys, scenario, location)
    file_path = joinpath(location, "future_gen_thermal_exp_pp.csv")
    add_future_status_therm_stor(sys, scenario, file_path, "gen")
    file_path = joinpath(location, "future_storage_pp.csv")
    add_future_status_therm_stor(sys, scenario, file_path, "storage")
end
println("Added thermal generators and storage time series data")

if scenario == "ST"
    time_series_data = built_load_one_yearly_TSdata(sys)
elseif scenario == "MT"
    time_series_data = built_load_six_yearly_TSdata(sys)    
elseif contains(scenario, "LT")
    time_series_data = built_load_twenty_years_TSdata(sys)
elseif scenario == "SUM_ED"
    time_series_data = built_load_SUM_ED_TSdata(sys)
end
println("time series data added to the system for the scenario: ", scenario)

#PSY.set_units_base_system!(sys, PSY.UnitSystem.NATURAL_UNITS)
using SiennaPRASInterface

const DEFAULT_DEVICE_MODELS_ST = [
    DeviceRAModel(PSY.Line, LinePRAS),
    DeviceRAModel(PSY.TwoTerminalHVDCLine, LinePRAS),
    DeviceRAModel(PSY.StaticLoad, StaticLoadPRAS),
    DeviceRAModel(PSY.ThermalGen, GeneratorPRAS),
    DeviceRAModel(PSY.RenewableGen, GeneratorPRAS),
    DeviceRAModel(PSY.HydroDispatch, GeneratorPRAS),
    DeviceRAModel(PSY.EnergyReservoirStorage, EnergyReservoirLossless),
]
const DEFAULT_TEMPLATE = RATemplate(PSY.Area, DEFAULT_DEVICE_MODELS_ST)
@info "Generating PRAS model.."

gps = generate_pras_system(sys, DEFAULT_TEMPLATE)
println("PRAS model - GPS - is created")

# Modify the storage capacities directly with the storage time series, as PowerSystems has not
# implemented the scaling to the active power limits, etc.

for (i, kk) in enumerate(gps.storages.names)
    comp_data = get_component(EnergyReservoirStorage, sys, kk)
    ts_data = get_time_series(SingleTimeSeries, comp_data, "max_active_power")
    ts_data = ts_data.data
    gps.storages.energy_capacity[i,:] = gps.storages.energy_capacity[i,:] .* values(ts_data)
    gps.storages.charge_capacity[i,:] = gps.storages.charge_capacity[i,:] .* values(ts_data)
    gps.storages.discharge_capacity[i,:] = gps.storages.discharge_capacity[i,:] .* values(ts_data)
end
println("storage time series added into the gps")

#save_pras_lines_limits(gps)
@info "Running PRAS simulation"

resultspecs = (Shortfall(), Surplus(), Flow(), Utilization(), StorageEnergy(),
    GeneratorStorageEnergy(),GeneratorAvailability(), LineAvailability(), StorageAvailability(),
    GeneratorStorageAvailability())
smallsample = SequentialMonteCarlo(samples=100, seed=123, threaded=true)
shortfall_rs, surplus_rs, flow_rs, util_rs, energy, gs_energy, ga, la, sa, gsa =
        assess(gps, smallsample, resultspecs...)
println("PRAS simulation done")
@info "PRAS simulation done"

odir = joinpath(pwd(), "../../../data", "ISP_data", "pras_metrics_output", "shortfall_data", scenario)
mkpath(odir)
@info "Saving data of PRAS simulation to the output directory " odir

use_df = save_shortfall_eue_metrics(gps, shortfall_rs, scenario, odir)
println("Unserved energy during shortfall time extracted")
save_shortfall_time_series_data(scenario, shortfall_rs, gps, flow_rs, util_rs, odir)
save_generator_storage_data(ga, gps, energy, scenario, odir)

println("Saved PRAS time series metrics data")
@info "Completed and exiting"
