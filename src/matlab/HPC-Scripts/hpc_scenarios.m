function scenarios = hpc_scenarios()
%% The list of HPC scenarios: EDIT THIS FILE to choose what the cluster runs
% Every scenario is one simulation. On the cluster, each scenario runs as
% its own Slurm task, all at the same time. Scenario numbers start at 1 and
% follow the order they are added below.
%
% How to add a scenario:
%   1. Start from the defaults:      scenario = default_scenario;
%   2. Change only what you need:    scenario.spring_constant_lbf_per_inch = 20;
%   3. Add it to the list:           scenarios = add_scenario(scenarios, scenario);
%
% To see the numbered list (and a rough run-time estimate) without running
% anything, type in MATLAB:   preview_hpc_scenarios
%
% A value of [] means "use the normal value from plant_constants.m or
% controller_parameters.m". That way the defaults live in only one place.

%% Defaults shared by every scenario
default_scenario.name = '';                      % short description, used in titles and the summary table

% Which model to run:
%   'HPC_Compatible_FirstOrderADRC'   ADRC controller, minimal logging (best for long runs)
%   'DataCollection_FirstOrderADRC'   ADRC controller, more signals logged
%   'FPGA_Compatible_FirstOrderADRC'  ADRC controller as it goes to the FPGA (logs only the plant)
%   'OpenLoop_TraditionalStepper'     no controller, driven like a traditional stepper
default_scenario.model_name = 'HPC_Compatible_FirstOrderADRC';
default_scenario.simulation_mode = 'accelerator';   % 'accelerator' (about 8x faster) or 'normal'
default_scenario.stop_time_seconds = 0.5;           % motor time to simulate (about 50 min of wall time per second in accelerator mode)

% Motion command: nut travel in mm (5 mm = one motor revolution).
% Negative values move in reverse.
default_scenario.commanded_displacement_mm = 5;

% Load
default_scenario.spring_constant_lbf_per_inch = [];      % [] = value in plant_constants.m (15 lbf/in); 0 = no spring

% Extra load torque at the motor shaft (see make_load_disturbance.m)
default_scenario.disturbance_type = 'none';              % 'none', 'step', 'impulse' or 'noise'
default_scenario.disturbance_start_time_seconds = 0;     % when it starts
default_scenario.disturbance_size_newton_meters = 0;     % step/impulse height, or noise standard deviation
default_scenario.disturbance_duration_seconds = 0.002;   % impulse width (only used by 'impulse')

% ADRC controller tuning ([] = value in controller_parameters.m)
default_scenario.position_loop_gain = [];
default_scenario.velocity_closed_loop_bandwidth_rad_per_second = [];
default_scenario.velocity_observer_bandwidth_multiplier = [];
default_scenario.current_closed_loop_bandwidth_rad_per_second = [];
default_scenario.current_observer_bandwidth_multiplier = [];

% Traditional stepper only (model_name = 'OpenLoop_TraditionalStepper').
% The number of steps comes from commanded_displacement_mm.
default_scenario.stepper_drive_mode = 'full step';         % 'full step', 'wave' or 'half step'
default_scenario.stepper_step_rate_steps_per_second = 200;

scenarios = [];

%% Useful numbers for choosing displacements and stop times
% The spring force at which the motor's 1.6 N*m holding torque is reached
% (the "slip point"): F = T_holding * 2*pi * efficiency / lead
%                       = 1.6 * 2*pi * 0.9 / 0.005 = 1809.6 N
slip_force_newtons = 1.6 * 2*pi * 0.9 / 0.005;
newtons_per_meter_per_lbf_per_inch = 4.448222 / 0.0254;
% Rough cruise speed of the motor, used only to choose stop times
cruise_speed_rad_per_second = 100;
radians_per_mm = 2*pi / 5;

%% Scenario group 1: no load, forward and reverse (HPC model)
scenario = default_scenario;
scenario.name = 'No spring, +1 rev';
scenario.spring_constant_lbf_per_inch = 0;
scenario.commanded_displacement_mm = 5;
scenarios = add_scenario(scenarios, scenario);

scenario = default_scenario;
scenario.name = 'No spring, -1 rev';
scenario.spring_constant_lbf_per_inch = 0;
scenario.commanded_displacement_mm = -5;
scenarios = add_scenario(scenarios, scenario);

