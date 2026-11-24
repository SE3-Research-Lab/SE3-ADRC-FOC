#!/bin/bash
## Submit scenarios from hpc_scenarios.m to Slurm.
##
## First time only: copy hpc.env.example to hpc.env (in this folder) and fill
## it in with your account, partition, time limit, memory and MATLAB module.
##
## Usage (from anywhere; the script finds the repository itself):
##     bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 1-19       scenarios 1 to 19
##     bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 3          only scenario 3
##     bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 1,4,7-9    a mix
##
## Optional, for a quick test or benchmark (put it in front of the command):
##     ADRC_STOP_TIME_OVERRIDE=0.01      simulate only this many seconds
##
## Results go to src/results/hpc/run_<date_time>/:
##     scenario_XX/                  one folder per scenario (.mat file, summary, figures)
##     logs/                         the Slurm output of every task
##     summary_all_scenarios.csv     written when all tasks are done

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: bash $0 <scenario numbers, for example 1-19>" >&2
    echo "Run preview_hpc_scenarios in MATLAB to see the numbered list." >&2
    exit 1
fi
SCENARIO_NUMBERS="$1"

# This script is in src/matlab/HPC-Scripts/slurm, so src is three folders up
SLURM_SCRIPTS_FOLDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_FOLDER="$(cd "${SLURM_SCRIPTS_FOLDER}/../../.." && pwd)"

# ---- Read the HPC settings ----------------------------------------------
HPC_SETTINGS_FILE="${SLURM_SCRIPTS_FOLDER}/hpc.env"
if [ ! -f "${HPC_SETTINGS_FILE}" ]; then
    echo "Missing ${HPC_SETTINGS_FILE}" >&2
    echo "Create it from the template and fill it in:" >&2
    echo "    cp ${SLURM_SCRIPTS_FOLDER}/hpc.env.example ${HPC_SETTINGS_FILE}" >&2
    exit 1
fi
# set -a exports every variable the file sets, so the Slurm jobs see them.
# tr removes Windows line endings in case the file was edited on Windows.
set -a
source <(tr -d '\r' < "${HPC_SETTINGS_FILE}")
set +a

# Every required setting must be filled in (not empty, not a <placeholder>)
for SETTING_NAME in ADRC_SLURM_ACCOUNT ADRC_SLURM_PARTITION ADRC_SLURM_TIME ADRC_SLURM_MEMORY ADRC_MATLAB_MODULE; do
    SETTING_VALUE="${!SETTING_NAME:-}"
    if [ -z "${SETTING_VALUE}" ] || [[ "${SETTING_VALUE}" == *"<"* ]]; then
        echo "Fill in ${SETTING_NAME} in ${HPC_SETTINGS_FILE} (it is \"${SETTING_VALUE}\")." >&2
        exit 1
    fi
done

# ---- Build the sbatch options from the settings ---------------------------
COMMON_OPTIONS=(--account="${ADRC_SLURM_ACCOUNT}" --partition="${ADRC_SLURM_PARTITION}" --export=ALL)

SCENARIO_OPTIONS=(--time="${ADRC_SLURM_TIME}" --mem="${ADRC_SLURM_MEMORY}"
                  --cpus-per-task="${ADRC_SLURM_CPUS_PER_TASK:-2}")
if [ -n "${ADRC_SLURM_MAIL_USER:-}" ]; then
    SCENARIO_OPTIONS+=(--mail-user="${ADRC_SLURM_MAIL_USER}" --mail-type="${ADRC_SLURM_MAIL_TYPE:-END,FAIL}")
fi

# Optional limit on how many scenarios run at the same time (the %N in 1-19%5)
ARRAY_SPECIFICATION="${SCENARIO_NUMBERS}"
if [ -n "${ADRC_SLURM_MAX_SIMULTANEOUS_TASKS:-}" ]; then
    ARRAY_SPECIFICATION="${SCENARIO_NUMBERS}%${ADRC_SLURM_MAX_SIMULTANEOUS_TASKS}"
fi

# ---- Submit ---------------------------------------------------------------
RUN_FOLDER="${SRC_FOLDER}/results/hpc/run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${RUN_FOLDER}/logs"

export ADRC_SRC_FOLDER="${SRC_FOLDER}"
export ADRC_RUN_FOLDER="${RUN_FOLDER}"
export ADRC_STOP_TIME_OVERRIDE="${ADRC_STOP_TIME_OVERRIDE:-}"

SCENARIO_JOB_ID=$(sbatch --parsable "${COMMON_OPTIONS[@]}" "${SCENARIO_OPTIONS[@]}" \
    --array="${ARRAY_SPECIFICATION}" \
    --output="${RUN_FOLDER}/logs/scenario_%a.out" \
    "${SLURM_SCRIPTS_FOLDER}/run_hpc_scenarios.sbatch")

COLLECT_JOB_ID=$(sbatch --parsable "${COMMON_OPTIONS[@]}" \
    --dependency=afterany:${SCENARIO_JOB_ID} \
    --output="${RUN_FOLDER}/logs/collect.out" \
    "${SLURM_SCRIPTS_FOLDER}/collect_hpc_results.sbatch")

echo "Submitted scenarios ${ARRAY_SPECIFICATION} as job ${SCENARIO_JOB_ID}"
echo "  account ${ADRC_SLURM_ACCOUNT}, partition ${ADRC_SLURM_PARTITION}, time ${ADRC_SLURM_TIME}, memory ${ADRC_SLURM_MEMORY}"
echo "Summary job ${COLLECT_JOB_ID} runs when they all finish."
echo "Results folder: ${RUN_FOLDER}"
echo
echo "Check progress:  squeue -u \$USER"
echo "After it ends:   sacct -j ${SCENARIO_JOB_ID} --format=JobID,State,Elapsed,MaxRSS"
