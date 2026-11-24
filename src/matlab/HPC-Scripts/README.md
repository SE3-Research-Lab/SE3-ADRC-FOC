# Running the models on the HPC (MSU Tempest)

You clone this repository onto the cluster, list the simulations you want in **`hpc_scenarios.m`**, and submit them with one command. Each scenario runs as its own Slurm task, and all tasks run at the same time. Any of the four models can be used:

- `HPC_Compatible_FirstOrderADRC`
- `DataCollection_FirstOrderADRC`
- `FPGA_Compatible_FirstOrderADRC`
- `OpenLoop_TraditionalStepper`

| File | What it does |
|---|---|
| `hpc_scenarios.m` | **The list of scenarios. Edit this.** Each scenario sets the model, stop time, displacement, spring, disturbance, ADRC tuning and stepper settings. |
| `preview_hpc_scenarios.m` | Prints the numbered list with a rough run-time estimate. Nothing is simulated. |
| `run_hpc_scenario.m` | Runs one scenario and saves the `.mat` file, a summary and the figures. Each Slurm task calls it. |
| `make_load_disturbance.m` | Builds the step, impulse or noise load torque for a scenario. |
| `collect_hpc_results.m` | Gathers every scenario's summary into `summary_all_scenarios.csv`. Runs automatically after the scenarios finish. |
| `slurm/submit_hpc_scenarios.sh` | **The one command you run on the cluster.** It submits the scenarios and the summary job. |
| `slurm/hpc.env.example` | **Template for your cluster settings** (Slurm account, partition, time limit, memory, MATLAB module, e-mail). Copy it to `slurm/hpc.env` and fill that in. `hpc.env` is git-ignored, so your settings stay private. |
| `slurm/run_hpc_scenarios.sbatch`, `slurm/collect_hpc_results.sbatch` | The Slurm job files. They read their settings from `hpc.env`, so you don't need to edit them. |
| `archive/old_pipeline_2026-11/` | The earlier pipeline (`adrc_params`, `hpc_config`, `run_scenario`, ...), kept for reference. |

Every scenario uses the same constants as the local runs: `matlab/Local-Scripts/plant_constants.m` and `controller_parameters.m`. A scenario only changes the values it lists, so there is one place to change a motor or controller constant.

## 1. Choose the scenarios (on your PC)

Open `hpc_scenarios.m`. Every scenario starts from `default_scenario` and changes only what it needs:

```matlab
scenario = default_scenario;
scenario.name = 'Spring 20 lbf/in, step disturbance';
scenario.model_name = 'HPC_Compatible_FirstOrderADRC';
scenario.spring_constant_lbf_per_inch = 20;
scenario.commanded_displacement_mm = 100;
scenario.disturbance_type = 'step';
scenario.disturbance_size_newton_meters = 0.24;
scenario.disturbance_start_time_seconds = 1.5;
scenario.velocity_closed_loop_bandwidth_rad_per_second = 600;
scenario.stop_time_seconds = 2.0;
scenarios = add_scenario(scenarios, scenario);
```

A value left as `[]` uses the normal value from `plant_constants.m` or `controller_parameters.m`. Groups of scenarios (a spring sweep, a bandwidth sweep) are made with a simple `for` loop; see the examples in the file.

Then check the list:

```matlab
preview_hpc_scenarios
```

It prints each scenario's number (the number Slurm uses), its settings and a rough wall-time estimate. The estimate uses speeds measured on the lab PC: about 50 minutes of wall time per second of motor time in accelerator mode.

**Quick test on your PC** (2 ms of motor time, no figure windows, takes about 30 s):

```matlab
run_hpc_scenario(5, 'results/local_test', 0.002)
```

Then look in `results/local_test/scenario_05/`.

## 2. Put the repository on the cluster (first time only)

Connect to the MSU VPN, then:

```bash
ssh <netid>@tempest-login.msu.montana.edu
git clone <repository URL> SE3-ADRC-FOC
cd SE3-ADRC-FOC/src
```

After you change files on your PC and push them, update the cluster copy with `git pull`.

**Create your settings file.** Every cluster-specific value is in one file, `slurm/hpc.env`, which is never committed:

```bash
cp matlab/HPC-Scripts/slurm/hpc.env.example matlab/HPC-Scripts/slurm/hpc.env
chmod 600 matlab/HPC-Scripts/slurm/hpc.env      # only you can read it
nano matlab/HPC-Scripts/slurm/hpc.env            # fill it in
```

