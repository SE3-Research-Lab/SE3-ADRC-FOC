%% generatedFirstOrderPlots.m
% Publication-quality plots for the first-order MFP-ADRC stepper-motor
% simulation (runFirstOrderADRCMultiRateClock_V2.m + Simulink model).
%
% HOW TO USE
%   1. Run runFirstOrderADRCMultiRateClock_V2.m (in Local-Scripts) (creates the parameters).
%   2. Run the Simulink model so its SimulationOutput ("out") is in the
%      base workspace.
%   3. Run the "Setup" section and the "Load & decimate" section once.
%   4. Run any figure section on its own (Run Section / Ctrl+Enter).
%
%   Do NOT add "clear" to this script: it would delete the simulation output.
%   Requires MATLAB R2020b or newer (tiledlayout, exportgraphics, xline/yline).
%
% NOTATION                      LOGGED SIGNAL
%   theta^*      position ref.        log_position_target_rad_c
%   hat{theta}_m measured position    log_enc_count_m (or log_angle_rad_a)
%   Omega^*_m    velocity ref.        log_angular_velocity_rad_per_sec_c
%   hat{Omega}_f filtered velocity    log_angular_velocity_rad_per_sec_m
%   i_q^*, i_d^* current refs.        log_quadrature_current_c / log_direct_current_c
%   hat{i}_q, hat{i}_d measured       log_quadrature_current_m / log_direct_current_m

%% Setup: options, plot style and parameters
% ---- Data options --------------------------------------------------------
maxBuckets  = 4e5;        % decimation buckets per signal (see Load section)
thetaSource = 'encoder';  % 'encoder' -> log_enc_count_m, 'truth' -> log_angle_rad_a
posUnit     = 'mm';       % Figure 2 units: 'mm' (table, via ballscrew) or 'rad'

% ---- Time windows in seconds, [] = automatic / full simulation ----------
tWin.fig1 = [];           % e.g. [0 0.06]
tWin.fig2 = [];           % [] = automatic window around the position step
tWin.fig3 = [];           % e.g. [0 0.02]

% ---- Publication style ---------------------------------------------------
pub.export      = false;                    % true -> write PDFs to pub.outDir
pub.outDir      = fullfile(pwd, 'figures');
pub.contentType = 'vector';                 % 'image' -> smaller files for dense traces
pub.resolution  = 600;                      % dpi, used only for 'image'
pub.width       = 6.5;                      % figure width (in)
pub.fontSize    = 10;
pub.lw          = 1.25;                     % measured traces
pub.lwRef       = 1.0;                      % reference traces
pub.metricsBox  = true;                     % metrics text box on Figure 2

if strcmp(pub.contentType, 'image')
    pub.exportArgs = {'ContentType', 'image', 'Resolution', pub.resolution};
else
    pub.exportArgs = {'ContentType', 'vector'};
end
if pub.export && ~isfolder(pub.outDir), mkdir(pub.outDir); end

% Okabe-Ito colour-blind-safe palette
C.ref    = [0 0 0];
C.blue   = [0 114 178]/255;
C.verm   = [213 94 0]/255;
C.green  = [0 158 115]/255;
C.orange = [230 159 0]/255;
C.grey   = [0.55 0.55 0.55];

ms = 1e3;   % s -> ms

styleAx = @(ax) set(ax, 'FontSize', pub.fontSize, 'TickLabelInterpreter', 'latex', ...
    'LineWidth', 0.75, 'TickDir', 'out', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on', ...
    'GridAlpha', 0.15, 'XMinorTick', 'on', 'YMinorTick', 'on', 'Layer', 'top');
legOpts = {'Interpreter', 'latex', 'FontSize', pub.fontSize - 1, ...
    'Box', 'on', 'EdgeColor', [0.85 0.85 0.85]};

% ---- Parameters (fall back to the run-script values if missing) ---------
missingPar = {};
% Loop sample times (multirate):
%   Ts_sim      -> position loop
%   Ts_velocity -> velocity loop (ADRC)
%   Ts_current  -> current loops (ADRC)
% A missing Ts_sim falls back to the old single-rate Ts (or 2e-5 s);
% a missing Ts_velocity / Ts_current falls back to Ts_sim.
if ~exist('Ts_sim', 'var')
    if exist('Ts', 'var'), Ts_sim = Ts; else, Ts_sim = 2e-5; end
    missingPar{end+1} = 'Ts_sim';
