%% Design the ADRC gains from the tuning choices
% This script turns the tuning choices in controller_parameters.m into the
% coefficients the Simulink model uses. controller_parameters.m runs it
% automatically at its end.
%
% Run it again yourself if you change any of these values after running
% controller_parameters.m:
%   position_loop_gain
%   velocity_closed_loop_bandwidth_rad_per_second
%   velocity_observer_bandwidth_multiplier
%   current_closed_loop_bandwidth_rad_per_second
%   current_observer_bandwidth_multiplier
% (The HPC scenario runner does this for you.)
%
% It needs the plant (plant_constants.m) and the loop rates
% (controller_parameters.m) to already be in the workspace.

%% Position loop
KPth = position_loop_gain;                       % name used by the Simulink model

%% Velocity loop: first-order ADRC
% Discrete-time pole locations: z = exp(-bandwidth * sample period)
velocity_closed_loop_pole = exp(-velocity_closed_loop_bandwidth_rad_per_second * Ts_velocity);
velocity_observer_pole = exp(-velocity_observer_bandwidth_multiplier * ...
    velocity_closed_loop_bandwidth_rad_per_second * Ts_velocity);

% Plant gain b0 seen by the velocity loop: Kt / J (about 5914.6 rad/s^2 per A)
velocity_plant_gain_b0 = motor_rotor_teeth * PsiM / J;
bs = velocity_plant_gain_b0;                     % name used by the Simulink model

% Controller and observer coefficients (Herbst and Madonski, 2023)
[k1_s, alpha_s, beta_s, gam_s] = MFP_ADRC_1st_params_multirate(velocity_plant_gain_b0, ...
    velocity_closed_loop_pole, velocity_observer_pole, Ts_velocity);

%% Current loops (d and q axis): first-order ADRC
current_closed_loop_pole = exp(-current_closed_loop_bandwidth_rad_per_second * Ts_current);
current_observer_pole = exp(-current_observer_bandwidth_multiplier * ...
    current_closed_loop_bandwidth_rad_per_second * Ts_current);

% Plant gain b0 seen by the current loops: 1 / inductance
current_plant_gain_b0 = 1 / L;
biq = current_plant_gain_b0;                     % name used by the Simulink model

[k1_iqd, alpha_iqd, beta_iqd, gam_iqd] = MFP_ADRC_1st_params_multirate(current_plant_gain_b0, ...
    current_closed_loop_pole, current_observer_pole, Ts_current);

%% Print the key values (they match thesis Eq. (52) and Table 15)
fprintf('Total inertia J = %.4e kg*m^2, torque constant Kt = %.5f N*m/A\n', J, Kt);
fprintf('Position gain = %g, velocity bandwidth = %g rad/s (observer x%g), current bandwidth = %g rad/s (observer x%g)\n', ...
    position_loop_gain, velocity_closed_loop_bandwidth_rad_per_second, velocity_observer_bandwidth_multiplier, ...
    current_closed_loop_bandwidth_rad_per_second, current_observer_bandwidth_multiplier);
fprintf('b0 (velocity) = %.2f, b0 (current) = %.2f, iq* limit = %.3f A\n', bs, biq, Iq_limit);