The settings it needs (each one is explained in the file):

| Setting | What to put | How to find it |
|---|---|---|
| `ADRC_SLURM_ACCOUNT` | Slurm account to charge | `sacctmgr show assoc user=$USER format=account%30` |
| `ADRC_SLURM_PARTITION` | `priority` (14 days, `priority-<group>` account), `nextgen` (3 days, `group-<group>` account) or `unsafe` (7 days, can be preempted) | |
| `ADRC_SLURM_TIME` | Time limit per scenario, longer than the longest scenario | `preview_hpc_scenarios` prints an estimate |
| `ADRC_SLURM_MEMORY` | Memory per scenario, `16G` to start | Raise it if a task fails with `OUT_OF_MEMORY` |
| `ADRC_MATLAB_MODULE` | MATLAB module, R2026a or newer (the models are saved in R2026a) | `module avail matlab` |
| Optional | CPUs per task, the maximum number of scenarios running at once, e-mail notifications | |

`submit_hpc_scenarios.sh` reads (sources) `hpc.env`. It stops with a message if the file is missing or a required setting still has its `<placeholder>`. The Slurm jobs read it again when they start. The file can be edited on Windows: Windows line endings are removed when it is read.

## 3. Benchmark (recommended before a big run)

Run one scenario for 0.01 s of motor time to measure how fast the cluster is:

```bash
ADRC_STOP_TIME_OVERRIDE=0.01 bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 1
```

When it ends, the log (`results/hpc/run_<date_time>/logs/scenario_1.out`) shows `Simulation done in X minutes`. Multiply X by 100 to get the minutes per second of motor time, and use that to set `ADRC_SLURM_TIME` in `hpc.env`.

## 4. Submit

From the `src` folder of the repository on the cluster:

```bash
bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 1-19        # all scenarios
bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 3            # just one
bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 1,4,7-9      # a mix
```

Then watch the jobs:

```bash
squeue -u $USER                                            # what is running or waiting
sacct -j <job id> --format=JobID,State,Elapsed,MaxRSS      # after it ends: time and memory used
```

## 5. Results

Everything from one submission goes into `src/results/hpc/run_<date_time>/`:

```
logs/scenario_5.out              MATLAB output of scenario 5 (look here first if something failed)
scenario_05/scenario_05.mat      simOut (every logged signal), scenario, summary
scenario_05/scenario_05_summary.txt
scenario_05/figures/S05_*.pdf|png|fig    the same figures as the local run scripts
scenario_05/ERROR.txt            only if the scenario failed: the full error message
summary_all_scenarios.csv        one row per scenario: settings, final position error, run time
```

To copy results to your PC, run this on your PC:

```bash
scp -r <netid>@tempest-login.msu.montana.edu:SE3-ADRC-FOC/src/results/hpc/run_<date_time> .
```

To re-plot a saved run on your PC without simulating again:

```matlab
loaded = load('scenario_05.mat');
plot_options.title_text = loaded.scenario.name;
plot_options.ballscrew_lead_mm = 5;
plot_options.current_limit_amps = 4.243;
plot_options.holding_torque_newton_meters = 1.6;
plot_options.save_folder = '';
plot_options.file_name_prefix = 'S05';
plot_options.show_figures = true;
plot_simulation_results(loaded.simOut, plot_options);
```

To re-run one failed scenario, submit just its number. It goes into a new `run_<date_time>` folder.

## Good to know

- **Accelerator mode** uses Simulink's built-in JIT compiler, so the cluster does not need a C compiler. If the accelerated build still fails, the task automatically falls back to normal mode (slower) and records that in its summary (`simulation_mode`).
- **The `motor_torque` variable is the load torque.** The plant logs it from `Load Torque Sum`: the spring torque plus the disturbance at the motor shaft. It is not the motor's electromagnetic torque. The figures and summary label it as load torque.
- **The FPGA model logs only the plant** (load torque and disturbance), so its figures and position summary are limited. Use the Data Collection model, which computes the same controller, when you need more signals.
- **Line endings.** `slurm/.gitattributes` keeps the Slurm scripts in Linux format. If a script fails on the cluster with `$'\r': command not found`, run `sed -i 's/\r$//' matlab/HPC-Scripts/slurm/*`.
- `src/results/` and `hpc.env` are in the repository's `.gitignore`, so results and your cluster settings are never committed.