end
if ~exist('Ts_velocity', 'var'),       Ts_velocity = Ts_sim;   missingPar{end+1} = 'Ts_velocity';       end
if ~exist('Ts_current', 'var'),        Ts_current = Ts_sim;    missingPar{end+1} = 'Ts_current';        end
if ~exist('KPth', 'var'),              KPth = 150;             missingPar{end+1} = 'KPth';              end
if ~exist('wCL_s', 'var'),             wCL_s = 750;            missingPar{end+1} = 'wCL_s';             end
if ~exist('wCL_iqd', 'var'),           wCL_iqd = 10000;        missingPar{end+1} = 'wCL_iqd';           end
if ~exist('CountsPerRev', 'var'),      CountsPerRev = 20000;   missingPar{end+1} = 'CountsPerRev';      end
if ~exist('ballscrew_lead_mm', 'var'), ballscrew_lead_mm = 5;  missingPar{end+1} = 'ballscrew_lead_mm'; end
if ~isempty(missingPar)
    warning('generatedFirstOrderPlots:defaults', ...
        'Not found in workspace, using fallback values: %s', strjoin(missingPar, ', '));
end

%% Load & decimate the logged signals (run once after each simulation)
% The model logs ~2e8 samples per signal, far too many to plot. Each signal
% is reduced to at most 2*maxBuckets points:
%   'minmax' keeps the min and max of every bucket, so PWM/current ripple
%            and peaks survive exactly (recommended for noisy signals).
%   'sample' keeps every b-th sample (used for smooth or wrapping signals).
if ~exist('out', 'var')
    error('No SimulationOutput "out" in the workspace. Run the Simulink model first.');
end
simOut = out;   % <- change if your SimulationOutput has a different name

sigList = {
    'log_position_target_rad_c',          'sample'
    'log_enc_count_m',                    'sample'
    'log_angle_rad_a',                    'sample'
    'log_angular_velocity_rad_per_sec_c', 'minmax'
    'log_angular_velocity_rad_per_sec_m', 'minmax'
    'log_quadrature_current_c',           'minmax'
    'log_quadrature_current_m',           'minmax'
    'log_direct_current_c',               'minmax'
    'log_direct_current_m',               'minmax'};

available = simOut.who;
S = struct();
for kSig = 1:size(sigList, 1)
    name = sigList{kSig, 1};
    mode = sigList{kSig, 2};
    if ~any(strcmp(available, name))
        warning('generatedFirstOrderPlots:missing', 'Signal %s not found in the output.', name);
        continue
    end
    tsObj = simOut.(name);
    t = tsObj.Time(:);
    y = tsObj.Data;
    y = y(:);
    N = numel(t);
    b = max(1, floor(N/maxBuckets));

    if b == 1 || strcmp(mode, 'sample')
        idx = unique([1:b:N, N])';
    else
        n = floor(N/b)*b;
        if isfi(y), yi = storedInteger(y); else, yi = y; end   % fast, order-preserving
        Yb = reshape(yi(1:n), b, []);
        [~, iMin] = min(Yb, [], 1);
        [~, iMax] = max(Yb, [], 1);
        off = (0:size(Yb, 2) - 1)*b;
        idx = unique([off + iMin, off + iMax, n+1:N])';        % sorted = time order
    end
    [tk, iu] = unique(t(idx), 'last');                          % strictly increasing time
    S.(name).t = tk;
    S.(name).y = double(y(idx(iu)));                            % real-world units
    fprintf('%-38s %11d -> %8d samples\n', name, N, numel(tk));
    clear tsObj t y yi Yb
end

% Measured position hat{theta}_m (rad)
switch lower(thetaSource)
    case 'encoder'
        th.t = S.log_enc_count_m.t;
        th.y = S.log_enc_count_m.y*(2*pi/CountsPerRev);
    case 'truth'
        th.t = S.log_angle_rad_a.t;
        th.y = unwrap(S.log_angle_rad_a.y);
    otherwise
        error('thetaSource must be ''encoder'' or ''truth''.');
end