%% Scenario group 2: spring sweep to 70 % of the holding torque (HPC model)
% Each spring is compressed until it pushes back with 70 % of the slip
% force, so every run ends at the same load torque.
spring_rates_lbf_per_inch = [12 15 20 25 30 40 60 100];
for spring_number = 1:length(spring_rates_lbf_per_inch)
    spring_rate = spring_rates_lbf_per_inch(spring_number);
    spring_newtons_per_meter = spring_rate * newtons_per_meter_per_lbf_per_inch;
    displacement_mm = 1000 * 0.70 * slip_force_newtons / spring_newtons_per_meter;

    scenario = default_scenario;
    scenario.name = sprintf('Spring %g lbf/in, 70%% load', spring_rate);
    scenario.spring_constant_lbf_per_inch = spring_rate;
    scenario.commanded_displacement_mm = displacement_mm;
    % time to travel at cruise speed, plus 0.5 s to settle
    scenario.stop_time_seconds = displacement_mm * radians_per_mm / cruise_speed_rad_per_second + 0.5;
    scenarios = add_scenario(scenarios, scenario);
end

%% Scenario group 3: disturbance rejection at 20 lbf/in (HPC model)
% Same move as the 20 lbf/in spring scenario above, plus a disturbance
% that starts 0.2 s after the motor has settled.
spring_rate = 20;
displacement_mm = 1000 * 0.70 * slip_force_newtons / (spring_rate * newtons_per_meter_per_lbf_per_inch);
settle_time_seconds = displacement_mm * radians_per_mm / cruise_speed_rad_per_second + 0.5;
disturbance_types = {'step', 'impulse', 'noise'};
disturbance_sizes_newton_meters = [0.24, 0.40, 0.08];   % 15 %, 25 % and 5 % of the holding torque
for disturbance_number = 1:length(disturbance_types)
    scenario = default_scenario;
    scenario.name = sprintf('Spring 20 lbf/in, %s disturbance', disturbance_types{disturbance_number});
    scenario.spring_constant_lbf_per_inch = spring_rate;
    scenario.commanded_displacement_mm = displacement_mm;
    scenario.disturbance_type = disturbance_types{disturbance_number};
    scenario.disturbance_size_newton_meters = disturbance_sizes_newton_meters(disturbance_number);
    scenario.disturbance_start_time_seconds = settle_time_seconds;
    scenario.stop_time_seconds = settle_time_seconds + 0.2;
    scenarios = add_scenario(scenarios, scenario);
end

%% Scenario group 4: velocity-loop tuning sweep (Data Collection model)
% Short runs that log more signals, to compare controller tunings.
velocity_bandwidths_rad_per_second = [200 400 800];
for bandwidth_number = 1:length(velocity_bandwidths_rad_per_second)
    scenario = default_scenario;
    scenario.model_name = 'DataCollection_FirstOrderADRC';
    scenario.name = sprintf('Velocity bandwidth %g rad/s', velocity_bandwidths_rad_per_second(bandwidth_number));
    scenario.spring_constant_lbf_per_inch = 0;
    scenario.velocity_closed_loop_bandwidth_rad_per_second = velocity_bandwidths_rad_per_second(bandwidth_number);
    scenario.stop_time_seconds = 0.2;
    scenarios = add_scenario(scenarios, scenario);
end

%% Scenario group 5: the FPGA model (same controller, the version that goes to hardware)
scenario = default_scenario;
scenario.model_name = 'FPGA_Compatible_FirstOrderADRC';
scenario.name = 'FPGA model, no spring, +1 rev';
scenario.spring_constant_lbf_per_inch = 0;
scenario.stop_time_seconds = 0.2;
scenarios = add_scenario(scenarios, scenario);

%% Scenario group 6: traditional open-loop stepper drive, for comparison
scenario = default_scenario;
scenario.model_name = 'OpenLoop_TraditionalStepper';
scenario.name = 'Traditional stepper, full step';
scenario.spring_constant_lbf_per_inch = 0;
scenario.commanded_displacement_mm = 0.5;            % 20 full steps
scenario.stepper_drive_mode = 'full step';
scenario.stepper_step_rate_steps_per_second = 200;
scenario.stop_time_seconds = 0.15;                   % 20 steps / 200 steps/s = 0.1 s, plus 0.05 s to settle
scenarios = add_scenario(scenarios, scenario);

scenario = default_scenario;
scenario.model_name = 'OpenLoop_TraditionalStepper';
scenario.name = 'Traditional stepper, half step';
scenario.spring_constant_lbf_per_inch = 0;
scenario.commanded_displacement_mm = 0.5;            % 40 half steps
scenario.stepper_drive_mode = 'half step';
scenario.stepper_step_rate_steps_per_second = 400;
scenario.stop_time_seconds = 0.15;
scenarios = add_scenario(scenarios, scenario);
end


function scenarios = add_scenario(scenarios, scenario)
% Append one scenario to the end of the list
if isempty(scenarios)
    scenarios = scenario;
else
    scenarios(end + 1) = scenario;
end
end
