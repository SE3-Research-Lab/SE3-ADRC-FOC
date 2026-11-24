# Stepper motor FOC with ADRC: models and scripts

This folder holds the Simulink models and MATLAB scripts for a stepper motor driven by field-oriented control (FOC). Velocity and current are controlled by first-order active disturbance rejection controllers (ADRC). The controller is written in fixed point so it can be turned into HDL for an FPGA.

## Quick start

Open one of the run scripts in `matlab/Local-Scripts/` and press **Run**. Each one adds the project folders to the path, loads every constant, runs its model and plots the results:

| Script | Model | 10 ms of motor time takes |
|---|---|---|
| `run_DataCollection_model.m` | `DataCollection_FirstOrderADRC` | ~0.5 min (accelerator) |
| `run_HPC_Compatible_model.m` | `HPC_Compatible_FirstOrderADRC` (short local check) | ~0.5 min (accelerator) |
| `run_FPGA_Compatible_model.m` | `FPGA_Compatible_FirstOrderADRC` | ~4–5 min (normal mode) |
| `run_OpenLoop_TraditionalStepper_model.m` | `OpenLoop_TraditionalStepper` | ~1.3 min for its default 60 ms test |

Change the test (stop time, commanded steps, spring, disturbance) in the "Settings for this run" and "Change the test for this run" sections at the top of each script. Set `save_figures = true` to also save PDF/PNG/FIG files to `results/local/<model>/`.

The constants live in two shared scripts that every run script calls:

- `plant_constants.m`: the hardware (motor, ballscrew, spring, PCB, encoder, load cell).
- `controller_parameters.m`: the ADRC tuning (bandwidths, position gain), loop rates, iq\* limit and fixed-point types. It must run after `plant_constants.m`. At its end it runs `design_adrc_gains.m`, which turns the tuning into the coefficients the model uses. If you change a tuning value afterwards, run `design_adrc_gains` again.

Set `show_figures = false` in a run script to draw the figures without opening windows. They are still saved when `save_figures = true`.

Each value has a long descriptive name, followed by the short name the Simulink blocks use (for example `motor_phase_resistance_ohms`, then `r`). The plots come from `matlab/Plotting-Scripts/plot_simulation_results.m`, which takes a `simOut` and draws the same figures, in the same style, as the HPC pipeline.

The models run with a 5 ns fixed step, so keep local runs short; long runs go on the HPC.

## Folder layout

```
src/
├─ setup_paths.m          adds the folders below to the MATLAB path (archive folders excluded)
├─ matlab/
│  ├─ HPC-Scripts/        run any model on the cluster: hpc_scenarios.m (the list of runs),
│  │                      run_hpc_scenario.m, slurm/. See its README.md
│  ├─ Local-Scripts/      run_*_model.m, plant_constants.m, controller_parameters.m,
│  │  │                   ADRC gain design, tuning sweep
│  │  └─ archive/         superseded scripts, second-order ADRC scripts
│  └─ Plotting-Scripts/   plot_simulation_results.m (any simOut), older publication plots
├─ simulink/
│  ├─ pid-model/          (empty, reserved for a PID baseline model)
│  ├─ open-loop-stepper-model/
│  │                      OpenLoop_TraditionalStepper.slx: same plant, driven like a
│  │                      traditional stepper (full/wave/half step, no feedback)
│  └─ ADRC-model/
│     ├─ FPGA_Compatible_FirstOrderADRC.slx
│     ├─ DataCollection_FirstOrderADRC.slx
│     ├─ HPC_Compatible_FirstOrderADRC.slx
│     ├─ subsystems/      adrc_harness.slx (plant), PWM_Generator.slx
│     ├─ docs/            sync_report.md: how the three models were made to match
│     └─ archive/         older models, test bench, model_backups/
├─ hdl/                   HDL Coder IP core generated earlier (adrc_axi_ctrl); predates the current model
├─ constraints/           FPGA constraints (placeholder)
└─ results/               output of HPC/local sweep runs
```

## The three ADRC models

All three compute exactly the same controller. On 2026-11-23 they were verified bit-exact against each other over 10 ms (61 signals); see `simulink/ADRC-model/docs/sync_report.md`. They differ only in what they log and how they are prepared:

| Model | Use it for | Logging |
|---|---|---|
| `HPC_Compatible_FirstOrderADRC` | Long runs on the cluster (`matlab/HPC-Scripts`; any model can run there) | Only the final signals, decimated to about 20 µs |
| `DataCollection_FirstOrderADRC` | Short local runs (~10 ms) to check data | Same To Workspace set as HPC, decimated more |
| `FPGA_Compatible_FirstOrderADRC` | The model that goes to HDL. DUT: `Stepper Motor FOC Controller` | No Scope or To Workspace blocks. Log with signal logging instead |

**If you change the controller math, change it in all three models**, then re-run the comparison in `docs/sync_report.md`.

All three use the same two subsystem files in `subsystems/`, so an edit there changes every model:

- `adrc_harness.slx`: the plant (PCB, ADC emulation, encoder, stepper motor, ballscrew/spring load, load disturbance input). Phase current is limited to ±4.243 A, the motor's peak rating.
- `PWM_Generator.slx`: the PWM generator used four times inside the controller.

## Open-loop (traditional) stepper model

`OpenLoop_TraditionalStepper` drives the same plant and PWM generators as the ADRC models, but with no feedback, the way a classic stepper driver does. Inside its `Full Step Sequence Generator` subsystem:

- the number of steps taken is `floor(time × step rate)`, held once it reaches `number_of_steps_to_move`;
- that count picks a column of the step sequence table;
- the table sets each phase to +V, −V or off.

The phase voltage is the motor's rated current times its resistance (2.7 V, a classic L/R drive). The plant outputs phase current as ADC counts, so the `ADC Counts to Amps` subsystem converts them to amps for the plots. The drive mode, step rate, step count and direction are set at the top of `run_OpenLoop_TraditionalStepper_model.m`. The model is an update of the old `archive/runStepperMotor_TestBench.slx`, which drove the phases with two 48 V sine waves and logged every 5 ns sample.

## Parameters

There are no data dictionaries or model callbacks. Every constant comes from the base workspace:

- **Every run, local and HPC:** `matlab/Local-Scripts/plant_constants.m` and `controller_parameters.m` (with `design_adrc_gains.m`). The run scripts and the HPC runner call them, so a constant is changed in one place. For all 47 variables the models use, they give values bit-identical to the earlier `adrc_params.m` (checked 2026-11-23).
- **HPC scenarios** change only the values they list (spring, displacement, disturbance, ADRC tuning, stepper settings); see `matlab/HPC-Scripts/hpc_scenarios.m`.
- The earlier cluster parameter script, `adrc_params.m`, is in `matlab/HPC-Scripts/archive/old_pipeline_2026-11/`.
- `matlab/Local-Scripts/runFirstOrderADRCMultiRateClock_V2.m` is the original script the two shared scripts were made from. It does not set `load_disturbance_data`, which the plant needs.
- All of them call `MFP_ADRC_1st_params_multirate.m` (in `Local-Scripts`) to compute the ADRC gains.

Key rates:
- `Ts_sim` = 5 ns (200 MHz FPGA clock);
- `Ts_current` = 20 µs (current loops);
- `Ts_velocity` = 400 µs (velocity loop, entered through Rate Transitions).

## Known open items (FPGA)

The FPGA model is HDL-ready for the KR260 (`checkhdl`: 0 errors; IP core generation passes; 0 cycles of added latency; gains are AXI4-Lite registers with a commit strobe). Details, the register map and the checklist are in `simulink/ADRC-model/docs/hdl_readiness_report.md`. Still open:

- **Vivado:** run `matlab/FPGA-Scripts/generate_fpga_ip_core.m` on the machine with Vivado, add the IP core to the KR260 block design, then synthesize and check timing and resource use (DSP slices, the 128-bit encoder velocity path).
- **HDL simulation:** run the generated validation model or testbench with an HDL simulator (none is installed on the Windows PC).
- **HPC and Data Collection models:** they still have the old controller math. The report lists the changes to copy over.

## Notes

- The archive folders are not on the path on purpose. `archive/PWM_Generator_v1p11_unused.slx` is an older copy that used to shadow the real one.
- `matlab_workspace.mat`, `slprj/` and the `*.slxc` files in `src/` are left over from earlier sessions and builds. The `.slxc` files are Simulink caches and can be deleted.