% Ideal first-order position response: theta = K_Ptheta/(s + K_Ptheta) * theta^*
% (exact zero-order-hold discretisation on a fine uniform grid, so it is
% valid for any reference shape, not only a step)
pr = S.log_position_target_rad_c;
tg = linspace(pr.t(1), pr.t(end), 2e5)';
rg = interp1(pr.t, pr.y, tg, 'previous');
aG = exp(-KPth*(tg(2) - tg(1)));
thIdeal.t = tg;
thIdeal.y = filter(1 - aG, [1 -aG], rg, aG*th.y(1));
clear pr tg rg aG

%% Figure 1 - Cascade tracking: position, velocity and current loops
assert(exist('S', 'var') == 1, 'Run the Setup and Load sections first.');
w = tWin.fig1;  if isempty(w), w = [th.t(1) th.t(end)]; end
inW = @(s) s.t >= w(1) & s.t <= w(2);

fig = figure(1); clf(fig);
set(fig, 'Color', 'w', 'Units', 'inches', 'Position', [1 0.5 pub.width 7.0], ...
    'Name', 'Fig. 1 - Cascade tracking');
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% (a) Position: theta^*, hat{theta}_m and ideal first-order response
ax1 = nexttile(tl); hold(ax1, 'on');
s = th;                          k = inW(s);
hM = plot(ax1, s.t(k)*ms, s.y(k), '-',  'Color', C.blue, 'LineWidth', pub.lw);
s = thIdeal;                     k = inW(s);
hI = plot(ax1, s.t(k)*ms, s.y(k), ':',  'Color', C.verm, 'LineWidth', pub.lw + 0.25);
s = S.log_position_target_rad_c; k = inW(s);
hR = plot(ax1, s.t(k)*ms, s.y(k), '--', 'Color', C.ref,  'LineWidth', pub.lwRef);
ylabel(ax1, 'Position (rad)', 'Interpreter', 'latex');
title(ax1, '(a) Position loop', 'Interpreter', 'latex', 'FontWeight', 'normal');
legend(ax1, [hR hM hI], {'$\theta^*$', '$\hat{\theta}_m$', ...
    sprintf('Ideal first order, $K_{P\\theta} = %g$ rad/s', KPth)}, ...
    'Location', 'southeast', legOpts{:});

% (b) Velocity: Omega^*_m and hat{Omega}_f
ax2 = nexttile(tl); hold(ax2, 'on');
s = S.log_angular_velocity_rad_per_sec_m; k = inW(s);
hM = plot(ax2, s.t(k)*ms, s.y(k), '-',  'Color', C.blue, 'LineWidth', pub.lw);
s = S.log_angular_velocity_rad_per_sec_c; k = inW(s);
hR = plot(ax2, s.t(k)*ms, s.y(k), '--', 'Color', C.ref,  'LineWidth', pub.lwRef);
ylabel(ax2, 'Velocity (rad/s)', 'Interpreter', 'latex');
title(ax2, '(b) Velocity loop', 'Interpreter', 'latex', 'FontWeight', 'normal');
legend(ax2, [hR hM], {'$\Omega^*_m$', '$\hat{\Omega}_f$'}, 'Location', 'northeast', legOpts{:});

% (c) Current: i_q^*, hat{i}_q and hat{i}_d
ax3 = nexttile(tl); hold(ax3, 'on');
s = S.log_quadrature_current_m; k = inW(s);
hQ = plot(ax3, s.t(k)*ms, s.y(k), '-',  'Color', C.blue,  'LineWidth', pub.lw);
s = S.log_direct_current_m;     k = inW(s);
hD = plot(ax3, s.t(k)*ms, s.y(k), '-',  'Color', C.green, 'LineWidth', pub.lw);
s = S.log_quadrature_current_c; k = inW(s);
hR = plot(ax3, s.t(k)*ms, s.y(k), '--', 'Color', C.ref,   'LineWidth', pub.lwRef);
ylabel(ax3, 'Current (A)', 'Interpreter', 'latex');
title(ax3, '(c) Current loop', 'Interpreter', 'latex', 'FontWeight', 'normal');
legend(ax3, [hR hQ hD], {'$i_q^*$', '$\hat{i}_q$', '$\hat{i}_d$'}, 'Location', 'northeast', legOpts{:});

axs = [ax1 ax2 ax3];
linkaxes(axs, 'x');  xlim(ax3, w*ms);
xticklabels(ax1, {});  xticklabels(ax2, {});
xlabel(ax3, 'Time (ms)', 'Interpreter', 'latex');
styleAx(axs);
set(axs, 'TitleHorizontalAlignment', 'left');

