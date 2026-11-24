%% Run the traditional (open-loop) stepper model: OpenLoop_TraditionalStepper
% This model drives the same motor, PCB and ballscrew as the ADRC models,
% but the way a traditional stepper driver does. The driver switches the
% two phase voltages through a fixed sequence, one entry per step.
% Each step turns the rotor 1.8 degrees (full step) or 0.9 degrees
% (half step). Compare the results with the ADRC models to see what the
% closed-loop controller adds (for example, less ringing after each step).
%
% How the model works (see the "Full Step Sequence Generator" subsystem):
%   steps taken   = floor(time * step rate), stopped at the number of steps to move
%   sequence slot = mod(steps taken, steps in the sequence)
%   phase voltage = sequence table(sequence slot) * phase voltage level
% The two phase voltages then go through the same PWM generators the
% controller uses, into the plant.
%
% Steps:
%   1. Change the values in "Settings for this run" below.
%   2. Press Run. The script loads the plant constants, runs the model and
%      plots the results.
%
% Run time: the model steps every 5 ns. In accelerator mode, 10 ms of motor
% time takes roughly a minute (plus about a minute the first time, while
% Simulink builds the accelerated model).

clear;
clc;
close all hidden;

%% Settings for this run
model_name = 'OpenLoop_TraditionalStepper';
simulation_mode = 'accelerator';                        % 'accelerator' (faster) or 'normal' required MATLAB 2021B or newer 
save_figures = false;                                   % true = also save PDF/PNG/FIG files
show_figures = true;                                    % false = draw the figures hidden (no windows open)

% Drive mode: 'full step', 'wave', or 'half step'
%   full step : both phases on at all times (most torque), 1.8 degree steps
%   wave      : one phase on at a time (less torque), 1.8 degree steps
%   half step : alternates one and two phases on, 0.9 degree steps
drive_mode = 'full step';

step_rate_steps_per_second = 100;                       % how fast the driver steps
number_of_steps_to_move = 4;                            % the driver stops (and holds) after this many steps
step_direction = 1;                                     % 1 = forward, -1 = reverse
hold_time_after_move_seconds = 0.02;                    % keep simulating this long after the last step

%% Add every project folder to the MATLAB path
% setup_paths.m is in the src folder, two folders above this script.
this_script_folder = fileparts(mfilename('fullpath'));
source_folder = fullfile(this_script_folder, '..', '..');
run(fullfile(source_folder, 'setup_paths.m'));

%% Load the constants shared by every model
% This model has no ADRC controller, but its PWM generators are the same
% FPGA blocks the controller uses, and they need the fixed-point data types
% from controller_parameters.m.
plant_constants;                                        % motor, ballscrew, spring, PCB, encoder, load cell
controller_parameters;                                  % fixed-point data types (the ADRC gains are not used here)

% Spring on the nut, in lbf/in (0 = no spring)
spring_constant_lbf_per_inch = 15;
spring_constant = (spring_constant_lbf_per_inch * pound_force_to_newtons) / inches_to_meters;

% Extra load torque at the motor shaft: [time (s), torque (N*m)]
load_disturbance_data = [0 0; 1 0];

%% Driver settings: phase voltage, step sequence tables, logging
% (uses drive_mode and the step settings from the top of this script)
open_loop_stepper_parameters;

%% Simulate
time_to_finish_move_seconds = number_of_steps_to_move / step_rate_steps_per_second;
stop_time_seconds = time_to_finish_move_seconds + hold_time_after_move_seconds;

fprintf('Stepping %d steps (%s) at %g steps/s, simulating %g s (%s mode)...\n', ...
    number_of_steps_to_move, drive_mode, step_rate_steps_per_second, stop_time_seconds, simulation_mode);
load_system(model_name);               % use open_system(model_name) to also see the diagram
simulation_timer = tic;
simOut = sim(model_name, 'StopTime', num2str(stop_time_seconds), 'SimulationMode', simulation_mode);
fprintf('Done in %.1f minutes.\n', toc(simulation_timer) / 60);

%% Plot
plot_options.title_text = sprintf('Traditional stepper drive (%s, %g steps/s)', drive_mode, step_rate_steps_per_second);
plot_options.ballscrew_lead_mm = ballscrew_lead_mm;
plot_options.current_limit_amps = motor_peak_current_amps;
plot_options.holding_torque_newton_meters = T_holding;
plot_options.file_name_prefix = 'OpenLoop_TraditionalStepper';
plot_options.show_figures = show_figures;
if save_figures
    plot_options.save_folder = fullfile(source_folder, 'results', 'local', model_name);
else
    plot_options.save_folder = '';
end
plot_simulation_results(simOut, plot_options);
