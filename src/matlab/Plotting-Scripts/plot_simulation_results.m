function plot_simulation_results(simOut, plot_options)
%% Plot the results of one simulation in a similar style to what is in my thesis
% Usage (the run scripts do this for you):
%   simOut = sim('DataCollection_FirstOrderADRC', 'StopTime', '0.01');
%   Configure Plotting Options for the collected simOut data
%   Example:
%   plot_options.title_text = 'Data Collection model';
%   plot_options.ballscrew_lead_mm = ballscrew_lead_mm;
%   plot_options.current_limit_amps = Iq_limit;
%   plot_options.holding_torque_newton_meters = T_holding;
%   plot_options.save_folder = '';                          % '' = do not save files
%   plot_options.file_name_prefix = 'DC';                   % start of each saved file name
%   plot_options.show_figures = true;                       % false = draw hidden (for the HPC or
%                                                           % while you work on other things and don't want a ton of figures popping up), then save and close
%   plot_simulation_results(simOut, plot_options);
%
% Inputs:
%   simOut        the output of sim(...)
%   plot_options  a struct with the fields listed above
%
% Figures it makes (each one only if its signals were logged):
%   summary         (a) position, (b) load torque, (c) current
%   velocity        actual, measured and commanded angular velocity
%   currents_dq     d- and q-axis current, commanded and measured
%   phase_currents  phase A and B current
%   phase_voltages  phase A and B commanded voltage
%   angle           commanded and actual rotor angle
%   torque_iq       load torque at the shaft and the q-axis current reference iq*
%
% The style (fonts, colors, sizes, panel letters, file formats) matches
% what was used in my thesis work
%
% Signal names: the To Workspace blocks write variables named
%   log_<what>_<a|m|c>   a = actual (plant), m = measured (sensors),
%                        c = commanded (controller output or target)
% A signal that is missing from simOut is skipped, so the same function works
% for every model, including the FPGA model, which logs only the plant.
% (To Workspace and Scope blocks break the HDL compatibility and should not be used
% on the FPGA model unless absolutely needed)

%% Plot style
style.figure_width_inches = 6.5;                    % full text width of a thesis page
style.summary_height_inches = 6.0;                  % 3-panel summary figure
style.single_height_inches = 3.2;                   % single-panel figures
style.two_panel_height_inches = 4.2;                % two-panel figures
style.font_name = 'Times New Roman';
% Linux computers often do not have Times New Roman. Use a similar
% font if it is missing. (Auto attempt below)
if ~any(strcmp(listfonts, 'Times New Roman'))
    style.font_name = 'Liberation Serif';
end

style.font_size = 10;
style.color_actual = [0.165 0.471 0.839];       % blue
style.color_second = [0.922 0.408 0.204];       % orange
style.color_third = [0.106 0.686 0.478];        % green
style.color_reference = [0.043 0.043 0.043];    % near black, dashed
style.color_limit = [0.45 0.45 0.43];           % grey, dotted
style.png_resolution_dpi = 1000;

% Show the figure windows, or draw them hidden (default: show)
style.figure_visible = 'on';
if isfield(plot_options, 'show_figures') && ~plot_options.show_figures
    style.figure_visible = 'off';
end

%% Read every signal the figures can use
[angle_time, angle_actual] = read_logged_signal(simOut, 'log_angle_rad_a');
[angle_command_time, angle_command] = read_logged_signal(simOut, 'log_position_target_rad_c');
[velocity_actual_time, velocity_actual] = read_logged_signal(simOut, 'log_angular_velocity_rad_per_sec_a');
[velocity_measured_time, velocity_measured] = read_logged_signal(simOut, 'log_angular_velocity_rad_per_sec_m');
[velocity_command_time, velocity_command] = read_logged_signal(simOut, 'log_angular_velocity_rad_per_sec_c');
[iq_measured_time, iq_measured] = read_logged_signal(simOut, 'log_quadrature_current_m');
[iq_command_time, iq_command] = read_logged_signal(simOut, 'log_quadrature_current_c');
[id_measured_time, id_measured] = read_logged_signal(simOut, 'log_direct_current_m');
[id_command_time, id_command] = read_logged_signal(simOut, 'log_direct_current_c');
[phase_a_actual_time, phase_a_actual] = read_logged_signal(simOut, 'log_phase_a_current_a');
[phase_b_actual_time, phase_b_actual] = read_logged_signal(simOut, 'log_phase_b_current_a');
[phase_a_measured_time, phase_a_measured] = read_logged_signal(simOut, 'log_phase_a_current_m');
[phase_b_measured_time, phase_b_measured] = read_logged_signal(simOut, 'log_phase_b_current_m');
[phase_a_voltage_time, phase_a_voltage] = read_logged_signal(simOut, 'log_phase_a_voltage_c');
[phase_b_voltage_time, phase_b_voltage] = read_logged_signal(simOut, 'log_phase_b_voltage_c');
[load_torque_time, load_torque] = read_logged_signal(simOut, 'log_motor_torque_a');
[disturbance_time, disturbance] = read_logged_signal(simOut, 'log_load_disturbance_a');
% The plant's 'motor_torque' variable is the SAME load torque (spring +
% disturbance at the shaft), logged inside the plant. The FPGA model only
% has this one, so use it when log_motor_torque_a is missing.
if isempty(load_torque)
    [load_torque_time, load_torque] = read_logged_signal(simOut, 'motor_torque');
