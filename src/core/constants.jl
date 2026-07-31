#############################################################################
# Constants shared across the package
#############################################################################

"Number of NEM sub-regions in the 15-region SNEM representation."
const N_REGIONS = 15

"Mapping of area number (as `Int`) to ISP sub-region code."
const AREA_CODE_REGION = Dict(
    1 => "NNSW", 2 => "CNSW", 3 => "SNW", 4 => "SNSW", 5 => "WNV",
    6 => "MEL", 7 => "SEV", 8 => "NQ", 9 => "CQ", 10 => "GG",
    11 => "SQ", 12 => "NSA", 13 => "CSA", 14 => "SESA", 15 => "TAS",
)

"Mapping of area number (as `String`) to ISP sub-region code (legacy form)."
const ZONE_DICT = Dict(string(k) => v for (k, v) in AREA_CODE_REGION)

"Grouping of the 15 sub-regions into the five NEM states used for
renewable resource traces (solar/wind/hydro are provided per state)."
const REN_DIST_DICT = Dict(
    "NSW" => [1, 2, 3, 4],
    "VIC" => [5, 6, 7],
    "QLD" => [8, 9, 10, 11],
    "SA" => [12, 13, 14],
    "TAS" => [15],
)

"""
Scenario identifiers supported by [`build_scenario_timeseries!`](@ref) and
[`run_scenario`](@ref).

* `"ST"`     - short term: one year (Jul 2024 - Jun 2025), 30-minute resolution
* `"MT"`     - medium term: six years (Jul 2024 - Jun 2030), 30-minute resolution
* `"LT"`     - long term: twenty years (Jul 2024 - Jun 2044), 60-minute resolution
  (variants such as `"LT_BASE"`, `"LT_TYP"`, `"LT_BEST"`, `"LT_WORST"` are
  treated as LT for data handling; the suffix selects the network case and
  labels the outputs)
* `"SUM_ED"` - summer extreme days sampled over Jul 2024 - Jun 2030
"""
const SUPPORTED_SCENARIOS = ["ST", "MT", "LT", "SUM_ED"]

"Timestamp format used in the bundled ISP CSV traces and log messages."
const DATE_FORMAT = "yyyy-mm-dd HH:MM:SS"

"System base power (MVA) used when constructing components."
const SYSTEM_BASE_MVA = 100.0

"""
    scenario_class(scenario::AbstractString)

Return the scenario family (`"ST"`, `"MT"`, `"LT"` or `"SUM_ED"`) for a
scenario label. Long-term variants such as `"LT_BASE"` or `"LT_WORST"`
all map to `"LT"`.

Throws an `ArgumentError` for unrecognised labels.
"""
function scenario_class(scenario::AbstractString)
    contains(scenario, "LT") && return "LT"
    scenario in SUPPORTED_SCENARIOS && return String(scenario)
    throw(ArgumentError(
        "Unknown scenario \"$scenario\". Supported scenarios: " *
        join(SUPPORTED_SCENARIOS, ", ") * " (plus LT_* variants)."))
end
