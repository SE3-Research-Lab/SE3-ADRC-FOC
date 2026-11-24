function run_results = reduceSweepRun(sim_output, position_loop_gain, theta_ref, trace_time_step)
%% Post Simulation Function for sweepVelocityTuning.m
% Runs on the parallel worker right after each simulation in the sweep
% finishes. It computes the tuning metrics and keeps a thinned copy of the
% traces, so the full rate logged data never travels back to (or piles up
% in) the main MATLAB session.
%
% Whatever this function returns replaces the normal simulation output.
% That is why sweepVelocityTuning.m reads the results with
% get('Overshoot_pct'), get('t'), and so on. The field names of
% run_results must not be changed without also changing that script.
%
% Inputs:
%   sim_output          Simulink.SimulationOutput of the finished run
%   position_loop_gain  position gain KPth used in that run (1/s)
%   theta_ref           position step command (rad)
%   trace_time_step     spacing of the stored traces (s), e.g. 10e-6
%
% Output fields (run_results):
%   RunError            '' if the run worked, otherwise the error message
%   Overshoot_pct       position overshoot past theta_ref (%)
%   Settle_ms           2% settling time (ms), NaN if it never settles
%   IAE_mrad_s          integral of the absolute position error (mrad*s)
%   VelTrackRMS         RMS velocity tracking error (rad/s)
%   VelPeakErr          largest velocity above the command (rad/s)
%   PeakIq_A            largest |iq| during the run (A)
%   HoldVelRMS          RMS velocity while holding the final position (rad/s)
%   HoldIqP2P_A         peak to peak iq while holding (A)
%   HoldPosP2P_counts   peak to peak position while holding (encoder counts)
%   t, theta, omega, omega_cmd   thinned traces for plotting

%% Constants
% Time after which the move is finished and the motor is only holding
% position. Anything after this is used for the holding (limit cycle)
% metrics. Must be less than the sweep stop time.
hold_start_time = 0.045;                                    % s

% Settling band: the position is "settled" once it stays within 2% of
% the commanded step
settling_band_fraction = 0.02;

% 5000 line quadrature encoder = 20000 counts per mechanical revolution
radians_per_encoder_count = 2*pi/20000;                     % rad/count

% Start with no error. If anything below fails, the catch block at the
% bottom fills this in instead.
run_results.RunError = '';

