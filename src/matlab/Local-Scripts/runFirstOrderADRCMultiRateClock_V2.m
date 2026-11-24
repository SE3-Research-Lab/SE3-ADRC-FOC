%% Run the Minimum Footprint Active Disturbance Rejection Control model
% with the update Nema23 Stepper Motor that matches the Mini-Tech mill

clear;
clc;
close all hidden;
Ts_sim = 5e-9;
%% Stepper Motor Parameters
% motor parameters
RT=50 ; 
L=0.0027;
r=0.9;
% Torque constant computed from the datasheet exactly as in thesis
% Eq. (1)-(2), so the script and thesis cannot drift apart. Kt is the
% standardized thesis symbol; Km is kept as an alias so no Simulink block
% that references Km breaks.
T_holding = 1.60;                                           % N*m, Dings' 23H2065 holding torque
I_rated_rms = 3.0;                                          % A rms, datasheet rated current
I_pk_motor = sqrt(2)*I_rated_rms;                           % 4.243 A, thesis Eq. (1)
Kt = T_holding/I_pk_motor;                                  % 0.3771 N*m/A, thesis Eq. (2)
Km = Kt;                                                    % alias, same value
PsiM=Km/RT;

Jm=3.5e-5;
Bm=8e-4;
TL=0.0;

% Ballscrew and nut inertia computed from the THK catalog values,
% matching thesis Eq. (7)-(10). Result: Js = 2.84e-5, Jn = 3.61e-7,
% J = 6.38e-5 kg*m^2.
lambda_s = 1.25;                                            % kg/m, THK BIF1605 shaft mass per unit length
L_screw  = 0.71;                                            % m, screw length
d_screw  = 0.016;                                           % m, screw shaft diameter
m_nut    = 0.57;                                            % kg, nut mass
P_h      = 0.005;                                           % m/rev, lead
Js = 0.5*lambda_s*L_screw*(d_screw/2)^2;                    % thesis Eq. (8)
Jn = m_nut*(P_h/(2*pi))^2;                                  % thesis Eq. (9)
% Jf = "inertia fudge factor", used only for the testing
Jf = 1e-4;
J=Jm+Js+Jn;                                                  % thesis Eq. (10)

%% PCB and testbench Parameters 
% TODO: Adjust the voltage saturation in the Simulink model to handle the
% max of ~66% of 64V.  For now, allowing for 48V is fine without the PWM
% generation in the model. 

% source voltage
vs=48.0; 
% PWM Saturation voltage 
PWMVoltage = 48;

%ADC Constants
ADC_VREF = 5;
ADC_Precision = 16;

% This may need to be changed in the future. Going with a smaller resistor
% and a larger gain is the recommended option for the INA241 and general
% shunt amp usage. 
% INA241A4 (100 V/V) on the revised PCB.
Shunt_Amp_Gain = 100;

% This is set at the resistance of the shunts on the board. A calibrated
% value should be used in the final version. 
% 5 mOhm with 100 V/V gives 0.5 V/A. Amplifier linear output range
% (GND + 50 mV to VS - 200 mV) gives +/-2.3 V about the 2.5 V offset,
% i.e. +/-4.6 A linear, ADC clip at +/-5.0 A. Covers 4.243 A peak plus the
% 89 mA ripple. Shunt loss at 3 A rms: 45 mW (was 0.9 W at 0.1 Ohm).
Shunt_Resistance = 0.005;

% These are used to emulate the ADCS
ADC_Emulated_conversion_factor = Shunt_Resistance*Shunt_Amp_Gain;
% MAX11162 datasheet (Figure 3 / Table 3): LSB = VREF/65536,
% midscale 2.500000 V = code 0x8000, code transitions at +/-0.5 LSB
% (round to nearest), output clips at 0x0000 and 0xFFFF. This matches
% thesis Eq. (40) (2^N / Vref = 13107.2 counts/V).
VoltagetoADCValue = 2^ADC_Precision/ADC_VREF;

% These are used to convert from the ADC 16 bit register to a voltage value
inverseVoltagetoADCValue = 1/VoltagetoADCValue;
inverseADC_Emulated_Conversion_factor= 1/ADC_Emulated_conversion_factor;

