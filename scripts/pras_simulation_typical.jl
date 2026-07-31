#############################################################################
# PRAS simulation for the LT_TYP long-term scenario.
# Thin wrapper around scripts/pras_simulation.jl; sample count can be
# overridden with a second CLI argument or the IPASA_SAMPLES env var.
#
#   julia --project --threads auto scripts/pras_simulation_typical.jl [SAMPLES]
#############################################################################

using Pkg
Pkg.activate("./")

# run first time to install dependencies
Pkg.instantiate()

using iPASA

samples = length(ARGS) >= 1 ? parse(Int, ARGS[1]) :
    parse(Int, get(ENV, "IPASA_SAMPLES", "100"))

setup_logging(joinpath("log", "pras_simulation_typical.log"))
@info "Starting the application.." scenario = "LT_TYP" samples

run_scenario("LT_TYP"; samples = samples,
    output_dir = get(ENV, "IPASA_OUTPUT_DIR", nothing))

@info "Completed and exiting"