try
    %% Read the Logged Signals
    % Each logged signal is a timeseries with a .Time and a .Data part
    logged_angle    = get_logged_signal(sim_output, 'log_angle_rad_a');
    logged_velocity = get_logged_signal(sim_output, 'log_angular_velocity_rad_per_sec_a');
    logged_current  = get_logged_signal(sim_output, 'log_quadrature_current_c');

    % Turn each signal into plain double column vectors.
    %   squeeze removes extra size 1 dimensions that logging can add
    %   double converts fixed point (fi) data to normal numbers
    %   (:) forces a column vector so all the math below lines up
    % unwrap removes jumps of 2*pi in the angle, in case the logged angle
    % wraps around, so the position is one continuous curve.
    angle_time = logged_angle.Time(:);
    angle_rad  = unwrap(double(squeeze(logged_angle.Data)));
    angle_rad  = angle_rad(:);

    velocity_time        = logged_velocity.Time(:);
    velocity_rad_per_sec = double(squeeze(logged_velocity.Data));
    velocity_rad_per_sec = velocity_rad_per_sec(:);

    %% Position Metrics
    absolute_position_error = abs(theta_ref - angle_rad);

    % Overshoot in percent of the step. max(0, ...) reports 0 instead of
    % a negative number when the position never passes theta_ref.
    run_results.Overshoot_pct = max(0, (max(angle_rad) - theta_ref)/theta_ref*100);

    % Settling time
    % Find the LAST sample that is outside the settling band. The sample
    % right after it is when the position entered the band for good.
    last_sample_outside_band = find( ...
        absolute_position_error > settling_band_fraction*theta_ref, 1, 'last');
    if isempty(last_sample_outside_band)
        % Never outside the band
        run_results.Settle_ms = 0;
    elseif last_sample_outside_band < numel(angle_time)
        run_results.Settle_ms = angle_time(last_sample_outside_band + 1)*1e3;
    else
        % Still outside the band at the last sample: not settled within
        % the stop time
        run_results.Settle_ms = NaN;
    end

    % Integral of absolute error (IAE). trapz adds up the area under the
    % error curve using the trapezoid rule. *1e3 converts rad*s to mrad*s.
    run_results.IAE_mrad_s = trapz(angle_time, absolute_position_error)*1e3;

    %% Velocity Tracking Metrics
    % The position loop is a proportional controller, so the velocity it
    % asks for is KPth*(theta_ref - position). This uses the actual
    % position, so it is the ideal command, not the one measured inside
    % the controller.
    %
    % The angle and velocity are logged at different times, so interp1
    % looks up the angle at each velocity sample time.
    %   'previous' holds the last value (like a sampled signal does)
    %   'extrap'   allows times slightly outside the angle's time range
    angle_at_velocity_times = interp1(angle_time, angle_rad, velocity_time, ...
        'previous', 'extrap');
    velocity_command = position_loop_gain*(theta_ref - angle_at_velocity_times);

    velocity_tracking_error = velocity_rad_per_sec - velocity_command;
    run_results.VelTrackRMS = rms(velocity_tracking_error);
    run_results.VelPeakErr  = max(velocity_tracking_error);  % worst overshoot above the command
    run_results.PeakIq_A    = max(abs(double(squeeze(logged_current.Data))));

    %% Holding Metrics
    % After the move, the motor should sit still at theta_ref. A small
    % back and forth oscillation (limit cycle) can appear instead. These
    % metrics measure how big it is, using only samples after
    % hold_start_time.
    current_time = logged_current.Time(:);
    quadrature_current_amps = double(squeeze(logged_current.Data));
    quadrature_current_amps = quadrature_current_amps(:);

    % true/false lists that pick out the holding samples of each signal
    is_holding_velocity = velocity_time >= hold_start_time;
    is_holding_current  = current_time  >= hold_start_time;
    is_holding_angle    = angle_time    >= hold_start_time;

    run_results.HoldVelRMS = rms(velocity_rad_per_sec(is_holding_velocity));  % rad/s

    % Peak to peak = largest value minus smallest value
    run_results.HoldIqP2P_A = max(quadrature_current_amps(is_holding_current)) ...
                            - min(quadrature_current_amps(is_holding_current));

    % Dividing by radians per count converts the position swing to
    % encoder counts, which is easier to compare with the sensor resolution
    run_results.HoldPosP2P_counts = (max(angle_rad(is_holding_angle)) ...
                                   - min(angle_rad(is_holding_angle))) ...
                                   / radians_per_encoder_count;

    %% Thinned Traces for Plotting
    % Resample every signal onto one evenly spaced time vector. With a
    % 10 us spacing this is far smaller than the logged data but still
    % plenty for the plots. .' makes it a column vector.
    trace_time = (0:trace_time_step:angle_time(end)).';
    run_results.t         = trace_time;
    run_results.theta     = interp1(angle_time,    angle_rad,            trace_time, 'previous', 'extrap');
    run_results.omega     = interp1(velocity_time, velocity_rad_per_sec, trace_time, 'previous', 'extrap');
    run_results.omega_cmd = interp1(velocity_time, velocity_command,     trace_time, 'previous', 'extrap');

catch metric_error
    % Something above failed. Save the reason instead of stopping, so one
    % bad run does not stop the whole sweep. If the simulation itself
    % failed, its error message explains more than the metric error
    % (which usually just says a logged signal was missing), so use that.
    run_results.RunError = metric_error.message;
    if ~isempty(sim_output.ErrorMessage)
        run_results.RunError = sim_output.ErrorMessage;
    end
end
end


function logged_signal = get_logged_signal(sim_output, signal_name)
% Return a logged signal as a timeseries, whichever way it was logged.
% To Workspace blocks give a timeseries directly. Signal logging gives a
% Dataset that holds a Signal object, which holds the timeseries in its
% .Values property. This unwraps those layers when they are there.
logged_signal = sim_output.get(signal_name);

if isa(logged_signal, 'Simulink.SimulationData.Dataset')
    logged_signal = logged_signal{1};                       % first element of the Dataset
end

if isa(logged_signal, 'Simulink.SimulationData.Signal')
    logged_signal = logged_signal.Values;                   % the timeseries inside the Signal
end
end
