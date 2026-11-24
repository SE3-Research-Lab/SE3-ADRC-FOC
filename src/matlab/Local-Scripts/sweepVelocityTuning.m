%% Velocity ADRC and Position Loop Tuning Sweep
% Runs the DataCollection model once for every combination of velocity
% loop bandwidth (wCL), observer bandwidth factor (keso), and position
% gain (KPth), then compares the runs with a results table and two figures.
%
% Before running this script:
%   1. Run runFirstOrderADRCMultiRateClock_V2.m so the base workspace has
%      bs, Ts_velocity, theta_ref, and the rest of the model constants.
%   2. Make sure reduceSweepRun.m is in the same folder as this script.
%
% Nothing in the base workspace or the saved model is changed. Each run
% gets its own gains through a Simulink.SimulationInput object.

model_name = 'DataCollection_FirstOrderADRC';

%% Check That the Parallel Computing Toolbox Is Installed
% This sweep uses parsim to run several simulations at the same time on
% parallel workers, which needs the Parallel Computing Toolbox.
%
% The check is done before any setup so the script stops right away
% instead of after the model has loaded. error() prints the message in
% red and ends the script.
parallel_toolbox_info = ver('parallel');
if isempty(parallel_toolbox_info)
    error(['The Parallel Computing Toolbox is not installed. ' ...
           'Install it from the MATLAB Home tab: Add-Ons > Get Add-Ons, ' ...
           'search for "Parallel Computing Toolbox", then run this ' ...
           'script again.']);
end

%% Sweep Settings
% Simulation length
% 0.015 s is enough to compare velocity overshoot and ringing.
% Use >= 0.06 s for settling time (2% settling ~ 4/KPth = 44 ms at KPth = 90)
% and to see the limit cycle while holding the final position.
stop_time = 0.06;                                           % s

% Values to sweep. Every combination of these three lists is simulated.
wCL_list  = [300 400 500];                                  % rad/s, velocity loop closed loop bandwidth
keso_list = [2.5 3 4];                                      % observer bandwidth factor, wESO = keso*wCL
KPth_list = 90;                                             % 1/s, position loop gain

%% Memory and Speed Settings
% Number of parallel workers. Raise this only after checking how much
% memory each worker uses.
max_workers = 4;

% To Workspace blocks log every 5 ns by default. Keeping every 200th
% sample gives one sample every 1 us, which is plenty for the metrics.
log_decimation = 200;

% Spacing of the thinned traces that reduceSweepRun.m sends back to this
% MATLAB session for plotting.
trace_time_step = 10e-6;                                    % s

% Scopes slow the simulation down and are not needed for a sweep.
disable_scopes = true;

%% Build the List of Runs
load_system(model_name);

% ndgrid makes every combination of the three sweep lists. Entry i of
% each grid holds the values used in run i.
%
% Example with wCL_list = [300 400] and keso_list = [3 4]:
%   wCL_grid  = [300 300      keso_grid = [3 4
%                400 400]                  3 4]
% Reading both grids at the same index gives one combination, e.g.
% index 3 is wCL = 300, keso = 4. MATLAB counts down each column first,
% so the four runs are (300,3), (400,3), (300,4), (400,4).
%
% Indexing a grid with one number, like wCL_grid(run_index), walks
% through it in that same order. Writing wCL_grid(:) turns the whole
% grid into one tall column in that order, which is used later to build
% the results table.
[wCL_grid, keso_grid, KPth_grid] = ndgrid(wCL_list, keso_list, KPth_list);
number_of_runs = numel(wCL_grid);                           % 3*3*1 = 9 runs with the default lists

% Find the logging and Scope blocks so they can be changed for each run.
% find_system searches the whole model and returns the full path of
% every block of the given type. 'LookUnderMasks' and 'FollowLinks' make
% it also search inside masked subsystems and library blocks, which it
% would otherwise skip.
to_workspace_blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', 'BlockType', 'ToWorkspace');
scope_blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', 'BlockType', 'Scope');

% A Simulink.SimulationInput object is a list of changes to apply to the
% model for one simulation only: parameter values, block settings, and
% variables. The model file and the base workspace are left alone, which
% is what lets many runs with different gains happen at the same time.
%
% This line makes an array with one SimulationInput per run. Each one
% starts out empty (no changes) and is filled in by the loop below.
%
% Note: SimulationInput methods return an updated copy instead of
% changing the object in place, so every call has to be written as
%   sim_inputs(run_index) = sim_inputs(run_index).someMethod(...);
sim_inputs(1:number_of_runs) = Simulink.SimulationInput(model_name);