end

%% Time axis: milliseconds for short runs, seconds for long runs
end_time_seconds = find_end_time(simOut);
if end_time_seconds < 0.5
    time_scale = 1e3;
    time_label = 'Time (ms)';
else
    time_scale = 1;
    time_label = 'Time (s)';
end
time_limits = [0 end_time_seconds * time_scale];

%% Convert rotor angle to linear position of the nut (mm)
% Unwrap in radians first, then convert to mm.
millimeters_per_radian = plot_options.ballscrew_lead_mm / (2*pi);
position_actual_mm = unwrap(angle_actual) * millimeters_per_radian;
position_command_mm = angle_command * millimeters_per_radian;

%% Figure 1: summary (position, load torque, current)
if ~isempty(angle_actual) || ~isempty(load_torque) || ...
        ~isempty(iq_measured) || ~isempty(phase_a_measured)
    [figure_handle, layout] = start_figure(style, 3, style.summary_height_inches);

    % (a) Position
    position_axes = start_axes(layout, style, 'Position (mm)', 'a');
    add_line(position_axes, angle_command_time * time_scale, position_command_mm, style.color_reference, '--', 1.0, 'Commanded');
    add_line(position_axes, angle_time * time_scale, position_actual_mm, style.color_actual, '-', 1.3, 'Actual');
    finish_axes(position_axes, style, 'southeast');

    % (b) Load torque on the motor shaft (spring + disturbance)
    torque_axes = start_axes(layout, style, 'Load torque (N\cdotm)', 'b');
    add_line(torque_axes, load_torque_time * time_scale, load_torque, style.color_actual, '-', 1.1, 'Total load');
    if any(disturbance ~= 0)
        add_line(torque_axes, disturbance_time * time_scale, disturbance, style.color_second, '-', 0.8, 'Disturbance');
    end
    add_limit_line(torque_axes, style, plot_options.holding_torque_newton_meters, ...
        sprintf('Holding torque %.1f N\\cdotm', plot_options.holding_torque_newton_meters));
    finish_axes(torque_axes, style, 'north');

    % (c) Current: q-axis current for the ADRC models, phase currents for
    % the open-loop stepper
    if ~isempty(iq_measured) || ~isempty(iq_command)
        current_axes = start_axes(layout, style, 'q-axis current (A)', 'c');
        add_line(current_axes, iq_measured_time * time_scale, iq_measured, style.color_actual, '-', 0.8, 'i_q measured');
        add_line(current_axes, iq_command_time * time_scale, iq_command, style.color_reference, '--', 1.0, 'i_q^* reference');
    else
        current_axes = start_axes(layout, style, 'Phase current (A)', 'c');
        add_line(current_axes, phase_a_measured_time * time_scale, phase_a_measured, style.color_actual, '-', 0.8, 'Phase A');
        add_line(current_axes, phase_b_measured_time * time_scale, phase_b_measured, style.color_second, '-', 0.8, 'Phase B');
    end
    add_limit_line(current_axes, style, plot_options.current_limit_amps, ...
        sprintf('\\pm%.2f A limit', plot_options.current_limit_amps));
    add_limit_line(current_axes, style, -plot_options.current_limit_amps, '');
    finish_axes(current_axes, style, 'north');

    finish_figure(layout, style, plot_options, time_label, time_limits, [position_axes torque_axes current_axes]);
    save_figure(figure_handle, plot_options, 'summary', style);
