# ADRC stepper model: 20-scenario sweep on MSU Tempest

These files run all 20 load scenarios as one Slurm **job array**. Each scenario runs as its own MATLAB process at the same time, so the whole sweep takes about as long as the slowest single run. Each run saves a `.mat` file and publication figures. A dependent job then builds a summary table and comparison figures.

These scripts need `simulink/ADRC-model/HPC_Compatible_FirstOrderADRC.slx`, the two files in `simulink/ADRC-model/subsystems/` (`adrc_harness.slx`, `PWM_Generator.slx`) and `matlab/Local-Scripts/MFP_ADRC_1st_params_multirate.m` on the MATLAB path. Run `setup_paths` in `src/` to add them. When copying to the cluster, copy the whole `src/` folder so this layout is kept.

| File | Purpose |
|---|---|
| `adrc_params.m` | Your V2 constants, without `clear`/`clc`. It also sets defaults for the new disturbance and logging variables. **Edit model constants here.** |
| `runFirstOrderADRCMultiRateClock_V3.m` | Desktop entry point, used the same way as V2 (it calls `adrc_params`). |
| `hpc_config.m` | **All sweep settings**: springs, disturbance sizes, stop-time estimate, logged signal names, plot style. |
| `scenario_table.m` | Builds the 20 scenarios from `adrc_params` and `hpc_config`. |
| `make_disturbance.m` | Impulse, step and Gaussian load torque at random times. Each scenario uses a fixed seed, so runs are reproducible. |
| `prepare_models.m` | **One-time** model edits: adds the disturbance input, sets logging decimation and saves backups. |
| `preview_scenarios.m` | Prints the table and plots the disturbance profiles. No simulation needed. |
| `run_scenario.m` | Runs one scenario end to end: parameters, accelerator build, simulation, `.mat` file, figures. |
| `plot_scenario.m`, `pub_*.m` | Publication figures for one run (vector PDF, 300-dpi PNG and editable `.fig`). |
| `collect_results.m` | Summary CSV and comparison figures across all runs. |
| `slurm/*.sbatch`, `slurm/submit_all.sh` | Tempest job scripts. |

## The 20 scenarios

These defaults assume a cruise speed of 100 rad/s. Stop times are recomputed after you change `omega_cruise_est`.

| ID | Spring (lbf/in) | Command | Load at target | Disturbance | Model time |
|---|---|---|---|---|---|
| 1 | 0 | +141 rev (705 mm) | 0 | none | 11.6 s |
| 2 | 10 | 237.7 rev (115 % of the predicted slip point, 1033 mm) | stalls | none | 20.2 s |
| 3 | 0 | same as 2 | 0 | none | 20.2 s |
| 4–11 | 12, 15, 20, 25, 30, 40, 60, 100 | 120.6 → 14.5 rev | 70 % of 1.6 N·m | none | 10.0 → 1.6 s |
| 12–19 | same springs and targets | same | 70 % + disturbance | impulse, gaussian, step, gaussian, impulse, gaussian, step, gaussian | same |
| 20 | 0 | −141 rev | 0 | none | 11.6 s |

- **Slip force.** The model converts nut force to shaft torque with `lead/(2π·η)`. So 1.6 N·m holding torque equals **1809.6 N** at the nut.
- **Disturbances** are added to the load torque at the motor shaft. Event times are drawn at random between 10 % and 90 % of the run.
  - **Impulse:** five pulses of 0.40 N·m (25 % of holding torque), each 2 ms wide.
  - **Step:** 0.24 N·m (15 %), held until the end of the run.
  - **Gaussian:** standard deviation 0.08 N·m (5 %), resampled every 0.1 ms, switched on at a random time.

  With the 70 % spring load, the worst case stays below the 1.6 N·m limit, so the disturbed runs measure disturbance rejection rather than slip. All of these sizes are set in `hpc_config.m`.

## Step by step

### 1. On your PC, before going to the cluster