for run_index = 1:number_of_runs
    wCL_run  = wCL_grid(run_index);
    keso_run = keso_grid(run_index);
    KPth_run = KPth_grid(run_index);

    % Velocity ADRC gains for this run (same design as the main script)
    zCL_run  = exp(-wCL_run*Ts_velocity);                   % discrete control poles
    zESO_run = exp(-keso_run*wCL_run*Ts_velocity);          % discrete observer poles
    [k1_run, alpha_run, beta_run, gam_run] = ...
        MFP_ADRC_1st_params_multirate(bs, zCL_run, zESO_run, Ts_velocity);

    % Simulation settings that keep memory use low
    sim_inputs(run_index) = sim_inputs(run_index).setModelParameter( ...
        'StopTime', num2str(stop_time));
    sim_inputs(run_index) = sim_inputs(run_index).setModelParameter( ...
        'InspectSignalLogs', 'off');                        % do not archive in the Data Inspector
    sim_inputs(run_index) = sim_inputs(run_index).setModelParameter( ...
        'SaveState', 'off', 'SaveFinalState', 'off');

    % setVariable gives the model a value for a variable during this run
    % only. When the model looks up a variable, a value set here wins over
    % the base workspace value from the main script. The names must match
    % the names used inside the Simulink model exactly.
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('wCL_s',   wCL_run);
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('keso_s',  keso_run);
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('zCL_s',   zCL_run);
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('zESO_s',  zESO_run);
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('k1_s',    k1_run);
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('alpha_s', alpha_run);
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('beta_s',  beta_run);
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('gam_s',   gam_run);
    sim_inputs(run_index) = sim_inputs(run_index).setVariable('KPth',    KPth_run);

    % Log fewer samples from every To Workspace block
    for block_index = 1:numel(to_workspace_blocks)
        sim_inputs(run_index) = sim_inputs(run_index).setBlockParameter( ...
            to_workspace_blocks{block_index}, 'Decimation', num2str(log_decimation));
    end

    % Comment out every Scope block for this run only
    if disable_scopes
        for block_index = 1:numel(scope_blocks)
            sim_inputs(run_index) = sim_inputs(run_index).setBlockParameter( ...
                scope_blocks{block_index}, 'Commented', 'on');
        end
    end

    % Post simulation function
    % reduceSweepRun.m runs right after each simulation finishes, on the
    % same worker that ran it. It computes the metrics and thins the
    % traces so the full rate logs never come back to this MATLAB session.
    % Whatever it returns replaces the normal simulation output, which is
    % why the results are read later with get('Overshoot_pct') and so on.
    %
    % The @(sim_output) ... part is an anonymous function: a small
    % function with no file of its own. Simulink calls it with one input,
    % the finished simulation output, and it passes that along to
    % reduceSweepRun together with three more values.
    %
    % Anonymous functions copy the values of any variables they use at the
    % moment they are created. So this run's handle keeps this run's
    % KPth_run even after the loop moves on and KPth_run changes.
    sim_inputs(run_index) = sim_inputs(run_index).setPostSimFcn( ...
        @(sim_output) reduceSweepRun(sim_output, KPth_run, theta_ref, trace_time_step));
end

%% Run the Simulations
% Use parallel workers when there is more than one run. A single run is
% simply run here with sim, since starting workers would take longer
% than the run itself. The toolbox was already checked at the top.
if number_of_runs > 1
    % A parallel pool is a group of extra MATLAB sessions (workers)
    % running in the background. Each worker runs one simulation at a
    % time. Starting a pool takes a while, so an open pool of the right
    % size is reused.
    %
    % gcp('nocreate') returns the open pool, or an empty result if there
    % is none. 'nocreate' stops it from starting a default sized pool.
    current_pool = gcp('nocreate');
    if isempty(current_pool)
        parpool(max_workers);
    elseif current_pool.NumWorkers ~= max_workers
        delete(current_pool);
        parpool(max_workers);
    end

    % parsim hands the runs out to the workers and returns one output per
    % run, in the same order as sim_inputs.
    %   'TransferBaseWorkspaceVariables' copies this session's base
    %       workspace (bs, Ts_velocity, all the model constants, ...) to
    %       each worker. Workers start with an empty workspace, so without
    %       this the model could not find its variables.
    %   'AttachedFiles' sends reduceSweepRun.m to the workers so they can
    %       call it. which() gives the full path to the file.
    sim_outputs = parsim(sim_inputs, 'ShowProgress', 'on', ...
        'TransferBaseWorkspaceVariables', 'on', ...
        'AttachedFiles', {which('reduceSweepRun')});
