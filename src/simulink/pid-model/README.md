# PID model

Reserved for a PID FOC baseline to compare against the ADRC models in `../ADRC-model/`. No PID model exists in the repository yet.

If you build one, reuse the plant and PWM generator in `../ADRC-model/subsystems/` (`adrc_harness.slx`, `PWM_Generator.slx`), so both controllers see exactly the same motor.
