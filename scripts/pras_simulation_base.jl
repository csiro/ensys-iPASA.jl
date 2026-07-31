#############################################################################
# PRAS simulation for the LT_BASE long-term scenario.
# Thin wrapper around scripts/pras_simulation.jl; sample count can be
# overridden with a second CLI argument or the IPASA_SAMPLES env var.
#
#   julia --project --threads auto scripts/pras_simulation_base.jl [SAMPLES]
#############################################################################

using Pkg
Pkg.activate("./")

# run first time to install dependencies
Pkg.instantiate()

using iPASA


samples = length(ARGS) >= 1 ? parse(Int, ARGS[1]) :
    parse(Int, get(ENV, "IPASA_SAMPLES", "100"))

setup_logging(joinpath("log", "pras_simulation_base.log"))
@info "Starting the application.." scenario = "LT_BASE" samples

# Note: source file needed = "/data/isp/output/2024_ISP_Step_Change_20yrs_scaled.csv"
# Since the raw AEMO ISP trace download (several GB) isn't in this repo, you'll need 
# to point scenario_dem_path/scenario_ren_path at your local copy and 
# re-run pre-processing_ISP_data.ipynb to actually regenerate 
# data/isp/output/2024_ISP_Step_Change_20yrs_scaled.csv before pras_simulation_base.jl (LT_BASE) will run.
# Alternatively, you can download the the pre-processed CSV file from CSIRO DAP using the following link:
# https://dap.csiro.au/dap/api/v1/asset/content/5e3     # TO DO update this link to point to the correct file once it is uploaded to DAP

run_scenario("LT_BASE"; samples = samples,
    output_dir = get(ENV, "IPASA_OUTPUT_DIR", nothing))

@info "Completed and exiting"
