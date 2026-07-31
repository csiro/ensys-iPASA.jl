#############################################################################
# Generic PRAS resource-adequacy simulation driver.
#
# Usage:
#   julia --project --threads auto scripts/pras_simulation.jl [SCENARIO] [SAMPLES]
#
#   SCENARIO  one of ST, MT, SUM_ED, LT_BASE, LT_TYP, LT_BEST, LT_WORST
#             (default: LT_BASE)
#   SAMPLES   number of Monte Carlo samples (default: 100; use a small
#             number such as 2 for a quick smoke test)
#
# Environment overrides:
#   IPASA_SAMPLES     same as the SAMPLES argument
#   IPASA_OUTPUT_DIR  output directory for the PRAS metrics CSVs
#############################################################################

using iPASA

function main(args)
    scenario = length(args) >= 1 ? args[1] : "LT_BASE"
    samples = length(args) >= 2 ? parse(Int, args[2]) :
        parse(Int, get(ENV, "IPASA_SAMPLES", "100"))
    output_dir = get(ENV, "IPASA_OUTPUT_DIR", nothing)

    setup_logging(joinpath("log", "pras_simulation_$(lowercase(scenario)).log"))
    @info "Starting the application.." scenario samples

    run_scenario(scenario; samples = samples, output_dir = output_dir)

    @info "Completed and exiting"
end

main(ARGS)
