#############################################################################
# iPASA.jl
# Integrated Probabilistic Assessment of System Adequacy (iPASA)
#
# A Julia package for resource-adequacy assessment of the Australian
# National Electricity Market (NEM) built on the Sienna ecosystem
# (PowerSystems.jl, PowerSimulations.jl) and PRAS.
#############################################################################

module iPASA

import PowerModels

using PowerSystems
using PRAS
using SiennaPRASInterface
using PowerSimulations
using PowerAnalytics
using StorageSystemsSimulations
using HydroPowerSimulations
using HiGHS
using JuMP

using CSV
using DataFrames
using DataStructures
using Dates
using Logging
using LoggingExtras
using NPZ
using Tables
using TimeSeries

import DataStructures: SortedDict

# Short aliases, PowerModels.jl-style
const _PM = PowerModels
const PSY = PowerSystems
const PSI = PowerSimulations
const PA = PowerAnalytics

# Root of the installed package; used to resolve the bundled data directory.
const _PKG_ROOT = normpath(joinpath(@__DIR__, ".."))

"Default directory holding bundled network cases, configs and ISP traces."
default_data_dir() = joinpath(_PKG_ROOT, "data")

# core
include("core/constants.jl")
include("core/logging.jl")

# io: parsing network cases and constructing PowerSystems.jl systems
include("io/components.jl")
include("io/system.jl")
include("io/augment.jl")

# data: ISP time-series ingestion and attachment
include("data/timeseries.jl")

# prob: problem specifications (PRAS adequacy assessment, production cost)
include("prob/pras.jl")
include("prob/production_cost.jl")

# util: result extraction, exports, generic helpers
include("util/common.jl")
include("util/results.jl")
include("util/export.jl")

# --- Public API ---------------------------------------------------------
# core
export setup_logging, default_data_dir
export AREA_CODE_REGION, REN_DIST_DICT, N_REGIONS, SUPPORTED_SCENARIOS

# io / system construction
export build_system, add_baseload!, add_future_generators!, add_future_storage!,
    add_retirement_status!

# time series
export build_scenario_timeseries!, load_scaled_data, normalise_data,
    normalize_to_range, build_time_series

# PRAS assessment
export generate_pras_model, apply_storage_timeseries!, run_pras_assessment,
    run_scenario, default_ra_template

# production-cost simulation
export get_uc_template, formulate_decision_model, run_production_simulation,
    extract_simulation_data

# results / exports
export save_shortfall_eue_metrics, save_shortfall_time_series_data,
    save_generator_storage_data, save_pras_lines_info, save_line_capacity,
    get_pras_lines, get_pras_regional_loads, flow_utilisation,
    save_system_snapshot

# generic helpers
export scenario_class, stringify_keys, find_region

end # module iPASA
