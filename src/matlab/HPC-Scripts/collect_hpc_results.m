function collect_hpc_results(run_folder)
%% Gather the summary of every scenario in one run into a single table
% On the cluster this runs automatically after all scenarios finish. You
% can also run it directly:
%   collect_hpc_results('results/hpc/run_20261201_0930')
%
% It writes <run_folder>/summary_all_scenarios.csv (opens in Excel) with
% one row per scenario, and lists any scenario that failed.

scenario_folders = dir(fullfile(run_folder, 'scenario_*'));
all_summaries = [];
failed_scenarios = {};

for folder_number = 1:length(scenario_folders)
    folder_name = scenario_folders(folder_number).name;
    results_file = fullfile(run_folder, folder_name, [folder_name '.mat']);
    error_file = fullfile(run_folder, folder_name, 'ERROR.txt');

    if exist(error_file, 'file')
        failed_scenarios{end + 1} = folder_name; %#ok<AGROW>
    elseif exist(results_file, 'file')
        % Load only the small summary, not the whole simulation output
        loaded = load(results_file, 'summary');
        if isempty(all_summaries)
            all_summaries = loaded.summary;
        else
            all_summaries(end + 1) = loaded.summary; %#ok<AGROW>
        end
    else
        failed_scenarios{end + 1} = [folder_name ' (no results: still running, or the job ran out of time or memory)']; %#ok<AGROW>
    end
end

if isempty(all_summaries)
    fprintf('No finished scenarios found in %s\n', run_folder);
else
    summary_table = struct2table(all_summaries);
    csv_file = fullfile(run_folder, 'summary_all_scenarios.csv');
    writetable(summary_table, csv_file);
    fprintf('Wrote %d scenarios to %s\n', height(summary_table), csv_file);
    disp(summary_table);
end

if ~isempty(failed_scenarios)
    fprintf('\nThese scenarios did not finish (see ERROR.txt and the Slurm log in logs/):\n');
    for failed_number = 1:length(failed_scenarios)
        fprintf('  %s\n', failed_scenarios{failed_number});
    end
end
end
