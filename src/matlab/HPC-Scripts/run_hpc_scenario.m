function run_hpc_scenario(scenario_number, output_folder, stop_time_override_seconds)
%% Run ONE scenario from hpc_scenarios.m and save its results
% On the cluster, each Slurm array task calls this with its own number:
%   run_hpc_scenario(5, '/home/<netid>/SE3-ADRC-FOC/src/results/hpc/run_20261201_0930')
%
% For a quick test on your own computer (a very short run, no windows):
%   run_hpc_scenario(5, 'results/local_test', 0.002)
%
% Inputs:
%   scenario_number            which scenario in hpc_scenarios.m (1, 2, 3, ...)
%   output_folder              where to save; a scenario_XX folder is made inside it
%   stop_time_override_seconds (optional) simulate this long instead of the
%                              scenario's stop time. Useful for quick tests
%                              and for measuring how fast the cluster runs.
%                              The ADRC_STOP_TIME_OVERRIDE environment
%                              variable does the same thing from Slurm.
%
% What it saves in <output_folder>/scenario_XX/:
%   scenario_XX.mat          simOut (every logged signal), the scenario and a summary
%   scenario_XX_summary.txt  the summary in plain text
%   figures/                 the plot_simulation_results figures (PDF, PNG, FIG)
%   ERROR.txt                only if the run failed (with the full error message)
%
% A note on variable names in this file:
% Because this is a function, every variable lives in this function's own
% workspace, not the base workspace. The scripts called below
% (plant_constants, controller_parameters, design_adrc_gains, ...) and the
% Simulink model all read and write variables here by name. So names like
% spring_constant, position_loop_gain, theta_ref, and drive_mode must stay
% exactly as they are. simOut, scenario, and summary are the names saved
% in the .mat file, and collect_hpc_results.m loads 'summary' by name.

%% Find the project and put it on the MATLAB path
% mfilename('fullpath') is the full path of this file (without .m), and
% fileparts strips off the file name to leave just its folder.
% This file is in src/matlab/HPC-Scripts, so src is two folders up ('..'
% means "the folder above"). setup_paths.m then adds every project folder
% to the path so the scripts and models below can be found from anywhere.
this_file_folder = fileparts(mfilename('fullpath'));
source_folder = fullfile(this_file_folder, '..', '..');
run(fullfile(source_folder, 'setup_paths.m'));

%% Pick the scenario
% hpc_scenarios() returns a struct array with one element per scenario.
% Check the number first so a typo gives a clear message instead of an
% "index exceeds" error.
scenarios = hpc_scenarios();
if scenario_number < 1 || scenario_number > length(scenarios)
    error('Scenario %d does not exist. hpc_scenarios.m has %d scenarios.', scenario_number, length(scenarios));
end
scenario = scenarios(scenario_number);

% Stop time, in order of priority:
%   1. the third input, if it was given and is not empty
%   2. the ADRC_STOP_TIME_OVERRIDE environment variable, if it is set
%   3. the scenario's own stop time
% nargin is the number of inputs the function was called with. getenv
% returns '' when the environment variable is not set. Environment
% variables are always text, so str2double turns it into a number.
stop_time_seconds = scenario.stop_time_seconds;
if nargin >= 3 && ~isempty(stop_time_override_seconds)
    stop_time_seconds = stop_time_override_seconds;
elseif ~isempty(getenv('ADRC_STOP_TIME_OVERRIDE'))
    stop_time_seconds = str2double(getenv('ADRC_STOP_TIME_OVERRIDE'));
end

% Make the output folder for this scenario, e.g. scenario_05.
% %02d pads the number to two digits so the folders sort in order.
scenario_folder = fullfile(output_folder, sprintf('scenario_%02d', scenario_number));
if ~exist(scenario_folder, 'dir')
    mkdir(scenario_folder);
end

