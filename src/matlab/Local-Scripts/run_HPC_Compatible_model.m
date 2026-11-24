%% Run the HPC model on this computer: HPC_Compatible_FirstOrderADRC
% The HPC model is the one the cluster (MSU Tempest) runs for long load
% tests. It computes exactly the same controller as the Data Collection and
% FPGA models. It logs fewer signals, so long runs fit in memory.
%
% Use this script for a SHORT local check of the HPC model, for example
% after you change it and before you copy it to the cluster. For the real
% 20-scenario sweep, use the scripts in matlab/HPC-Scripts (see the
% README.md there).
%
% Steps:
%   1. Change the values in "Settings for this run" below.
%   2. Press Run. The script loads every constant, runs the model and plots
%      the results.
%
% Run time: the model steps every 5 ns, so 10 ms is 2 million steps. In
% accelerator mode, expect a minute or two (plus about a minute the first
% time, while Simulink builds the accelerated model).

clear;
clc;
close all hidden;

%% Settings for this run
model_name = 'HPC_Compatible_FirstOrderADRC';
stop_time_seconds = 0.01;                % how much motor time to simulate
simulation_mode = 'accelerator';         % 'accelerator' (faster) or 'normal'
save_figures = false;                    % true = also save PDF/PNG/FIG files
show_figures = true;                     % false = draw the figures hidden (no windows open)

%% Add every project folder to the MATLAB path
% setup_paths.m is in the src folder, two folders above this script.
this_script_folder = fileparts(mfilename('fullpath'));
source_folder = fullfile(this_script_folder, '..', '..');
run(fullfile(source_folder, 'setup_paths.m'));

%% Load the constants shared by every model
plant_constants;          % motor, ballscrew, spring, PCB, encoder, load cell
controller_parameters;    % ADRC gains, loop rates, current limit, data types

%% Change the test for this run (optional)
% Commanded move: a step to this many motor steps (200 steps = 1 revolution)
commanded_motor_steps = 200;
theta_ref = commanded_motor_steps * 1.8 * pi / 180;

% Spring on the nut, in lbf/in (0 = no spring)
spring_constant_lbf_per_inch = 15;
spring_constant = (spring_constant_lbf_per_inch * pound_force_to_newtons) / inches_to_meters;

% Extra load torque at the motor shaft: [time (s), torque (N*m)]
load_disturbance_data = [0 0; 1 0];

%% Simulate
fprintf('Simulating %s for %g s of motor time (%s mode)...\n', model_name, stop_time_seconds, simulation_mode);
load_system(model_name);               % use open_system(model_name) to also see the diagram
simulation_timer = tic;
simOut = sim(model_name, 'StopTime', num2str(stop_time_seconds), 'SimulationMode', simulation_mode);
fprintf('Done in %.1f minutes.\n', toc(simulation_timer) / 60);

%% Plot
plot_options.title_text = 'HPC model (local run)';
plot_options.ballscrew_lead_mm = ballscrew_lead_mm;
plot_options.current_limit_amps = Iq_limit;
plot_options.holding_torque_newton_meters = T_holding;
plot_options.file_name_prefix = 'HPC_Compatible';
plot_options.show_figures = show_figures;
if save_figures
    plot_options.save_folder = fullfile(source_folder, 'results', 'local', model_name);
else
    plot_options.save_folder = '';
end
plot_simulation_results(simOut, plot_options);