if pub.export
    exportgraphics(fig, fullfile(pub.outDir, 'fig1_cascade_tracking.pdf'), pub.exportArgs{:});
end

%% Figure 2 - Position step response and rise time
% Rise time is 10-90 % of the step from the measured position, interpolated
% between samples. Settling time uses a 2 % band around the final reference.
% Assumes the position reference is a step (stepTime/theta_ref in the run script).
assert(exist('S', 'var') == 1, 'Run the Setup and Load sections first.');
switch lower(posUnit)
    case 'mm'
        pScale = ballscrew_lead_mm/(2*pi);
        yLab = 'Table position $x$ (mm)';
        refLab = '$x^*$';       measLab = '$\hat{x}_m$';
    otherwise
        pScale = 1;
        yLab = 'Angular position $\theta$ (rad)';
        refLab = '$\theta^*$';  measLab = '$\hat{\theta}_m$';
end

% Step instant from the reference
ref = S.log_position_target_rad_c;
iS = find(abs(ref.y - ref.y(1)) > 1e-9*max(1, max(abs(ref.y))), 1);
if isempty(iS), tStep = ref.t(1); else, tStep = ref.t(iS); end

tP = th.t;  yP = th.y*pScale;
rf = ref.y(end)*pScale;
y0 = interp1(tP, yP, tStep, 'linear', yP(1));
dY = rf - y0;
if dY == 0, error('The position reference has no step; rise time is undefined.'); end
sg = sign(dY);

% 10 % and 90 % crossing times
lv = y0 + [0.1 0.9]*dY;
tc = nan(1, 2);
for j = 1:2
    kk = find(tP >= tStep & sg*(yP - lv(j)) >= 0, 1);
    if isempty(kk), continue; end
    if kk > 1 && yP(kk) ~= yP(kk-1)
        tc(j) = tP(kk-1) + (lv(j) - yP(kk-1))*(tP(kk) - tP(kk-1))/(yP(kk) - yP(kk-1));
    else
        tc(j) = tP(kk);
    end
end
tRise = tc(2) - tc(1);

% Settling time (2 %), overshoot and steady-state error
kOut = find(tP >= tStep & abs(yP - rf) > 0.02*abs(dY), 1, 'last');
if isempty(kOut),         tSettle = 0;
elseif kOut == numel(tP), tSettle = NaN;          % not settled within the run
else,                     tSettle = tP(kOut+1) - tStep;
end
Mp  = max(0, max(sg*(yP(tP >= tStep) - rf)))/abs(dY)*100;
eSS = rf - yP(end);
tRiseIdeal   = log(9)/KPth;
tSettleIdeal = log(50)/KPth;

% Plot window
w = tWin.fig2;
if isempty(w)
    Tw = max([6/KPth, 1.3*tSettle, 2*(tc(2) - tStep)]);   % max() ignores NaN
    w  = [max(tStep - 0.05*Tw, tP(1)), tStep + Tw];
end
inW = @(s) s.t >= w(1) & s.t <= w(2);

fig = figure(2); clf(fig);
set(fig, 'Color', 'w', 'Units', 'inches', 'Position', [1 1 pub.width 3.6], ...
    'Name', 'Fig. 2 - Position step response');
ax = axes(fig); hold(ax, 'on');

k = inW(th);
hM = plot(ax, tP(k)*ms, yP(k), '-', 'Color', C.blue, 'LineWidth', pub.lw);
kI = inW(thIdeal);
hI = plot(ax, thIdeal.t(kI)*ms, thIdeal.y(kI)*pScale, ':', 'Color', C.verm, 'LineWidth', pub.lw + 0.25);
kR = inW(ref);
hR = plot(ax, ref.t(kR)*ms, ref.y(kR)*pScale, '--', 'Color', C.ref, 'LineWidth', pub.lwRef);

lvLab = {'10\%', '90\%'};
for j = 1:2
    yline(ax, lv(j), ':', lvLab{j}, 'Color', C.grey, 'LineWidth', 0.75, 'Interpreter', 'latex', ...
        'LabelHorizontalAlignment', 'left', 'FontSize', pub.fontSize - 1, 'HandleVisibility', 'off');
    if isfinite(tc(j))
        xline(ax, tc(j)*ms, ':', 'Color', C.grey, 'LineWidth', 0.75, 'HandleVisibility', 'off');
        plot(ax, tc(j)*ms, lv(j), 'o', 'MarkerSize', 5, 'MarkerFaceColor', C.blue, ...
            'MarkerEdgeColor', 'w', 'HandleVisibility', 'off');
    end
