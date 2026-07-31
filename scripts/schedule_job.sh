#!/bin/sh
# SLURM batch job for running iPASA PRAS simulations on an HPC cluster.
# Adjust the account, partition, repository path and JULIA_DEPOT_PATH to
# your environment before submitting with `sbatch scripts/schedule_job.sh`.
#SBATCH -A OD-223474
#SBATCH --output=stdout_output.txt  # Redirect standard output
#SBATCH --error=stderr_errors.txt   # Redirect standard error
#SBATCH --job-name=ipasa_pras
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --partition=cfd
#SBATCH --ntasks=10
#SBATCH --cpus-per-task 1
#SBATCH --mem=396g

# Path to the iPASA repository checkout.
cd "${IPASA_REPO:-$HOME/iPASA}"

# Shared Julia depot (package cache) on the cluster.
export JULIA_DEPOT_PATH="${JULIA_DEPOT_PATH:-$HOME/.julia}"
module load julia/1.11.1

export JULIA_NUM_THREADS=auto
echo "Job started at: $(date)"

# Select the scenario to run (LT_BASE, LT_TYP, LT_BEST, LT_WORST, ST, MT, SUM_ED)
SCENARIO="${IPASA_SCENARIO:-LT_TYP}"
SAMPLES="${IPASA_SAMPLES:-100}"

julia --project --threads auto scripts/pras_simulation.jl "$SCENARIO" "$SAMPLES" \
    > "simulation_output_${SCENARIO}.txt" 2>&1

echo "Job finished at: $(date)"
