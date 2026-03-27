#!/bin/sh
#SBATCH -A OD-223474
#SBATCH --output=stdout_output.txt  # Redirect standard output
#SBATCH --error=stderr_errors.txt   # Redirect standard error
#SBATCH --job-name=smcs_benchmark
#SBATCH --time=05:00:00
#SBATCH --nodes=1
#SBATCH --partition=cfd
#SBATCH --ntasks=10
#SBATCH --cpus-per-task 1
#SBATCH --mem=190g

cd /datasets/work/en-energy-sys/work/users/bal246/REPO/github/ensys-arpst-RAAssessment

export JULIA_DEPOT_PATH="/datasets/work/en-energy-sys/work/users/bal246/JULIA_EV_1111"
module load julia/1.11.1

export JULIA_NUM_THREADS=auto
echo "Job started at: $(date)"

julia --project --threads auto  pras_simulation.jl > simulation_output.txt 2>&1 

echo "Intermediate timestamp: $(date)"

