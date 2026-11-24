%% Controller parameters: the ADRC field-oriented controller
% This script sets everything the CONTROLLER needs: the loop rates, the
% position gain, the velocity and current ADRC tuning, the iq* current limit,
% the sensor-decoding constants and the fixed-point data types.
%
% It is shared by the three ADRC models:
%   HPC_Compatible_FirstOrderADRC, DataCollection_FirstOrderADRC and
%   FPGA_Compatible_FirstOrderADRC.
%
% How to use it:
%   Run plant_constants.m FIRST. The controller gains are designed from the
%   plant (inertia, inductance, torque constant), so this script reads
%   variables that plant_constants.m creates. The run scripts
%   (run_..._model.m) call both scripts in the right order for you.
%
% About the variable names:
%   Same rule as plant_constants.m: a long, descriptive name first, then the
%   short name the Simulink blocks use. Never delete or rename a short name
%   without changing the blocks that use it.
%
% This file has no clear/clc on purpose: it must not erase the variables of
% the script that calls it.

%% Fixed-point data types used inside the controller
% fixdt(signed, total bits, fraction bits). More fraction bits give finer
% resolution but a smaller range.
ParamType     = fixdt(1, 32, 20);   % general parameters
PosType       = fixdt(1, 32, 16);   % position needs a large whole-number range
CountType     = fixdt(1, 32, 0);    % whole numbers: encoder counts and ADC values
SpeedLoopType = fixdt(1, 32, 16);   % velocity ADRC, values above 10,000 (+/-32768, LSB 1.5e-5)
CurrLoopType  = fixdt(1, 32, 20);   % current ADRC, values below 1 (+/-2048, LSB 9.5e-7)
VelType       = fixdt(1, 128, 64);  % high-precision velocity math

%% Loop rates (the controller is multirate)
% Current loops run every 20 us. The velocity loop runs every 400 us; its
% signals enter and leave it through Rate Transition blocks.
current_loop_period_seconds = 2e-5;
Ts_current = current_loop_period_seconds;        % name used by the Simulink model

velocity_loop_period_seconds = 0.0002 * 2;
Ts_velocity = velocity_loop_period_seconds;      % name used by the Simulink model

%% Current sensor decoding (ADC counts -> amps)
% The ADC reads 32768 (0x8000) at 0 A. It is stored as an unsigned 16-bit
% fixed-point number so the FPGA can subtract it with simple bit math.
adc_zero_current_counts = fi(32768, 0, 16, 0);
ADC_Offset = adc_zero_current_counts;            % name used by the Simulink model

% Volts per ADC count: 5 V / 65536 (exactly representable in fixed point)
adc_volts_per_count = adc_reference_voltage_volts / 2^adc_resolution_bits;

% Converts the decoded load-cell voltage into force
loadcell_decode_gain = 47.1460;

%% Encoder decoding (counts -> radians and rad/s)
% pi stored with full 32-bit precision. It is compared with and subtracted
% from other values, so small errors would otherwise build up over time.
precise_pi = fi(3.1415927410125732421875, 1, 32, 28);

mechanical_radians_per_count = fi((2*precise_pi) / encoder_counts_per_revolution, 1, 128, 64);
mechanicalRadiansPerCount = mechanical_radians_per_count;   % name used by the Simulink model

% One electrical revolution is 20000 / 50 = 400 encoder counts
electrical_radians_per_count = fi((2*precise_pi) / 400, 1, 128, 64);
electricalRadiansPerCount = electrical_radians_per_count;   % name used by the Simulink model

% Velocity from the time between encoder edges: omega = K_omega / N, where
% N is the number of 5 ns clock ticks between two edges.
velocity_gain_rad_per_second_times_ticks = (2*pi / encoder_counts_per_revolution) / Ts_sim;  % 62831.85
K_omega = velocity_gain_rad_per_second_times_ticks;         % name used by the Simulink model

%% Controller tuning choices
% These are the values you would change to tune the controller. The math
% that turns them into the coefficients the Simulink model uses is in
% design_adrc_gains.m, which this script runs at the very end.
%
% IMPORTANT: if you change any of these values AFTER running this script
% (for example in a run script or an HPC scenario), run design_adrc_gains
% again so the model gets the new coefficients.

% Position loop (proportional): velocity command = gain * position error
position_loop_gain = 90;

% Velocity loop (first-order ADRC)
velocity_closed_loop_bandwidth_rad_per_second = 400;
velocity_observer_bandwidth_multiplier = 4;      % observer is 4x faster than the loop

% Current loops, d and q axis (first-order ADRC)
current_closed_loop_bandwidth_rad_per_second = 10000.0;
current_observer_bandwidth_multiplier = 2;       % observer is 2x faster than the loop

%% Current reference limit (iq*)
% With id = 0, the peak phase current equals |iq|, so limiting iq* limits
% the phase current. Use the smaller of what the motor allows and what the
% PCB can measure.
pcb_adc_clip_current_amps = (adc_reference_voltage_volts/2) / shunt_volts_per_amp;   % 5.0 A
pcb_amplifier_linear_current_amps = ...
    (adc_reference_voltage_volts - 0.2 - adc_reference_voltage_volts/2) / shunt_volts_per_amp;  % 4.6 A
pwm_current_ripple_peak_to_peak_amps = 0.089;    % thesis Eq. (14)

current_limit_from_motor_amps = motor_peak_current_amps;    % 4.243 A
current_limit_from_pcb_amps = min(pcb_adc_clip_current_amps, pcb_amplifier_linear_current_amps) ...
    - pwm_current_ripple_peak_to_peak_amps/2;               % 4.555 A
q_axis_current_limit_amps = min(current_limit_from_motor_amps, current_limit_from_pcb_amps);
Iq_limit = q_axis_current_limit_amps;            % name used by the Simulink model (4.243 A)

%% Default motion command
% The model moves the motor to this angle as a step at t = 0. One full step
% of the motor is 1.8 degrees, so 200 steps is one revolution (5 mm of
% travel). The run scripts can change commanded_motor_steps.
commanded_motor_steps = 200;
theta_ref = commanded_motor_steps * 1.8 * pi / 180;          % name used by the Simulink model

%% Turn the tuning choices into ADRC coefficients
design_adrc_gains;
