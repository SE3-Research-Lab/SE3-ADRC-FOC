%% Print the numbered list of HPC scenarios (nothing is simulated here)
% Run this after editing hpc_scenarios.m to check:
%   - the scenario numbers (these are the numbers you give to Slurm),
%   - the settings of each scenario,
%   - a rough wall-time estimate, so you can set #SBATCH --time.
%
% Measure the cluster with a short test run 
% (see README.md, "Benchmark") before a big run.

this_script_folder = fileparts(mfilename('fullpath'));
run(fullfile(this_script_folder, '..', '..', 'setup_paths.m'));

scenarios = hpc_scenarios();

% Minutes of wall time per second of motor time, measured on the lab PC
minutes_per_motor_second_adrc_accelerator = 50;
minutes_per_motor_second_adrc_normal = 350;
minutes_per_motor_second_stepper_accelerator = 22;

fprintf('\n%d scenarios in hpc_scenarios.m\n\n', length(scenarios));
fprintf('%3s  %-40s %-32s %8s %9s %8s %-9s %10s\n', '#', 'Name', 'Model', 'Move(mm)', 'Spring', 'Stop(s)', 'Disturb', 'Est. hours');
longest_hours = 0;
for scenario_number = 1:length(scenarios)
    scenario = scenarios(scenario_number);

    if strcmp(scenario.model_name, 'OpenLoop_TraditionalStepper')
        minutes_per_motor_second = minutes_per_motor_second_stepper_accelerator;
    elseif strcmp(scenario.simulation_mode, 'normal')
        minutes_per_motor_second = minutes_per_motor_second_adrc_normal;
    else
        minutes_per_motor_second = minutes_per_motor_second_adrc_accelerator;
    end
    estimated_hours = scenario.stop_time_seconds * minutes_per_motor_second / 60;
    longest_hours = max(longest_hours, estimated_hours);

    if isempty(scenario.spring_constant_lbf_per_inch)
        spring_text = 'default';
    else
        spring_text = sprintf('%g', scenario.spring_constant_lbf_per_inch);
    end

    fprintf('%3d  %-40s %-32s %8.1f %9s %8.2f %-9s %10.1f\n', scenario_number, scenario.name, ...
        scenario.model_name, scenario.commanded_displacement_mm, spring_text, ...
        scenario.stop_time_seconds, scenario.disturbance_type, estimated_hours);
end
fprintf('\nLongest scenario: about %.1f hours. Set #SBATCH --time in slurm/run_hpc_scenarios.sbatch above this.\n', longest_hours);
fprintf('To run all of them on the cluster:  bash matlab/HPC-Scripts/slurm/submit_hpc_scenarios.sh 1-%d\n\n', length(scenarios));
