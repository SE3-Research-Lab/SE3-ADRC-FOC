#!/bin/bash
## Builds summary_all_scenarios.csv after every scenario task has finished.
## submit_hpc_scenarios.sh queues this automatically (with the account and
## partition from hpc.env). To run it by hand from the src folder:
##     source matlab/HPC-Scripts/slurm/hpc.env
##     ADRC_SRC_FOLDER=$PWD ADRC_RUN_FOLDER=$PWD/results/hpc/run_<date_time> \
##         sbatch --account=$ADRC_SLURM_ACCOUNT --partition=$ADRC_SLURM_PARTITION \
##         --output=results/hpc/run_<date_time>/logs/collect.out matlab/HPC-Scripts/slurm/collect_hpc_results.sbatch

#SBATCH --job-name=adrc_collect
#SBATCH --time=01:00:00
#SBATCH --mem=8G
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1

set -euo pipefail
: "${ADRC_SRC_FOLDER:?Set ADRC_SRC_FOLDER to the src folder of the repository}"
: "${ADRC_RUN_FOLDER:?Set ADRC_RUN_FOLDER to the results/hpc/run_... folder}"

HPC_SETTINGS_FILE="${ADRC_SRC_FOLDER}/matlab/HPC-Scripts/slurm/hpc.env"
set -a
source <(tr -d '\r' < "${HPC_SETTINGS_FILE}")
set +a

module load "${ADRC_MATLAB_MODULE}"
cd "${ADRC_SRC_FOLDER}"
matlab -batch "addpath('${ADRC_SRC_FOLDER}/matlab/HPC-Scripts'); collect_hpc_results('${ADRC_RUN_FOLDER}')"