```matlab
preview_scenarios          % check the table, warnings and disturbance plots
prepare_models             % one-time: backs up and edits both models
setenv('ADRC_STOP_TIME','0.002'); res = run_scenario(12); setenv('ADRC_STOP_TIME','');
```

`prepare_models` prints three things:

- **Which blocks use `theta_ref`, `stepTime` and `spring_constant`.** This confirms the overrides reach the model.
- **What it added to `adrc_harness`.** It inserts a Sum between the `ballscrew_travel_per_force` gain and the motor's TL input. The other Sum input is a From Workspace block that reads `load_disturbance_data`. The disturbance is also logged as `log_load_disturbance_a`. `log_motor_torque_a` now records spring plus disturbance torque.
- **The decimation it set on every To Workspace block.** Each block logs every ~20 µs instead of every 5 ns step. Without this, a 10 s run would try to keep about 2×10⁹ samples per signal.

The short test run prints `Logged variables:` and `Not found:`. If a signal you need is listed as not found, add its real variable name to `cfg.sig` in `hpc_config.m`. Open `results/local/scenario_12/figures/S12_summary.pdf` to check the layout.

### 2. Copy the project to Tempest

Connect to the MSU VPN, then copy the whole folder:

```bash
rsync -av --exclude slprj --exclude '*.slxc' --exclude results ./ <netid>@tempest-login.msu.montana.edu:~/adrc/
```

### 3. Pick the MATLAB version and account

```bash
ssh <netid>@tempest-login.msu.montana.edu
cd ~/adrc
module spider matlab        # or: module avail matlab
```

The models were saved in your desktop release, so use a Tempest module that is the **same release or newer**. If the default `math/matlab` is older, set it before submitting:

```bash
export ADRC_MATLAB_MODULE=math/matlab/R2025b   # example: use a name the command above lists
```

In `slurm/run_scenarios.sbatch` and `slurm/collect.sbatch`, replace `priority-<group_name>` with your account. In `slurm/benchmark.sbatch`, replace `group-<group_name>`. Run `sacctmgr show assoc user=$USER format=account%30` if you are unsure of the names.

### 4. Benchmark (one hour, test partition)

```bash
mkdir -p logs && sbatch slurm/benchmark.sbatch
cat logs/adrc_bench_<jobid>.out
```

This simulates 0.01 s of scenario 1 at full fidelity. It then prints the projected wall time of each scenario and a suggested `#SBATCH --time`. Put that value in `run_scenarios.sbatch`. The `priority` partition allows up to 14 days.

Also look at the velocity figure from the benchmark or a longer local run. Set `cfg.omega_cruise_est` to the speed the motor actually cruises at, so the stop times are neither too short nor wasteful.

### 5. Submit everything

```bash
bash slurm/submit_all.sh
squeue -u $USER
sacct -j <arrayid> --format=JobID,State,Elapsed,MaxRSS
```

Results appear in `results/run_<arrayid>/`:

```
scenario_01/scenario_01.mat           scenario, sig, metrics, P, info  (-v7.3)
scenario_01/figures/S01_summary.pdf   position | load torque | iq & iq*
scenario_01/figures/S01_velocity.pdf  ... currents_dq, angle, loadcell, torque_iq
scenario_01/ERROR.txt                 only if the run failed
summary/summary_metrics.csv           one row per scenario
summary/cmp_slip_vs_noload.pdf        scenario 2 vs 3
summary/cmp_springs_position.pdf      8 springs, undisturbed vs disturbed
summary/cmp_disturbance_deviation.pdf position change caused by each disturbance
summary/cmp_forward_reverse.pdf       scenario 1 vs 20
summary/cmp_final_error.pdf           final error vs spring rate
```

To re-run a single failed scenario, use `sbatch --array=7 slurm/run_scenarios.sbatch`. It writes to a new `run_<id>` folder; move its `scenario_07` folder into the original run folder, then run `collect.sbatch` for that folder.