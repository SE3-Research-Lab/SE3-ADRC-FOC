%% Open-loop (traditional) stepper driver settings
% This script sets the values the OpenLoop_TraditionalStepper model needs:
% the phase voltage, the step sequence tables, the step angle, the
% ADC-to-amps conversion and the logging rate.
%
% Set these BEFORE running it (the run script and the HPC scenario runner
% do this for you):
%   drive_mode                   'full step', 'wave' or 'half step'
%   step_rate_steps_per_second   how fast the driver steps
%   number_of_steps_to_move      the driver stops (and holds) after this many steps
%   step_direction               1 = forward, -1 = reverse
% It also needs plant_constants.m to have run first.

%% Phase voltage level
% A traditional "L/R" driver applies a constant voltage. At standstill the
% current settles at voltage / resistance, so this voltage gives the rated
% current in each phase that is on. (The plant limits the current to
% +/-4.243 A, the motor's peak rating.)
phase_voltage_volts = motor_rated_current_rms_amps * motor_phase_resistance_ohms;   % 2.7 V

%% Step sequence tables
% Each column is one step. +1 = positive voltage on that phase, -1 =
% negative voltage, 0 = phase off. The driver goes through the columns left
% to right (right to left when step_direction is -1) and then starts over.
%
% The motor has 50 rotor teeth, so one trip through a 4-step sequence moves
% the rotor 4 * 1.8 = 7.2 degrees.
if strcmp(drive_mode, 'full step')
    step_sequence_phase_a = [ 1  -1  -1   1];
    step_sequence_phase_b = [ 1   1  -1  -1];
    step_angle_degrees = 1.8;
    % With both phases on, the rotor rests halfway between two teeth
    % positions, so the first rest position is half a step from 0.
    sequence_start_angle_degrees = 0.9;
elseif strcmp(drive_mode, 'wave')
    step_sequence_phase_a = [ 1   0  -1   0];
    step_sequence_phase_b = [ 0   1   0  -1];
    step_angle_degrees = 1.8;
    sequence_start_angle_degrees = 0;
elseif strcmp(drive_mode, 'half step')
    step_sequence_phase_a = [ 1   1   0  -1  -1  -1   0   1];
    step_sequence_phase_b = [ 0   1   1   1   0  -1  -1  -1];
    step_angle_degrees = 0.9;
    sequence_start_angle_degrees = 0;
else
    error('drive_mode must be ''full step'', ''wave'' or ''half step''.');
end

% Values used by the blocks in the "Full Step Sequence Generator" subsystem
steps_in_sequence = length(step_sequence_phase_a);
step_angle_radians = step_angle_degrees * pi / 180;
sequence_start_angle_radians = sequence_start_angle_degrees * pi / 180;

%% Converting the plant's current readings to amps
% The plant outputs the phase currents the way the PCB's ADCs read them:
% 16-bit counts, with 0 A at mid-scale (2.5 V = 32768 counts). The
% "ADC Counts to Amps" subsystem undoes that so the plots show amps.
adc_counts_at_zero_current = shunt_amplifier_offset_volts * adc_counts_per_volt;   % 32768
amps_per_adc_count = 1 / (adc_counts_per_volt * shunt_volts_per_amp);

%% Logging
% Save one sample every 20 us instead of every 5 ns step, so the logged
% data stays small. (20 us / 5 ns = 4000 steps.)
logging_period_seconds = 20e-6;
logging_decimation = round(logging_period_seconds / Ts_sim);