% New simulation parameters with updated timing and new constants
% This section supports ADC decoding with the real 16 bit data 
% along with, encoder position decoding, and separated stepper motor
% exact inverse of the datasheet transfer function. 5/65536 is exactly
% representable in binary fixed point (80 LSBs of an En20 type), so the
% decode adds no rounding error and 0x8000 decodes to exactly 0 A.
convert_adc_to_integer = ADC_VREF/2^ADC_Precision;

% 5v at the shunt amp with configuration to offset to 1/2 V_ref
% This will need to be adjusted because the filters each have a slight
% offset applied to the final value. 
Shunt_Amp_Offset = 5/2;

% Shunt amp offset value for decoding the ADC reading this is 5/2 as an 
% unsigned value of just bits. This is so the math is fast in the FPGA
% and takes advantage of bitwise operations 
ADC_Offset = fi(32768, 0, 16,0);

%% Encoder Constants
% The encoder is a 5,000 count quadrature encoder producing 20,0000 counts
% per full mechanical revolution
% This means for a full electrical revolution, it is 400 counts
CountsPerRev = 5000*4;
% Divide by 50 for 50 pole pairs. 
electricalCountsPerRev = CountsPerRev/50;

% This might seem like overkill to have pi calculated out this far however,
% because this value of pi is compared to and subtracted off of other
% values this needs to be a very precise constant to prevent small errors
% from building during run time. This means getting the full 32 bit values
% for the number. 
precise_pi = fi(3.1415927410125732421875, 1,32,28);
precise_step_radians = (2*pi)/20000;

mechanicalRadiansPerCount = fi((2*precise_pi)/CountsPerRev, 1, 128, 64);
% Velocity from edge period: omega = K_omega / N, N = 5 ns counts between edges

K_omega = (2*pi/CountsPerRev)/Ts_sim;                       % 62831.85 rad/s per count^-1
KomegaType = fixdt(1,32,14);                                % max 131072, LSB 6.1e-5 (relative error ~1e-9)

%If the counter runs at Ts_sim = 5 ns, this must be 5e-9.
EncoderCounterTs = Ts_sim;
counts_to_seconds = EncoderCounterTs;

electricalRadiansPerCount = fi((2*precise_pi)/400, 1, 128, 64);

%% Loadcell Parameters
% Unit conversion constants 
lbf_to_N = 4.448222;
in_to_m = 0.0254;

% Offset measured on PCB
loadcell_offset = 0;
loadcell_bias = 2.5;

% Loadcell Constants
excitation = 5;                                             %volts
sensitivity = 2e-3;                                         %volts
rated_capacity = 50*lbf_to_N;                               %Newtons (50 lbs)
loadcell_decode_gain = 47.1460;
adc_volts_per_count = ADC_VREF / 2^ADC_Precision;

% Spring values 
% increase for the simulation load tests (see thesis results section).

spring_constant = 15; % Units of lbf/in (Standard for most McMaster-Carr Springs)
% Convert the spring constant to N/m for SI units
spring_constant = (spring_constant * lbf_to_N)/in_to_m;
%% Ballscrew Parameters
ballscrew_lead_mm = 5;                                      %mm/rev
ballscrew_pitch = ballscrew_lead_mm/1000;                   %m/rev
ballscrew_efficiency = 0.9; 

%Added useful gains to cutdown on extra blocks in simulink
ballscrew_travel_per_rad = ballscrew_pitch/(2*pi);
ballscrew_travel_per_force = ballscrew_pitch/(2*pi*ballscrew_efficiency);

%% Control Parameters
% Position Control Constants
KPth=90; 
 
% Velocity Control Constants 
Ts_velocity=0.0002*2;
wCL_s=400;                                                  % closed loop bandwidth (closed loop poles) 
zCL_s=exp(-wCL_s*Ts_velocity);                              % discrete control poles
keso_s = 4;                                                 % multiplication factor for observer bandwidth
zESO_s=exp(-keso_s*wCL_s*Ts_velocity);                      % discrete observer poles