else
    sim_outputs = sim(sim_inputs, 'ShowProgress', 'on');
end

% Free anything the Simulation Data Inspector is still holding
Simulink.sdi.clear;

%% Collect the Results
% Metric names returned by reduceSweepRun.m
metric_names = {'Overshoot_pct', 'Settle_ms', 'IAE_mrad_s', ...
                'VelTrackRMS', 'VelPeakErr', 'PeakIq_A', ...
                'HoldVelRMS', 'HoldIqP2P_A', 'HoldPosP2P_counts'};

% One row per run, one column per metric. Failed runs stay NaN.
metric_values = nan(number_of_runs, numel(metric_names));

% reduceSweepRun.m sets RunError to an empty string when a run works and
% to the error message when it fails. Failed runs are reported and
% skipped, so one bad gain combination does not stop the whole sweep.
for run_index = 1:number_of_runs
    run_error = sim_outputs(run_index).get('RunError');

    if ~isempty(run_error)
        fprintf('Run %d (wCL=%g, keso=%g) failed: %s\n', run_index, ...
            wCL_grid(run_index), keso_grid(run_index), run_error);
        continue;
    end

    for metric_index = 1:numel(metric_names)
        metric_values(run_index, metric_index) = ...
            sim_outputs(run_index).get(metric_names{metric_index});
    end
end

% Observer bandwidth times the sample time, wESO*Ts. Useful for seeing how
% close the observer is to the limit of the velocity loop sample rate.
wESO_Ts_list = keso_grid(:) .* wCL_grid(:) * Ts_velocity;

% Build the results table. The square brackets put the columns side by
% side: the four tuning columns first, then all of the metric columns.
% Every column is in run order because the grids were turned into
% columns with (:) and metric_values was filled row by row in run order.
% The 'VariableNames' list names the columns in that same order.
results = array2table( ...
    [wCL_grid(:), keso_grid(:), KPth_grid(:), wESO_Ts_list, metric_values], ...
    'VariableNames', [{'wCL_s', 'keso_s', 'KPth', 'wESO_Ts'}, metric_names]);

% Show the runs with the smallest current ripple while holding first
disp(sortrows(results, 'HoldIqP2P_A'));

% The saved variable names are kept short so older result files still
% load the same way
out = sim_outputs;
stopTime = stop_time;
save('sweepResults.mat', 'results', 'out', 'wCL_list', 'keso_list', ...
    'KPth_list', 'stopTime');

