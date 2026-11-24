%% Generate the FPGA controller as a Vivado IP core (AMD Kria KR260)
% This turns the "Stepper Motor FOC Controller" subsystem of
% FPGA_Compatible_FirstOrderADRC into VHDL and packages it as a Vivado IP
% core with an AXI4-Lite register interface. You then add the IP core to
% the KR260 block design in vivado_project/ and connect it to the Zynq.
%
% What you get (inside hdl_project_folder below):
%   ipcore/StepperMo_ip_v1_0/          the IP core to add to Vivado
%   ipcore/.../include/*_addr.h        C header with the register addresses
%   ipcore/.../doc/*_report.html       IP core report (ports, registers)
%   hdlsrc/FPGA_Compatible_FirstOrderADRC/
%       *.vhd                          the generated VHDL
%       *_constraints.xdc              multicycle timing constraints
%       gm_*.slx                       model of the generated hardware
%       gm_*_vnl.slx                   validation model (compares the two)
%       html/                          code generation and resource reports
%
% Before running:
%   1. Vivado must be installed. Set its path in vivado_executable below.
%   2. Check the HDL settings are still right: the model's HDL Code
%      Generation settings target the KR260 part xck26-sfvc784-2LV-c at
%      200 MHz. See simulink/ADRC-model/docs/hdl_readiness_report.md.
%
% It takes about 3 minutes (longer if you also build the bitstream).

clear; clc;

%% Settings for this run (Includes settings that are useful if you are not familiar with the Vivado workflow)
vivado_executable = '/opt/Xilinx/Vivado/2024.1/bin/vivado';         % EDIT: Vivado path for the current computer 
hdl_project_folder = fullfile(tempdir, 'adrc_hdl_prj');             % short path: Vivado dislikes long ones for some reason
also_create_vivado_project = false;                                 % true: also make a Vivado project with the IP core
also_build_bitstream = false;                                       % true: also synthesize and build a bitstream (slow)

%% Load the project paths and every constant the model uses
this_script_folder = fileparts(mfilename('fullpath'));
source_folder = fullfile(this_script_folder, '..', '..');
run(fullfile(source_folder, 'setup_paths.m'));
plant_constants;
controller_parameters;

model_name = 'FPGA_Compatible_FirstOrderADRC';
controller_subsystem = [model_name '/Stepper Motor FOC Controller'];
load_system(model_name);

%% Tell HDL Coder where Vivado is
hdlsetuptoolpath('ToolName', 'Xilinx Vivado', 'ToolPath', vivado_executable);

%% Check the controller can be turned into HDL (quick, no files changed)
checkhdl(controller_subsystem);

%% Run the IP Core Generation workflow
workflow_settings = hdlcoder.WorkflowConfig('SynthesisTool', 'Xilinx Vivado', ...
    'TargetWorkflow', 'IP Core Generation');
workflow_settings.ProjectFolder = hdl_project_folder;
workflow_settings.RunTaskGenerateRTLCodeAndIPCore = true;
workflow_settings.RunTaskCreateProject = also_create_vivado_project || also_build_bitstream;
workflow_settings.RunTaskGenerateSoftwareInterface = false;
workflow_settings.RunTaskBuildFPGABitstream = also_build_bitstream;
workflow_settings.GenerateIPCoreReport = true;

hdlcoder.runWorkflow(controller_subsystem, workflow_settings);

fprintf('\nIP core and reports are in %s\n', hdl_project_folder);
fprintf('Check html/pages/*_delay_balancing.html: the output latency should be 0.\n');
fprintf('Run print_axi_register_values.m to get the register values for Linux.\n');