bs=50*PsiM/J;                                               % = Kt/J. With the thesis J this is ~5914.6 rad/s^2/A
[k1_s,alpha_s,beta_s,gam_s]=MFP_ADRC_1st_params_multirate(bs,zCL_s,zESO_s,Ts_velocity);

% Current Control Constants
Ts_current=2e-5;
KPiqd=10000.0; 
wCL_iqd=KPiqd;                                              % closed loop bandwidth (closed loop poles)
zCL_iqd=exp(-wCL_iqd*Ts_current);                           % discrete control poles

keso_iqd = 2;                                               % multiplication factor for observer bandwidth
zESO_iqd=exp(-keso_iqd*wCL_iqd*Ts_current);                 % discrete observer poles

bid=1/L;
biq=1/L;
[k1_iqd,alpha_iqd,beta_iqd,gam_iqd]=MFP_ADRC_1st_params_multirate(biq,zCL_iqd,zESO_iqd,Ts_current);

steps = 200;
theta_ref=steps*1.8*pi/180; 

stepTime=0.0;

%% Simulation Parameters

ParamType = fixdt(1,32,20);

%% Current reference limit
% With id = 0 the peak phase current equals |iq|, so the iq* limit sets the
% peak phase current.
I_adc_max = (ADC_VREF/2)/ADC_Emulated_conversion_factor;     % ADC clip: 5.0 A revised PCB (2.5 A as-built)
I_amp_linear = (ADC_VREF - 0.2 -  ... 
    ADC_VREF/2)/ADC_Emulated_conversion_factor;              % 4.6 A revised PCB
I_ripple_pp = 0.089;                                         % A, thesis Eq. (14)
Iq_limit_motor = I_pk_motor;                                 % 4.243 A
Iq_limit_PCB = min(I_adc_max, I_amp_linear) ...
     - I_ripple_pp/2;                                        % 4.555 A revised (2.455 A as-built)

Iq_limit = min(Iq_limit_motor, Iq_limit_PCB);                % = 4.243 A with the revised PCB

% Recording position of the motor requires more non-fractional accuracy 
PosType = fixdt(1,32,16); 
% Also turned out to be the perfect value for tracking ADC values in addition to encoder counts
CountType = fixdt(1,32,0); 

% Additional parameters for use in the ADRC loops. 
% The ADRC for velocity requires holding large values > 10,000
% The current control ADRC requires holding small numbers < 1
SpeedLoopType = fixdt(1,32,16);                             % ±32768, LSB 1.5e-5
CurrLoopType  = fixdt(1,32,20);                             % ±2048,  LSB 9.5e-7
%Bitwise logical operator data type
bitwiseOperator = fixdt(0,32,0);
VelType = fixdt(1,128, 64);
%% Print values for thesis Eq. (52) and Table 15
fprintf('Js = %.4e, Jn = %.4e, J = %.4e kg*m^2\n', Js, Jn, J);
fprintf('Kt = %.5f N*m/A, b0 (velocity) = %.2f, b0 (current) = %.2f\n', Kt, bs, biq);
fprintf('Velocity: k1/b0=%.6g a1=%.6g a2=%.6g b0c=%.6g b1c=%.6g g0=%.6g g1=%.6g\n', ...
    double(k1_s)/bs, double(alpha_s(1)), double(alpha_s(2)), double(beta_s(1)), ...
    double(beta_s(2)), double(gam_s(1)), double(gam_s(2)));
fprintf('Current:  k1/b0=%.6g a1=%.6g a2=%.6g b0c=%.6g b1c=%.6g g0=%.6g g1=%.6g\n', ...
    double(k1_iqd)/biq, double(alpha_iqd(1)), double(alpha_iqd(2)), double(beta_iqd(1)), ...
    double(beta_iqd(2)), double(gam_iqd(1)), double(gam_iqd(2)));

%% Simulate
% Important: Run the *correct* Simulink Model
% See README for more information about the *correct* model based on what data or 
% test is needed and location of the run IE personal computer vs Tempest

%simOut=sim("DataCollection_FirstOrderADRC",'StopTime','0.25')

%% Plotting
% Plotting is now handled by a seperate plotting script that standardizes everything