end

%% Figure 2: angular velocity
if ~isempty(velocity_actual) || ~isempty(velocity_measured)
    [figure_handle, layout] = start_figure(style, 1, style.single_height_inches);
    velocity_axes = start_axes(layout, style, 'Angular velocity (rad/s)', '');
    add_line(velocity_axes, velocity_measured_time * time_scale, velocity_measured, style.color_second, '-', 0.7, 'Measured (encoder)');
    add_line(velocity_axes, velocity_actual_time * time_scale, velocity_actual, style.color_actual, '-', 1.2, 'Actual (plant)');
    add_line(velocity_axes, velocity_command_time * time_scale, velocity_command, style.color_reference, '--', 1.0, 'Commanded');
    finish_axes(velocity_axes, style, 'best');
    finish_figure(layout, style, plot_options, time_label, time_limits, velocity_axes);
    save_figure(figure_handle, plot_options, 'velocity', style);
end

%% Figure 3: d- and q-axis currents
if ~isempty(iq_measured) || ~isempty(id_measured)
    [figure_handle, layout] = start_figure(style, 2, style.two_panel_height_inches);
    d_axis_axes = start_axes(layout, style, 'i_d (A)', 'a');
    add_line(d_axis_axes, id_measured_time * time_scale, id_measured, style.color_actual, '-', 0.8, 'Measured');
    add_line(d_axis_axes, id_command_time * time_scale, id_command, style.color_reference, '--', 1.0, 'Commanded');
    finish_axes(d_axis_axes, style, 'best');
    q_axis_axes = start_axes(layout, style, 'i_q (A)', 'b');
    add_line(q_axis_axes, iq_measured_time * time_scale, iq_measured, style.color_actual, '-', 0.8, 'Measured');
    add_line(q_axis_axes, iq_command_time * time_scale, iq_command, style.color_reference, '--', 1.0, 'Commanded');
    finish_axes(q_axis_axes, style, 'best');
    finish_figure(layout, style, plot_options, time_label, time_limits, [d_axis_axes q_axis_axes]);
    save_figure(figure_handle, plot_options, 'currents_dq', style);
end

%% Figure 4: phase currents
if ~isempty(phase_a_actual) || ~isempty(phase_a_measured)
    [figure_handle, layout] = start_figure(style, 2, style.two_panel_height_inches);
    phase_a_axes = start_axes(layout, style, 'Phase A current (A)', 'a');
    add_line(phase_a_axes, phase_a_actual_time * time_scale, phase_a_actual, style.color_actual, '-', 0.8, 'Actual');
    add_line(phase_a_axes, phase_a_measured_time * time_scale, phase_a_measured, style.color_second, '-', 0.8, 'Measured (ADC)');
    finish_axes(phase_a_axes, style, 'best');
    phase_b_axes = start_axes(layout, style, 'Phase B current (A)', 'b');
    add_line(phase_b_axes, phase_b_actual_time * time_scale, phase_b_actual, style.color_actual, '-', 0.8, 'Actual');
    add_line(phase_b_axes, phase_b_measured_time * time_scale, phase_b_measured, style.color_second, '-', 0.8, 'Measured (ADC)');
    finish_axes(phase_b_axes, style, 'best');
    finish_figure(layout, style, plot_options, time_label, time_limits, [phase_a_axes phase_b_axes]);
    save_figure(figure_handle, plot_options, 'phase_currents', style);
end

