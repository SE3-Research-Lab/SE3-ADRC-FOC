function load_disturbance_data = make_load_disturbance(disturbance_type, start_time_seconds, ...
    size_newton_meters, duration_seconds, stop_time_seconds, random_seed)
%% Build the extra load torque the plant adds at the motor shaft
% Returns a two-column matrix [time in seconds, torque in N*m]. The plant's
% "Load Disturbance" block holds each value until the next time.
%
% disturbance_type:
%   'none'     no extra torque
%   'step'     torque jumps to size_newton_meters at start_time_seconds and stays
%   'impulse'  torque is size_newton_meters for duration_seconds, then back to 0
%   'noise'    random torque (normal distribution, standard deviation
%              size_newton_meters) from start_time_seconds on, with a new
%              random value every 0.1 ms
% random_seed: a whole number. The same seed always gives the same noise,
%              so a run can be repeated exactly.

if strcmp(disturbance_type, 'none')
    load_disturbance_data = [0 0; 1 0];

elseif strcmp(disturbance_type, 'step')
    load_disturbance_data = [0                   0;
                             start_time_seconds  size_newton_meters];

elseif strcmp(disturbance_type, 'impulse')
    load_disturbance_data = [0                                      0;
                             start_time_seconds                     size_newton_meters;
                             start_time_seconds + duration_seconds  0];

elseif strcmp(disturbance_type, 'noise')
    noise_update_period_seconds = 1e-4;
    rng(random_seed);
    noise_times = (start_time_seconds : noise_update_period_seconds : stop_time_seconds)';
    noise_values = size_newton_meters * randn(length(noise_times), 1);
    load_disturbance_data = [0 0; noise_times noise_values];

else
    error('Unknown disturbance_type ''%s''. Use ''none'', ''step'', ''impulse'' or ''noise''.', disturbance_type);
end

% The times must be in increasing order. A disturbance at t = 0 would
% repeat the first time, so drop the leading zero row in that case.
if size(load_disturbance_data, 1) > 1 && load_disturbance_data(2, 1) == 0
    load_disturbance_data(1, :) = [];
end
end