% Path and start of the file name shared by every saved file, e.g.
% .../scenario_05/scenario_05. Each save adds its own ending.
file_base_name = fullfile(scenario_folder, sprintf('scenario_%02d', scenario_number));

fprintf('Scenario %d of %d: %s\n', scenario_number, length(scenarios), scenario.name);
fprintf('Model: %s, %s mode, %g s of motor time\n', scenario.model_name, scenario.simulation_mode, stop_time_seconds);

% Everything from here on is inside try/catch. If anything fails, the
% catch block at the bottom writes ERROR.txt before stopping.
try
    %% Keep this task's Simulink build files separate
    % Many tasks run at the same time from the same folder. Each one builds
    % its own accelerated model, so each gets its own build folder.
    % Without this, tasks would overwrite each other's build files.
    % fileGenControl changes where Simulink puts those files for this
    % MATLAB session only. 'createDir' makes the folder if it is missing.
    build_folder = fullfile(scenario_folder, 'simulink_build_files');
    Simulink.fileGenControl('set', 'CacheFolder', build_folder, 'CodeGenFolder', build_folder, 'createDir', true);

    %% Load the shared constants
    % These are scripts, not functions, so they create their variables
    % right here in this function's workspace.
    plant_constants;
    controller_parameters;

    %% Apply this scenario's settings
    % (The Code Analyzer marks some of these lines "might be unused".
    % They are used: the scripts and the Simulink model read them.)
    %
    % In hpc_scenarios.m, a setting of [] means "use the default". So each
    % setting below only replaces the default when it is not empty.

    % Spring ([] keeps the value from plant_constants.m)
    % The model needs the spring constant in N/m, so it is converted from
    % lbf/in here, the same way plant_constants.m does it.
    if ~isempty(scenario.spring_constant_lbf_per_inch)
        spring_constant_lbf_per_inch = scenario.spring_constant_lbf_per_inch;
        spring_constant = (spring_constant_lbf_per_inch * pound_force_to_newtons) / inches_to_meters;
    end

    % Controller tuning ([] keeps the value from controller_parameters.m)
    if ~isempty(scenario.position_loop_gain)
        position_loop_gain = scenario.position_loop_gain;
    end
    if ~isempty(scenario.velocity_closed_loop_bandwidth_rad_per_second)
        velocity_closed_loop_bandwidth_rad_per_second = scenario.velocity_closed_loop_bandwidth_rad_per_second;
    end
    if ~isempty(scenario.velocity_observer_bandwidth_multiplier)
        velocity_observer_bandwidth_multiplier = scenario.velocity_observer_bandwidth_multiplier;
    end
    if ~isempty(scenario.current_closed_loop_bandwidth_rad_per_second)
        current_closed_loop_bandwidth_rad_per_second = scenario.current_closed_loop_bandwidth_rad_per_second;
    end
    if ~isempty(scenario.current_observer_bandwidth_multiplier)
        current_observer_bandwidth_multiplier = scenario.current_observer_bandwidth_multiplier;
    end

    % The ADRC coefficients depend on the bandwidths above, so they must
    % be recomputed after any bandwidth changes. design_adrc_gains is a
    % script that reads the bandwidth variables from this workspace.
    design_adrc_gains;

    % Motion command: nut travel (mm) -> rotor angle (rad)
    % One motor revolution (2*pi rad) moves the nut one lead (mm), so
    % revolutions = travel / lead, and angle = revolutions * 2*pi.
    theta_ref = scenario.commanded_displacement_mm / ballscrew_lead_mm * 2*pi;

    % Load disturbance (the scenario number is the random seed, so noise
    % is different for each scenario but the same every time it is rerun)
    load_disturbance_data = make_load_disturbance(scenario.disturbance_type, ...
        scenario.disturbance_start_time_seconds, scenario.disturbance_size_newton_meters, ...
        scenario.disturbance_duration_seconds, stop_time_seconds, scenario_number);

    % Traditional stepper settings (only used by OpenLoop_TraditionalStepper)
    if strcmp(scenario.model_name, 'OpenLoop_TraditionalStepper')
        drive_mode = scenario.stepper_drive_mode;
        step_rate_steps_per_second = scenario.stepper_step_rate_steps_per_second;

        % The open loop model moves a number of steps in one direction,
        % so the signed travel is split into a direction and a size
        if scenario.commanded_displacement_mm >= 0
            step_direction = 1;
        else
            step_direction = -1;
        end
        open_loop_stepper_parameters;   % sets step_angle_degrees and the sequence tables

        % 360/step_angle_degrees = steps per revolution, and dividing by
        % the lead (mm per revolution) gives steps per mm of travel.
        % round() because the motor can only take whole steps.
        steps_per_mm = 360 / step_angle_degrees / ballscrew_lead_mm;
        number_of_steps_to_move = round(abs(scenario.commanded_displacement_mm) * steps_per_mm);
    end

    %% Simulate
    % 'SrcWorkspace', 'current' tells Simulink to read the constants from
    % this function (where the scripts above put them) instead of the base
    % workspace.
    load_system(scenario.model_name);
    simulation_mode_used = scenario.simulation_mode;

    % tic starts a stopwatch and toc reads it, to report the run time
    simulation_timer = tic;

    % Inner try/catch: if the simulation fails in accelerator mode, try
    % again in normal mode. Any other failure goes to the outer catch.
    try
        simOut = sim(scenario.model_name, 'StopTime', num2str(stop_time_seconds), ...
            'SimulationMode', simulation_mode_used, 'SrcWorkspace', 'current');
    catch accelerator_error
        % If the accelerated build fails on the cluster, run in normal mode
        % (slower, but always works) and note why.
        % If it was already in normal mode there is nothing to fall back
        % to, so rethrow sends the error on to the outer catch block.
        if strcmp(simulation_mode_used, 'normal')
            rethrow(accelerator_error);
        end
        fprintf('Accelerator mode failed (%s). Running in normal mode instead.\n', accelerator_error.message);
        simulation_mode_used = 'normal';
        simOut = sim(scenario.model_name, 'StopTime', num2str(stop_time_seconds), ...
            'SimulationMode', simulation_mode_used, 'SrcWorkspace', 'current');
    end
    wall_time_minutes = toc(simulation_timer) / 60;
    fprintf('Simulation done in %.1f minutes.\n', wall_time_minutes);

    %% Summary numbers
    % A small struct of the key settings and results. This is what
    % collect_hpc_results.m loads from every scenario and combines into
    % one table, so each field becomes a column in that table.
    % Every field must be a single number or a piece of text.
    summary.scenario_number = scenario_number;
    summary.name = scenario.name;
    summary.model_name = scenario.model_name;
    summary.simulation_mode = simulation_mode_used;
    summary.stop_time_seconds = stop_time_seconds;
    summary.wall_time_minutes = wall_time_minutes;
    summary.commanded_displacement_mm = scenario.commanded_displacement_mm;
    summary.spring_constant_lbf_per_inch = spring_constant_lbf_per_inch;
    summary.disturbance_type = scenario.disturbance_type;
    summary.position_loop_gain = position_loop_gain;
    summary.velocity_bandwidth_rad_per_second = velocity_closed_loop_bandwidth_rad_per_second;
    summary.current_bandwidth_rad_per_second = current_closed_loop_bandwidth_rad_per_second;

    % Final position and error (if the model logs the rotor angle)
    % simOut.who lists the names of everything that was logged. The
    % fields start as NaN so the summary has the same fields for every
    % model, even ones that do not log this signal.
    summary.final_position_mm = NaN;
    summary.final_position_error_mm = NaN;
    if any(strcmp(simOut.who, 'log_angle_rad_a'))
        logged_angle = simOut.get('log_angle_rad_a');
        % squeeze removes extra size 1 dimensions, double converts fixed
        % point data to normal numbers, and unwrap removes 2*pi jumps so
        % the angle is one continuous curve
        rotor_angle_rad = unwrap(double(squeeze(logged_angle.Data)));
        % Convert the last angle back to nut travel: rad / (2*pi) * lead
        summary.final_position_mm = rotor_angle_rad(end) * ballscrew_lead_mm / (2*pi);
        summary.final_position_error_mm = scenario.commanded_displacement_mm - summary.final_position_mm;
    end

    % Largest load torque at the motor shaft, spring + disturbance (the plant
    % logs it in every model, under the name motor_torque)
    summary.peak_load_torque_newton_meters = NaN;
    if any(strcmp(simOut.who, 'motor_torque'))
        logged_torque = simOut.get('motor_torque');
        summary.peak_load_torque_newton_meters = max(abs(double(squeeze(logged_torque.Data))));
    end

    %% Save
    % -v7.3 allows files larger than 2 GB (long runs)
    save([file_base_name '.mat'], 'simOut', 'scenario', 'summary', '-v7.3');
    write_summary_text_file([file_base_name '_summary.txt'], summary);

    %% Plot (hidden windows, saved to files)
    % plot_simulation_results takes its settings as one struct.
    % show_figures = false keeps the windows hidden, which is needed on
    % the cluster where there is no screen.
    plot_options.title_text = sprintf('Scenario %d: %s', scenario_number, scenario.name);
    plot_options.ballscrew_lead_mm = ballscrew_lead_mm;
    plot_options.current_limit_amps = Iq_limit;
    plot_options.holding_torque_newton_meters = T_holding;
    plot_options.save_folder = fullfile(scenario_folder, 'figures');
    plot_options.file_name_prefix = sprintf('S%02d', scenario_number);
    plot_options.show_figures = false;
    plot_simulation_results(simOut, plot_options);

    fprintf('Results saved in %s\n', scenario_folder);

    %% Clean up
    Simulink.fileGenControl('reset');   % put the build folder setting back
    bdclose(scenario.model_name);        % close the model so its build files can be deleted
    % The build files are not needed after the run. (Asking for the status
    % output means a file that cannot be deleted gives no error.)
    % 's' deletes the folder and everything inside it.
    build_files_deleted = rmdir(build_folder, 's'); %#ok<NASGU>

