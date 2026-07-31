# Shared setup for the iPASA test suite.

using iPASA
using Test

using CSV
using DataFrames
using Dates
using TimeSeries

import PowerSystems
const PSY = PowerSystems

# Bundled data shipped with the package.
const DATA_DIR = iPASA.default_data_dir()
const SC_DIR = joinpath(DATA_DIR, "sc_data")
const ISP_DIR = joinpath(DATA_DIR, "isp", "output")
const BASE_CASE = joinpath(SC_DIR, "snem_step_change_base_case_2044-final.m")

# Set IPASA_TEST_SKIP_SYSTEM=true to skip the (slow) full-system and PRAS
# integration tests, e.g. on small CI runners.
const SKIP_SYSTEM_TESTS = lowercase(get(ENV, "IPASA_TEST_SKIP_SYSTEM", "false")) == "true"

# Number of Monte Carlo samples used in the fast integration test. Keep
# this tiny: production runs use >= 100 samples via the scripts.
const TEST_SAMPLES = parse(Int, get(ENV, "IPASA_TEST_SAMPLES", "2"))

"Build a small synthetic normalised trace DataFrame for unit tests."
function synthetic_norm_df(; n = 48)
    timestamps = collect(DateTime(2024, 7, 1):Minute(30):(DateTime(2024, 7, 1) + Minute(30) * (n - 1)))
    return DataFrame(
        timestamp = timestamps,
        NSW_demand = 100 .+ rand(n) .* 50,
        NSW_Solar = rand(n),
        NSW_Wind = rand(n),
        NSW_hydro = rand(n),
    )
end
