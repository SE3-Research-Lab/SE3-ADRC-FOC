%% Print the AXI4-Lite register values for the FPGA controller
% The FPGA controller (FPGA_Compatible_FirstOrderADRC) gets its gains and
% commands from Linux through AXI4-Lite registers. Linux must write the RAW
% integer that stands for each fixed-point value, not the real number.
%
% For a fixed-point type fixdt(signed, 32, fraction_bits):
%     raw integer = round(real value * 2^fraction_bits)
% Example: ParamType = fixdt(1,32,20), so a gain of 1.5 is written as
%     1.5 * 2^20 = 1572864 = 0x00180000
%
% This script runs plant_constants and controller_parameters, then prints
% every register: its address offset (from the IP core base address), the
% real value and the raw 32-bit value to write.
%
% IMPORTANT - the ADRC gains are a group of 15 registers with a STROBE:
%   1. write all 15 gain registers (0x200 to 0x238)
%   2. then write 1 to the strobe register (0x240)
% The controller keeps using the old gains until the strobe is written, so
% it never runs with a mix of old and new gains. The new gains take effect
% at the start of the next control period.
%
% The addresses come from the generated C header
% (ipcore/<name>/include/<name>_addr.h). If you change the port mapping in
% the model, check them against that file.

clear; clc;
this_script_folder = fileparts(mfilename('fullpath'));
source_folder = fullfile(this_script_folder, '..', '..');
run(fullfile(source_folder, 'setup_paths.m'));
plant_constants;
controller_parameters;

%% The 15 ADRC gains, in the order the model's Mux puts them
% (FPGA_Compatible_FirstOrderADRC, root level, block "adrc_gain_vector")
gain_names = {
    'KPth         position loop gain'
    'k1_s/bs      velocity ADRC'
    'beta_s(1)    velocity ADRC'
    'beta_s(2)    velocity ADRC'
    'gam_s(1)     velocity ADRC'
    'gam_s(2)     velocity ADRC'
    'alpha_s(1)   velocity ADRC'
    'alpha_s(2)   velocity ADRC'
    'k1_iqd/biq   current ADRC'
    'beta_iqd(1)  current ADRC'
    'beta_iqd(2)  current ADRC'
    'gam_iqd(1)   current ADRC'
    'gam_iqd(2)   current ADRC'
    'alpha_iqd(1) current ADRC'
    'alpha_iqd(2) current ADRC'
    };
gain_values = [KPth, k1_s/bs, beta_s(1), beta_s(2), gam_s(1), gam_s(2), ...
    alpha_s(1), alpha_s(2), k1_iqd/biq, beta_iqd(1), beta_iqd(2), ...
    gam_iqd(1), gam_iqd(2), alpha_iqd(1), alpha_iqd(2)];

gain_fraction_bits = ParamType.FractionLength;   % 20
first_gain_address = hex2dec('200');
gain_strobe_address = hex2dec('240');

fprintf('ADRC gains (type ParamType = fixdt(1,32,%d), raw = value * 2^%d)\n', gain_fraction_bits, gain_fraction_bits);
fprintf('%-8s %-28s %16s %14s %12s\n', 'Offset', 'Gain', 'Real value', 'Raw integer', 'Raw hex');
for gain_number = 1:length(gain_values)
    address = first_gain_address + 4 * (gain_number - 1);
    raw_value = round(gain_values(gain_number) * 2^gain_fraction_bits);
    print_register_line(address, gain_names{gain_number}, gain_values(gain_number), raw_value);
end
fprintf('0x%03X    %-28s write 1 AFTER all 15 gains\n\n', gain_strobe_address, 'adrc_gains STROBE');

%% Single registers (each one takes effect as soon as it is written)
fprintf('Commands and settings\n');
fprintf('%-8s %-28s %16s %14s %12s\n', 'Offset', 'Register', 'Real value', 'Raw integer', 'Raw hex');
print_register_line(hex2dec('100'), 'Position Target (rad)', theta_ref, round(theta_ref * 2^PosType.FractionLength));
print_register_line(hex2dec('104'), 'id_ref (A)', 0, 0);
print_register_line(hex2dec('108'), 'adc_phase_a_offset (counts)', ADC_Offset, round(ADC_Offset));
print_register_line(hex2dec('10C'), 'adc_phase_b_offset (counts)', ADC_Offset, round(ADC_Offset));
print_register_line(hex2dec('110'), 'preset_val (counts)', 0, 0);
print_register_line(hex2dec('114'), 'preset_en (0/1)', 0, 0);
print_register_line(hex2dec('118'), 'elec_zero (0/1)', 0, 0);
print_register_line(hex2dec('11C'), 'angle_override (not used yet)', 0, 0);
print_register_line(hex2dec('120'), 'override_en (not used yet)', 0, 0);
print_register_line(hex2dec('124'), 'pos_freeze (not used yet)', 0, 0);
fprintf('\nPosition Target uses PosType = fixdt(1,32,%d). id_ref uses ParamType.\n', PosType.FractionLength);


function print_register_line(address, register_name, real_value, raw_value)
% Show one register. Negative values are written as two's complement, so
% the hex column shows the 32-bit pattern Linux should write.
raw_32_bit_pattern = mod(raw_value, 2^32);
fprintf('0x%03X    %-28s %16.8g %14d   0x%08X\n', address, register_name, real_value, raw_value, raw_32_bit_pattern);
end
