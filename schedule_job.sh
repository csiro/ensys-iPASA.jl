#!/bin/sh
#SBATCH -A OD-223474
#SBATCH --output=stdout_output.txt  # Redirect standard output
#SBATCH --error=stderr_errors.txt   # Redirect standard error
#SBATCH --job-name=smcs_typ_2
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --partition=cfd
#SBATCH --ntasks=10
#SBATCH --cpus-per-task 1
#SBATCH --mem=396g

cd /datasets/work/en-energy-sys/work/users/bal246/REPO/github/ensys-arpst-RAAssessment

export JULIA_DEPOT_PATH="/datasets/work/en-energy-sys/work/users/bal246/JULIA_EV_1111"
module load julia/1.11.1

export JULIA_NUM_THREADS=auto
echo "Job started at: $(date)"

julia --project --threads auto  pras_simulation_typical.jl > simulation_output_typ.txt 2>&1 
#julia --project --threads auto  pras_simulation_best.jl > simulation_output_best.txt 2>&1 
#julia --project --threads auto  pras_simulation_worst.jl > simulation_output_worst_2.txt 2>&1 
#julia --project --threads auto  pras_simulation.jl > simulation_output_base.txt 2>&1 

echo "Intermediate timestamp: $(date)"