end
if all(isfinite(tc))
    yB = y0 + 0.04*dY;   % rise-time bracket just above the initial value
    plot(ax, tc*ms, [yB yB], '-', 'Color', C.ref, 'LineWidth', 0.75, 'HandleVisibility', 'off');
    text(ax, tc(2)*ms, yB, sprintf('$\\;t_r = %.2f$ ms', tRise*ms), 'Interpreter', 'latex', ...
        'FontSize', pub.fontSize, 'VerticalAlignment', 'middle');
end

if pub.metricsBox
    if isnan(tSettle), sStr = 'not settled'; else, sStr = sprintf('%.1f ms', tSettle*ms); end
    txt = {sprintf('$t_r$ (10--90\\%%): %.2f ms', tRise*ms), ...
           sprintf('Ideal $t_r = \\ln 9 / K_{P\\theta}$: %.2f ms', tRiseIdeal*ms), ...
           sprintf('$t_s$ (2\\%%): %s', sStr), ...
           sprintf('Overshoot: %.2f\\%%', Mp)};
    text(ax, 0.98, 0.32, txt, 'Units', 'normalized', 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'bottom', 'Interpreter', 'latex', 'FontSize', pub.fontSize - 1, ...
        'BackgroundColor', 'w', 'EdgeColor', [0.85 0.85 0.85], 'Margin', 3);
end

pad = 0.08*abs(dY);
yAll = [yP(k); rf; y0];
ylim(ax, [min(yAll) - pad, max(yAll) + pad]);
xlim(ax, w*ms);
xlabel(ax, 'Time (ms)', 'Interpreter', 'latex');
ylabel(ax, yLab, 'Interpreter', 'latex');
legend(ax, [hR hM hI], {refLab, measLab, ...
    sprintf('Ideal first order, $K_{P\\theta} = %g$ rad/s', KPth)}, ...
    'Location', 'southeast', legOpts{:});
styleAx(ax);

fprintf('\nPosition step response (%s)\n', posUnit);
fprintf('  Step: %.4g -> %.4g %s at t = %.3f ms\n', y0, rf, posUnit, tStep*ms);
fprintf('  Rise time (10-90%%)   : %8.3f ms   (ideal %.3f ms)\n', tRise*ms, tRiseIdeal*ms);
fprintf('  Settling time (2%%)   : %8.3f ms   (ideal %.3f ms)\n', tSettle*ms, tSettleIdeal*ms);
fprintf('  Overshoot            : %8.3f %%\n', Mp);
fprintf('  Final error          : %8.4g %s\n', eSS, posUnit);

if pub.export
    exportgraphics(fig, fullfile(pub.outDir, 'fig2_position_step.pdf'), pub.exportArgs{:});
end

%% Figure 3 - dq-axis current tracking
assert(exist('S', 'var') == 1, 'Run the Setup and Load sections first.');
w = tWin.fig3;  if isempty(w), w = [S.log_quadrature_current_m.t(1) S.log_quadrature_current_m.t(end)]; end
inW = @(s) s.t >= w(1) & s.t <= w(2);

fig = figure(3); clf(fig);
set(fig, 'Color', 'w', 'Units', 'inches', 'Position', [1 1 pub.width 4.8], ...
    'Name', 'Fig. 3 - dq currents');
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% (a) q-axis
ax1 = nexttile(tl); hold(ax1, 'on');
s = S.log_quadrature_current_m; k = inW(s);
hM = plot(ax1, s.t(k)*ms, s.y(k), '-',  'Color', C.blue, 'LineWidth', pub.lw);
s = S.log_quadrature_current_c; k = inW(s);
hR = plot(ax1, s.t(k)*ms, s.y(k), '--', 'Color', C.ref,  'LineWidth', pub.lwRef);
ylabel(ax1, '$i_q$ (A)', 'Interpreter', 'latex');
title(ax1, '(a) Quadrature axis', 'Interpreter', 'latex', 'FontWeight', 'normal');
legend(ax1, [hR hM], {'$i_q^*$', '$\hat{i}_q$'}, 'Location', 'northeast', legOpts{:});

