#!/bin/bash
## Runs scenarios from hpc_scenarios.m as a Slurm job array: one task per
## scenario, all at the same time. Do not submit this file directly; use
##     bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 1-19
## from the src folder of the cloned repository.
##
## The account, partition, time limit, memory and e-mail come from hpc.env
## (copy hpc.env.example to hpc.env and fill it in). submit_hpc_scenarios.sh
## passes them to sbatch, because #SBATCH lines cannot read variables.

#SBATCH --job-name=adrc_scenario
#SBATCH --nodes=1
#SBATCH --ntasks=1

set -euo pipefail

# Set by submit_hpc_scenarios.sh
: "${ADRC_SRC_FOLDER:?Submit with submit_hpc_scenarios.sh}"
: "${ADRC_RUN_FOLDER:?Submit with submit_hpc_scenarios.sh}"

# Read the HPC settings again (for ADRC_MATLAB_MODULE). tr removes Windows
# line endings in case hpc.env was edited on a Windows computer.
HPC_SETTINGS_FILE="${ADRC_SRC_FOLDER}/matlab/HPC-Scripts/slurm/hpc.env"
set -a
source <(tr -d '\r' < "${HPC_SETTINGS_FILE}")
set +a

module load "${ADRC_MATLAB_MODULE}"

echo "Scenario ${SLURM_ARRAY_TASK_ID} on $(hostname), started $(date)"
cd "${ADRC_SRC_FOLDER}"
matlab -batch "addpath('${ADRC_SRC_FOLDER}/matlab/HPC-Scripts'); run_hpc_scenario(${SLURM_ARRAY_TASK_ID}, '${ADRC_RUN_FOLDER}')"
echo "Finished $(date)"