%% Figure 5: phase voltages (commanded)
if ~isempty(phase_a_voltage) || ~isempty(phase_b_voltage)
    [figure_handle, layout] = start_figure(style, 1, style.single_height_inches);
    voltage_axes = start_axes(layout, style, 'Phase voltage (V)', '');
    add_line(voltage_axes, phase_a_voltage_time * time_scale, phase_a_voltage, style.color_actual, '-', 1.0, 'Phase A');
    add_line(voltage_axes, phase_b_voltage_time * time_scale, phase_b_voltage, style.color_second, '--', 1.0, 'Phase B');
    finish_axes(voltage_axes, style, 'best');
    finish_figure(layout, style, plot_options, time_label, time_limits, voltage_axes);
    save_figure(figure_handle, plot_options, 'phase_voltages', style);
end

%% Figure 6: rotor angle
if ~isempty(angle_actual)
    [figure_handle, layout] = start_figure(style, 1, style.single_height_inches);
    angle_axes = start_axes(layout, style, 'Rotor angle (rad)', '');
    add_line(angle_axes, angle_command_time * time_scale, angle_command, style.color_reference, '--', 1.0, 'Commanded');
    add_line(angle_axes, angle_time * time_scale, unwrap(angle_actual), style.color_actual, '-', 1.2, 'Actual');
    finish_axes(angle_axes, style, 'southeast');
    finish_figure(layout, style, plot_options, time_label, time_limits, angle_axes);
    save_figure(figure_handle, plot_options, 'angle', style);
end

%% Figure 7: load torque and iq* (two panels instead of two y-axes)
if ~isempty(load_torque)
    if ~isempty(iq_command)
        number_of_panels = 2;
        figure_height_inches = style.two_panel_height_inches;
        panel_letter = 'a';
    else
        number_of_panels = 1;
        figure_height_inches = style.single_height_inches;
        panel_letter = '';
    end
    [figure_handle, layout] = start_figure(style, number_of_panels, figure_height_inches);
    load_torque_axes = start_axes(layout, style, 'Load torque (N\cdotm)', panel_letter);
    add_line(load_torque_axes, load_torque_time * time_scale, load_torque, style.color_actual, '-', 1.2, 'Load torque at the shaft');
    finish_axes(load_torque_axes, style, 'best');
    all_axes = load_torque_axes;
    if number_of_panels == 2
        iq_axes = start_axes(layout, style, 'i_q^* (A)', 'b');
        add_line(iq_axes, iq_command_time * time_scale, iq_command, style.color_reference, '-', 1.0, 'i_q^*');
        finish_axes(iq_axes, style, 'best');
        all_axes = [load_torque_axes iq_axes];
    end
    finish_figure(layout, style, plot_options, time_label, time_limits, all_axes);
    save_figure(figure_handle, plot_options, 'torque_iq', style);
end
end


%% ------------------------------------------------------------------------
%  Helper functions used above
%  ------------------------------------------------------------------------

function [time, values] = read_logged_signal(simOut, signal_name)
% Return the time and values of one logged signal as plain double columns.
% Returns two empty arrays if the signal was not logged.
time = [];
values = [];
logged_signal = [];

% To Workspace blocks save a variable with this name
if any(strcmp(simOut.who, signal_name))
    logged_signal = simOut.get(signal_name);
end

% Signal logging (right-click a line > Log Selected Signals) saves into
% logsout. The signal name must match.
if isempty(logged_signal) && any(strcmp(simOut.who, 'logsout'))
    logsout = simOut.get('logsout');
    if any(strcmp(logsout.getElementNames, signal_name))
        logged_element = logsout.get(signal_name);
        logged_signal = logged_element.Values;
    end
end

if isa(logged_signal, 'timeseries')
    time = double(logged_signal.Time(:));
    values = double(squeeze(logged_signal.Data));
    values = values(:);
end
end

function end_time_seconds = find_end_time(simOut)
% The simulation end time, read from the time vector the model saves
end_time_seconds = 0;
if any(strcmp(simOut.who, 'tout'))
    simulation_time = simOut.get('tout');
    end_time_seconds = simulation_time(end);
end
if end_time_seconds <= 0
    end_time_seconds = 1;
end
end

function [figure_handle, layout] = start_figure(style, number_of_rows, height_inches)
% A white, print-sized figure with panels stacked on top of each other
figure_handle = figure('Visible', style.figure_visible, 'Color', 'w', 'Units', 'inches', ...
    'Position', [1 1 style.figure_width_inches height_inches], ...
    'PaperUnits', 'inches', 'PaperSize', [style.figure_width_inches height_inches]);