% (b) d-axis
ax2 = nexttile(tl); hold(ax2, 'on');
s = S.log_direct_current_m; k = inW(s);
hM = plot(ax2, s.t(k)*ms, s.y(k), '-',  'Color', C.green, 'LineWidth', pub.lw);
s = S.log_direct_current_c; k = inW(s);
hR = plot(ax2, s.t(k)*ms, s.y(k), '--', 'Color', C.ref,   'LineWidth', pub.lwRef);
ylabel(ax2, '$i_d$ (A)', 'Interpreter', 'latex');
title(ax2, '(b) Direct axis', 'Interpreter', 'latex', 'FontWeight', 'normal');
legend(ax2, [hR hM], {'$i_d^*$', '$\hat{i}_d$'}, 'Location', 'northeast', legOpts{:});

axs = [ax1 ax2];
linkaxes(axs, 'x');  xlim(ax2, w*ms);
xticklabels(ax1, {});
xlabel(ax2, 'Time (ms)', 'Interpreter', 'latex');
styleAx(axs);
set(axs, 'TitleHorizontalAlignment', 'left');

if pub.export
    exportgraphics(fig, fullfile(pub.outDir, 'fig3_dq_currents.pdf'), pub.exportArgs{:});
end

%% Figure 4 - Designed closed-loop response of each loop in isolation
% Each loop is evaluated on its own (outer loops open, inner loops ideal),
% computed from the controller parameters rather than the cascaded run.
%   ADRC loops: designed closed-loop pole z_CL = exp(-w_CL*T), so a unit
%     step gives y[k] = 1 - z_CL^k. This is the reference response the
%     first-order ADRC imposes when b0 matches the plant and the ESO has
%     converged (the ESO poles shape disturbance rejection, not tracking).
%   Position loop: P controller around an ideal velocity loop, i.e. a
%     first-order response with bandwidth K_Ptheta.
% Multirate: each loop is discretised at its own sample time
%   current -> Ts_current, velocity -> Ts_velocity, position -> Ts_sim.
assert(exist('Ts_sim', 'var') == 1 && exist('Ts_velocity', 'var') == 1 && ...
    exist('Ts_current', 'var') == 1, 'Run the Setup section first.');
loopTs = [Ts_current, Ts_velocity, Ts_sim];   % sample time of [current, velocity, position] loop (s)

loops = struct( ...
    'name', {'Current', 'Velocity', 'Position'}, ...
    'lab',  {sprintf('Current (ADRC), $\\omega_{CL} = %g$ rad/s', wCL_iqd), ...
             sprintf('Velocity (ADRC), $\\omega_{CL} = %g$ rad/s', wCL_s), ...
             sprintf('Position (P), $K_{P\\theta} = %g$ rad/s', KPth)}, ...
    'w',    {wCL_iqd, wCL_s, KPth}, ...
    'Ts',   num2cell(loopTs), ...
    'col',  {C.blue, C.green, C.verm});

for j = 1:numel(loops)
    z = exp(-loops(j).w*loops(j).Ts);
    loops(j).z   = z;
    loops(j).tau = 1/loops(j).w;
    loops(j).t10 = ceil(log(0.9)/log(z))*loops(j).Ts;
    loops(j).t90 = ceil(log(0.1)/log(z))*loops(j).Ts;
    loops(j).tr  = loops(j).t90 - loops(j).t10;
    loops(j).ts  = ceil(log(0.02)/log(z))*loops(j).Ts;
end

fig = figure(4); clf(fig);
set(fig, 'Color', 'w', 'Units', 'inches', 'Position', [1 1 pub.width 3.2], ...
    'Name', 'Fig. 4 - Isolated loop response');
tl = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

