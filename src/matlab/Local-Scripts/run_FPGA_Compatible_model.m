%% Run the FPGA model: FPGA_Compatible_FirstOrderADRC
% This is the model that HDL Coder turns into FPGA logic. The part that
% becomes hardware is the "Stepper Motor FOC Controller" subsystem. It
% computes exactly the same controller as the HPC and Data Collection
% models.
%
% The controller has no Scope or To Workspace blocks, because those cause
% problems in HDL generation. Only the plant ("PCB and physical system
% model") logs data, so the plots show the motor torque and the load
% disturbance. To see more, run the Data Collection model, which computes
% the same thing.
%
% Steps:
%   1. Change the values in "Settings for this run" below.
%   2. Press Run. The script loads every constant, runs the model and plots
%      the results.
%
% Run time: this model is saved in normal mode. 10 ms of motor time
% (2 million steps of 5 ns) takes about 4 to 5 minutes.

clear;
clc;
close all hidden;

%% Settings for this run
model_name = 'FPGA_Compatible_FirstOrderADRC';
stop_time_seconds = 0.01;                               % how much motor time to simulate
simulation_mode = 'normal';                             % 'normal' or 'accelerator'
save_figures = false;                                   % true = also save PDF/PNG/FIG files
show_figures = true;                                    % false = draw the figures hidden (no windows open)

%% Add every project folder to the MATLAB path
% setup_paths.m is in the src folder, two folders above this script.
this_script_folder = fileparts(mfilename('fullpath'));
source_folder = fullfile(this_script_folder, '..', '..');
run(fullfile(source_folder, 'setup_paths.m'));

%% Load the constants shared by every model
% Later, these constants will be sent to the FPGA over the AXI bus instead.
plant_constants;                                        % motor, ballscrew, spring, PCB, encoder, load cell
controller_parameters;                                  % ADRC gains, loop rates, current limit, data types

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
plot_options.title_text = 'FPGA model';
plot_options.ballscrew_lead_mm = ballscrew_lead_mm;
plot_options.current_limit_amps = Iq_limit;
plot_options.holding_torque_newton_meters = T_holding;
plot_options.file_name_prefix = 'FPGA_Compatible';
plot_options.show_figures = show_figures;
if save_figures
    plot_options.save_folder = fullfile(source_folder, 'results', 'local', model_name);
else
    plot_options.save_folder = '';
end
plot_simulation_results(simOut, plot_options);
