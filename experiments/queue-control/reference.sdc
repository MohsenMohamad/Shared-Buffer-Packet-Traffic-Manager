# Nangate45 typical, ns/fF. Reset release budget is a reference model.
create_clock -name clk -period 10 [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks clk]
set data_inputs {}
foreach port [all_inputs -no_clocks] {
    if {[get_full_name $port] ne "rst_n"} { lappend data_inputs $port }
}
set_input_delay -max -clock clk 2.0 $data_inputs
set_input_delay -min -clock clk 0.2 $data_inputs
set_input_transition 0.05 $data_inputs
set_input_delay -rise -max -clock clk 2.0 [get_ports rst_n]
set_input_delay -rise -min -clock clk 0.2 [get_ports rst_n]
set_input_transition 0.05 [get_ports rst_n]
set_output_delay -max -clock clk 2.0 [all_outputs]
set_output_delay -min -clock clk 0.2 [all_outputs]
set_load 10.0 [all_outputs]
