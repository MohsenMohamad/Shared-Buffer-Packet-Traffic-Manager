# Nangate45 typical: ns / fF, 1.10 V / 25 C. Ideal clock, no exceptions.
create_clock -name clk -period 10 [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks clk]
set data_inputs [all_inputs -no_clocks]
# Reset is deliberately included in min/max IO constraints and drive modeling.
set_input_delay -max -clock clk 2.0 $data_inputs
set_input_delay -min -clock clk 0.2 $data_inputs
set_output_delay -max -clock clk 2.0 [all_outputs]
set_output_delay -min -clock clk 0.2 [all_outputs]
if {$::env(TM_DRIVE_MODE) eq "drive"} {
    set_driving_cell -lib_cell BUF_X1 -pin Z $data_inputs
} else {
    set_input_transition 0.05 $data_inputs
}
set_load 10.0 [all_outputs]
# These groups identify outputs consumed by future admission/accounting logic.
group_path -name selection -from [all_registers -clock_pins] -to [get_ports {available_id*}]
group_path -name availability -to [get_ports available]
group_path -name count -to [get_ports {free_count*}]