%% Figure 1: Velocity Loop Tuning Map
% Color map of velocity tracking RMS over wCL and keso, with dashed
% contour lines of constant wESO*Ts. Needs at least two values of both
% wCL and keso. Only the first KPth value is shown.
if numel(wCL_list) > 1 && numel(keso_list) > 1
    KPth_shown = KPth_list(1);
    results_for_KPth = results(results.KPth == KPth_shown, :);

    % Rearrange the table into a 2D grid for imagesc.
    % Rows are keso values, columns are wCL values. For each grid cell,
    % look for the table row with that keso and wCL. The == comparisons
    % give a true/false value for every row of the table, & keeps only the
    % rows where both are true, and any() checks that a match was found.
    % Cells with no matching run stay NaN and show as blank.
    tracking_rms_map = nan(numel(keso_list), numel(wCL_list));
    for keso_index = 1:numel(keso_list)
        for wCL_index = 1:numel(wCL_list)
            matching_row = results_for_KPth.keso_s == keso_list(keso_index) & ...
                           results_for_KPth.wCL_s  == wCL_list(wCL_index);
            if any(matching_row)
                tracking_rms_map(keso_index, wCL_index) = ...
                    results_for_KPth.VelTrackRMS(matching_row);
            end
        end
    end

    % imagesc draws the grid as colored squares. Passing wCL_list and
    % keso_list puts the real values on the axes instead of row and
    % column numbers. imagesc puts row 1 at the top like an image, so
    % 'YDir' 'normal' flips it to put the smallest keso at the bottom.
    figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 6.5 4.5]);
    imagesc(wCL_list, keso_list, tracking_rms_map);
    set(gca, 'YDir', 'normal');                             % small keso at the bottom
    axis tight;
    color_bar = colorbar;
    color_bar.Label.String = 'Velocity tracking RMS (rad/s)';
    hold on;

    % Contour lines of constant wESO*Ts
    % wESO*Ts can be calculated anywhere without simulating, so it is
    % calculated on a fine 200 x 200 grid to get smooth lines. meshgrid
    % works like ndgrid but in the x/y layout that contour expects.
    % contour draws a dashed white line at each value in contour_levels,
    % and clabel writes the value on each line. Moving toward the top
    % right of the map means a faster observer compared to the
    % velocity loop sample rate.
    [wCL_fine, keso_fine] = meshgrid( ...
        linspace(min(wCL_list),  max(wCL_list),  200), ...
        linspace(min(keso_list), max(keso_list), 200));
    wESO_Ts_fine = wCL_fine .* keso_fine * Ts_velocity;
    contour_levels = [0.4 0.6 0.8 1.0 1.2];
    [contour_matrix, contour_handle] = contour(wCL_fine, keso_fine, ...
        wESO_Ts_fine, contour_levels, 'w--');
    clabel(contour_matrix, contour_handle, 'Color', 'w', 'FontSize', 8);

    xlabel('\omega_{CL} (rad/s)');
    ylabel('k_{ESO} = \omega_{ESO}/\omega_{CL}');
    title(sprintf('Velocity-loop tuning map, K_{P\\theta} = %g s^{-1}', KPth_shown));
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 11, 'TickDir', 'out');
    % exportgraphics(gcf, 'velocity_tuning_map.pdf', 'ContentType', 'vector');
end

%% Figure 2: Position and Velocity Traces of the Best Runs
% Plots the three runs with the lowest velocity tracking RMS. The dashed
% lines are the velocity commanded by the position loop. To plot other
% runs, add their rows to runs_to_plot.
sorted_results = sortrows(results, 'VelTrackRMS');
number_to_plot = min(3, height(sorted_results));
runs_to_plot = sorted_results(1:number_to_plot, :);

figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 6.5 4.5]);
tiledlayout(2, 1, 'TileSpacing', 'compact');

position_axes = nexttile;
hold(position_axes, 'on');
ylabel(position_axes, '\theta_m (rad)');

velocity_axes = nexttile;
hold(velocity_axes, 'on');
ylabel(velocity_axes, '\omega_m (rad/s)');
xlabel(velocity_axes, 'Time (ms)');

for plot_index = 1:height(runs_to_plot)
    % Find which simulation output belongs to this row of the table.
    % Sorting changed the row order, so the table row number no longer
    % matches the run number. Instead, search the grids for the run with
    % the same wCL, keso, and KPth. find(..., 1) returns the first match.
    run_index = find(wCL_grid(:)  == runs_to_plot.wCL_s(plot_index) & ...
                     keso_grid(:) == runs_to_plot.keso_s(plot_index) & ...
                     KPth_grid(:) == runs_to_plot.KPth(plot_index), 1);

    time_ms = sim_outputs(run_index).get('t')*1e3;
    line_label = sprintf('\\omega_{CL}=%g, k_{ESO}=%g', ...
        wCL_grid(run_index), keso_grid(run_index));

    plot(position_axes, time_ms, sim_outputs(run_index).get('theta'), ...
        'DisplayName', line_label);
    velocity_line = plot(velocity_axes, time_ms, sim_outputs(run_index).get('omega'), ...
        'DisplayName', line_label);
    % Commanded velocity in the same color, hidden from the legend
    plot(velocity_axes, time_ms, sim_outputs(run_index).get('omega_cmd'), '--', ...
        'Color', velocity_line.Color, 'HandleVisibility', 'off');
end

% Dotted line at the position reference
yline(position_axes, theta_ref, ':k', 'HandleVisibility', 'off');
legend(position_axes, 'Location', 'southeast');
set([position_axes velocity_axes], 'FontName', 'Times New Roman', ...
    'FontSize', 11, 'TickDir', 'out');
% exportgraphics(gcf, 'velocity_tuning_traces.pdf', 'ContentType', 'vector');
