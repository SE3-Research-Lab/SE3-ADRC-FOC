function setup_paths()
%SETUP_PATHS  Put this project's models and scripts on the MATLAB path.
%   Run once per MATLAB session from any folder:
%       >> run('<path to>/src/setup_paths.m')
%   or, with src/ as the current folder:
%       >> setup_paths
%
%   Adds the ADRC models, their subsystem files and all script folders.
%   This replaces the original method of using the GUI to add the paths. 
%   This is needed on Tempest where the command line is the only interface for MATLAB

root = fileparts(mfilename('fullpath'));
folders = {
    fullfile(root, 'simulink', 'ADRC-model')
    fullfile(root, 'simulink', 'ADRC-model', 'subsystems')
    fullfile(root, 'simulink', 'pid-model')
    fullfile(root, 'simulink', 'open-loop-stepper-model')
    fullfile(root, 'matlab', 'FPGA-Scripts')
    fullfile(root, 'matlab', 'HPC-Scripts')
    fullfile(root, 'matlab', 'Local-Scripts')
    fullfile(root, 'matlab', 'Plotting-Scripts')
    };
addpath(folders{:});

% Remove any archive folders that an older session may have added.
p = strsplit(path, pathsep);
old = p(startsWith(p, root) & contains(p, [filesep 'archive']));
if ~isempty(old), rmpath(old{:}); end

% Every subsystem file must resolve to exactly one copy.
for name = {'adrc_harness', 'PWM_Generator'}
    hits = which(name{1}, '-all');
    hits = hits(endsWith(hits, '.slx'));
    if numel(hits) ~= 1
        warning('setup_paths:shadow', '%s.slx found %d times on the path:\n  %s', ...
            name{1}, numel(hits), strjoin(hits, '\n  '));
    end
end
fprintf('ADRC project paths added (root: %s)\n', root);
end