% (a) Normalised step responses on a log time axis
ax1 = nexttile(tl, [1 2]); hold(ax1, 'on');
h = gobjects(1, numel(loops));
for j = 1:numel(loops)
    kMax = ceil(10*loops(j).tau/loops(j).Ts);
    if kMax <= 5000      % show the discrete samples
        kk = (1:kMax)';
        tt = kk*loops(j).Ts;
        h(j) = stairs(ax1, tt*ms, 1 - loops(j).z.^kk, '-', 'Color', loops(j).col, 'LineWidth', pub.lw);
    else                 % very fine sampling: continuous curve is identical
        tt = logspace(log10(loops(j).Ts), log10(10*loops(j).tau), 2000)';
        h(j) = plot(ax1, tt*ms, 1 - exp(-loops(j).w*tt), '-', 'Color', loops(j).col, 'LineWidth', pub.lw);
    end
    t1090 = [loops(j).t10 loops(j).t90];
    y1090 = 1 - loops(j).z.^round(t1090/loops(j).Ts);
    plot(ax1, t1090*ms, y1090, 'o', 'MarkerSize', 5, 'MarkerFaceColor', loops(j).col, ...
        'MarkerEdgeColor', 'w', 'HandleVisibility', 'off');
end
yline(ax1, 0.1, ':', '10\%', 'Color', C.grey, 'LineWidth', 0.75, 'Interpreter', 'latex', ...
    'LabelHorizontalAlignment', 'left', 'FontSize', pub.fontSize - 1, 'HandleVisibility', 'off');
yline(ax1, 0.9, ':', '90\%', 'Color', C.grey, 'LineWidth', 0.75, 'Interpreter', 'latex', ...
    'LabelHorizontalAlignment', 'left', 'FontSize', pub.fontSize - 1, 'HandleVisibility', 'off');
set(ax1, 'XScale', 'log');
xlim(ax1, [0.5*min([loops.Ts]), 10*max([loops.tau])]*ms);
ylim(ax1, [0 1.05]);
xlabel(ax1, 'Time (ms)', 'Interpreter', 'latex');
ylabel(ax1, 'Normalized response $y/r$', 'Interpreter', 'latex');
title(ax1, '(a) Unit-step response', 'Interpreter', 'latex', 'FontWeight', 'normal');
legend(ax1, h, {loops.lab}, 'Location', 'northwest', legOpts{:});

% (b) Response-time metrics
ax2 = nexttile(tl); hold(ax2, 'on');
x = 1:numel(loops);
hTau = plot(ax2, x, [loops.tau]*ms, 'd', 'MarkerSize', 6, 'Color', C.grey, 'LineWidth', 1);
hTr  = plot(ax2, x, [loops.tr]*ms,  'o', 'MarkerSize', 6, 'MarkerFaceColor', C.ref, 'Color', C.ref);
hTs  = plot(ax2, x, [loops.ts]*ms,  's', 'MarkerSize', 6, 'Color', C.ref, 'LineWidth', 1);
for j = 1:numel(loops) - 1   % bandwidth separation between neighbouring loops
    text(ax2, j + 0.5, sqrt(loops(j).tr*loops(j+1).tr)*ms, ...
        sprintf('$\\times%.1f$', loops(j).w/loops(j+1).w), 'Interpreter', 'latex', ...
        'HorizontalAlignment', 'center', 'FontSize', pub.fontSize - 1, 'Color', C.grey);
end
set(ax2, 'YScale', 'log', 'XTick', x, 'XTickLabel', {loops.name}, 'XLim', [0.5 numel(loops) + 0.5]);
ylabel(ax2, 'Time (ms)', 'Interpreter', 'latex');
title(ax2, '(b) Response times', 'Interpreter', 'latex', 'FontWeight', 'normal');
legend(ax2, [hTau hTr hTs], {'$\tau = 1/\omega$', '$t_r$ (10--90\%)', '$t_s$ (2\%)'}, ...
    'Location', 'northwest', legOpts{:});

styleAx([ax1 ax2]);
set(ax2, 'XMinorTick', 'off', 'XGrid', 'off');
set([ax1 ax2], 'TitleHorizontalAlignment', 'left');

loopTable = table(string({loops.name})', [loops.w]', [loops.Ts]'*1e6, [loops.tau]'*ms, ...
    [loops.tr]'*ms, [loops.ts]'*ms, 'VariableNames', ...
    {'Loop', 'Bandwidth_rad_s', 'Ts_us', 'Tau_ms', 'RiseTime_ms', 'Settling2pct_ms'});
fprintf('\nDesigned closed-loop response of each loop in isolation\n');
disp(loopTable);

if pub.export
    exportgraphics(fig, fullfile(pub.outDir, 'fig4_isolated_loop_response.pdf'), pub.exportArgs{:});
end