catch run_error
    % Write the full error to a file so it is easy to find, then stop with
    % an error so Slurm marks this task as FAILED.
    % getReport gives the full message including which file and line
    % failed. 'hyperlinks' 'off' keeps it as plain text for the file.
    % collect_hpc_results.m looks for ERROR.txt to list failed scenarios.
    error_file_id = fopen(fullfile(scenario_folder, 'ERROR.txt'), 'w');
    fprintf(error_file_id, 'Scenario %d (%s) failed:\n\n%s\n', scenario_number, scenario.name, ...
        getReport(run_error, 'extended', 'hyperlinks', 'off'));
    fclose(error_file_id);

    % Put the build folder setting back even though the run failed
    Simulink.fileGenControl('reset');

    % rethrow raises the same error again, so MATLAB exits with an error
    rethrow(run_error);
end
end


function write_summary_text_file(file_name, summary)
% Write every field of the summary as "name: value", one per line.
% fieldnames lists the field names of the struct, and
% summary.(field_name) reads the field whose name is stored in
% field_name. Text values are written with %s and numbers with %g.
text_file_id = fopen(file_name, 'w');
field_names = fieldnames(summary);

for field_number = 1:length(field_names)
    field_name = field_names{field_number};
    field_value = summary.(field_name);

    if ischar(field_value)
        fprintf(text_file_id, '%s: %s\n', field_name, field_value);
    else
        fprintf(text_file_id, '%s: %g\n', field_name, field_value);
    end
end

fclose(text_file_id);
end