layout = tiledlayout(figure_handle, number_of_rows, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
end

function axes_handle = start_axes(layout, style, y_label, panel_letter)
% The next panel, styled for publication, with an optional (a)/(b) letter
axes_handle = nexttile(layout);
hold(axes_handle, 'on');
set(axes_handle, 'FontName', style.font_name, 'FontSize', style.font_size, 'TickDir', 'out', ...
    'LineWidth', 0.6, 'Box', 'off', 'XGrid', 'on', 'YGrid', 'on', ...
    'GridAlpha', 0.12, 'GridColor', [0 0 0], 'Layer', 'top', ...
    'XColor', [0.2 0.2 0.2], 'YColor', [0.2 0.2 0.2]);
ylabel(axes_handle, y_label, 'FontName', style.font_name, 'FontSize', style.font_size);
if ~isempty(panel_letter)
    text(axes_handle, 0.01, 0.97, ['(' panel_letter ')'], 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'FontName', style.font_name, ...
        'FontSize', style.font_size, 'FontWeight', 'bold');
end
end

function add_line(axes_handle, time, values, color, line_style, line_width, legend_name)
% Plot one line. Does nothing if the signal was not logged.
if isempty(values)
    return
end
plot(axes_handle, time, values, line_style, 'Color', color, 'LineWidth', line_width, ...
    'DisplayName', legend_name);
end

function add_limit_line(axes_handle, style, value, label_text)
% A dotted horizontal line, for example a current limit
yline(axes_handle, value, ':', label_text, 'Color', style.color_limit, 'LineWidth', 1, ...
    'FontName', style.font_name, 'FontSize', style.font_size - 1, ...
    'LabelHorizontalAlignment', 'right', 'HandleVisibility', 'off');
end

function finish_axes(axes_handle, style, legend_location)
% Add a boxless legend if the panel has any lines, otherwise say why it is empty
if isempty(findobj(axes_handle, 'Type', 'line'))
    text(axes_handle, 0.5, 0.5, 'Not logged by this model', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'FontName', style.font_name, ...
        'FontSize', style.font_size, 'Color', style.color_limit);
    return
end
legend(axes_handle, 'Location', legend_location, 'Box', 'off', 'FontName', style.font_name, ...
    'FontSize', style.font_size - 1, 'AutoUpdate', 'off');
end

function finish_figure(layout, style, plot_options, time_label, time_limits, all_axes)
% Share one time axis between all panels and add the title
linkaxes(all_axes, 'x');
xlim(all_axes(1), time_limits);
for panel_number = 1:numel(all_axes) - 1
    set(all_axes(panel_number), 'XTickLabel', []);   % only the bottom panel shows time labels
end
xlabel(all_axes(end), time_label, 'FontName', style.font_name, 'FontSize', style.font_size);
if ~isempty(plot_options.title_text)
    title(layout, plot_options.title_text, 'FontName', style.font_name, ...
        'FontSize', style.font_size + 1, 'FontWeight', 'normal');
end
end

function save_figure(figure_handle, plot_options, figure_name, style)
% Save as a vector PDF, a 1000-dpi PNG and an editable .fig file.
% Saves nothing if plot_options.save_folder is empty.
% Hidden figures (show_figures = false) are closed afterwards to free memory.
if ~isempty(plot_options.save_folder)
    if ~exist(plot_options.save_folder, 'dir')
        mkdir(plot_options.save_folder);
    end
    file_base_name = fullfile(plot_options.save_folder, [plot_options.file_name_prefix '_' figure_name]);
    exportgraphics(figure_handle, [file_base_name '.pdf'], 'ContentType', 'vector', 'BackgroundColor', 'white');
    exportgraphics(figure_handle, [file_base_name '.png'], 'Resolution', style.png_resolution_dpi, 'BackgroundColor', 'white');
    % A hidden figure would also open hidden from its .fig file later.
    % This line makes the saved .fig become visible when you open it.
    set(figure_handle, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
    savefig(figure_handle, [file_base_name '.fig']);
end
if strcmp(style.figure_visible, 'off')
    close(figure_handle);
end
end
