%% Plant constants: the physical system every model simulates
% This script sets every constant that describes the HARDWARE: the stepper
% motor, the ballscrew and nut, the spring load, the PCB (PWM voltage, shunt
% amplifiers, ADCs), the encoder and the load cell.
%
% It is shared by every model:
%   HPC_Compatible_FirstOrderADRC, DataCollection_FirstOrderADRC,
%   FPGA_Compatible_FirstOrderADRC and OpenLoop_TraditionalStepper.
%
% How to use it:
%   Do not run this file by itself. The run scripts (run_..._model.m) call it
%   for you. If you change a value here, it changes for every model.
%
% About the variable names:
%   Each value first gets a long, descriptive name (for example
%   motor_phase_resistance_ohms). Right after it, the short name that the
%   Simulink blocks use is set from it (for example r). The Simulink blocks
%   only know the short names, so never delete or rename a short name
%   without also changing every block that uses it.
%
% Numbers marked "thesis Eq. (x)" come from the thesis so the two always
% agree. This file has no clear/clc on purpose: it must not erase the
% variables of the script that calls it.

%% Simulation clock
% The FPGA fabric runs at 200 MHz, so one clock tick is 5 ns. The whole
% Simulink model steps at this rate.
fpga_clock_period_seconds = 5e-9;
Ts_sim = fpga_clock_period_seconds;              % name used by the Simulink model

%% Stepper motor (Dings' 23H2065, NEMA 23)
% A hybrid stepper has 50 rotor teeth, which act like 50 pole pairs.
motor_rotor_teeth = 50;
RT = motor_rotor_teeth;                          % name used by the Simulink model

motor_phase_inductance_henries = 0.0027;
L = motor_phase_inductance_henries;              % name used by the Simulink model

motor_phase_resistance_ohms = 0.9;
r = motor_phase_resistance_ohms;                 % name used by the Simulink model

% Torque constant computed from the datasheet, thesis Eq. (1)-(2)
motor_holding_torque_newton_meters = 1.60;       % datasheet holding torque
motor_rated_current_rms_amps = 3.0;              % datasheet rated current per phase
motor_peak_current_amps = sqrt(2) * motor_rated_current_rms_amps;   % 4.243 A, thesis Eq. (1)
motor_torque_constant_newton_meters_per_amp = ...
    motor_holding_torque_newton_meters / motor_peak_current_amps;   % 0.3771 N*m/A, thesis Eq. (2)
T_holding = motor_holding_torque_newton_meters;  % short name used by the HPC scripts and plots
Kt = motor_torque_constant_newton_meters_per_amp;

% Flux linkage of one rotor tooth (torque constant divided by the teeth)
motor_flux_linkage_weber = motor_torque_constant_newton_meters_per_amp / motor_rotor_teeth;
PsiM = motor_flux_linkage_weber;                 % name used by the Simulink model

motor_rotor_inertia_kg_m2 = 3.5e-5;
motor_viscous_friction_newton_meter_seconds = 8e-4;
Bm = motor_viscous_friction_newton_meter_seconds;   % name used by the Simulink model

%% Ballscrew and nut (THK BIF1605), thesis Eq. (7)-(10)
ballscrew_shaft_mass_per_length_kg_per_m = 1.25;
ballscrew_length_m = 0.71;
ballscrew_diameter_m = 0.016;
ballscrew_nut_mass_kg = 0.57;
ballscrew_lead_mm = 5;                           % mm of travel per motor revolution
ballscrew_pitch = ballscrew_lead_mm / 1000;      % m of travel per motor revolution
ballscrew_efficiency = 0.9;

% Inertia of the screw shaft (a solid cylinder), thesis Eq. (8)
ballscrew_shaft_inertia_kg_m2 = 0.5 * ballscrew_shaft_mass_per_length_kg_per_m * ...
    ballscrew_length_m * (ballscrew_diameter_m / 2)^2;
% Inertia of the nut as seen by the motor shaft, thesis Eq. (9)
ballscrew_nut_inertia_kg_m2 = ballscrew_nut_mass_kg * (ballscrew_pitch / (2*pi))^2;

% Total inertia the motor has to turn, thesis Eq. (10)
total_inertia_kg_m2 = motor_rotor_inertia_kg_m2 + ballscrew_shaft_inertia_kg_m2 + ...
    ballscrew_nut_inertia_kg_m2;                 % 6.38e-5 kg*m^2
J = total_inertia_kg_m2;                         % name used by the Simulink model

% Gains that turn rotor angle into nut travel and nut force into shaft
% torque (these names are used directly by the Simulink model)
ballscrew_travel_per_rad = ballscrew_pitch / (2*pi);
ballscrew_travel_per_force = ballscrew_pitch / (2*pi*ballscrew_efficiency);

%% Spring load on the nut
% Unit conversions
pound_force_to_newtons = 4.448222;
inches_to_meters = 0.0254;

% 5 lbf/in is the smallest physical spring. Larger springs are used for the
% simulation load tests (see the thesis results). Set it to 0 for no load.
spring_constant_lbf_per_inch = 15;               % McMaster-Carr springs are sold in lbf/in
spring_constant_newtons_per_meter = ...
    (spring_constant_lbf_per_inch * pound_force_to_newtons) / inches_to_meters;
spring_constant = spring_constant_newtons_per_meter;   % name used by the Simulink model

%% Extra load torque (disturbance) at the motor shaft
% Two columns: [time in seconds, torque in N*m]. The plant holds each value
% until the next time. All zeros means no disturbance.
load_disturbance_data = [0 0; 1 0];

%% PCB: PWM voltage
% The PWM generator limits its output to this voltage. The bridge is
% supplied with 48 V.
pwm_supply_voltage_volts = 48;
PWMVoltage = pwm_supply_voltage_volts;           % name used by the Simulink model

%% PCB: current sense (shunt resistor, INA241 amplifier, MAX11162 ADC)
adc_reference_voltage_volts = 5;
adc_resolution_bits = 16;

% Revised PCB: INA241A4 (100 V/V) and a 5 mOhm shunt, which gives 0.5 V/A.
% (The as-built board uses the 10 V/V amplifier and a 0.1 Ohm shunt.)
shunt_amplifier_gain = 100;
shunt_resistance_ohms = 0.005;

% Volts at the ADC input for every amp of phase current
shunt_volts_per_amp = shunt_resistance_ohms * shunt_amplifier_gain;
ADC_Emulated_conversion_factor = shunt_volts_per_amp;   % name used by the Simulink model

% ADC counts per volt: 2^16 / 5 V = 13107.2 counts/V (MAX11162 datasheet,
% thesis Eq. (40))
adc_counts_per_volt = 2^adc_resolution_bits / adc_reference_voltage_volts;
VoltagetoADCValue = adc_counts_per_volt;         % name used by the Simulink model

% The amplifier output sits at half the reference (2.5 V) when the current is 0 A
shunt_amplifier_offset_volts = 5/2;
Shunt_Amp_Offset = shunt_amplifier_offset_volts; % name used by the Simulink model

%% Encoder
% 5000-line quadrature encoder: 4 edges per line = 20000 counts per revolution
encoder_lines_per_revolution = 5000;
encoder_counts_per_revolution = encoder_lines_per_revolution * 4;

%% Load cell
loadcell_offset = 0;                             % offset measured on the PCB (V)
loadcell_bias = 2.5;                             % bias voltage (V)
excitation = 5;                                  % excitation voltage (V)
sensitivity = 2e-3;                              % output per volt of excitation (V/V)
rated_capacity = 50 * pound_force_to_newtons;    % 50 lbf, in newtons
