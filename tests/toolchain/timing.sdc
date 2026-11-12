create_clock -name clk -period 10 [get_ports clk]
set_input_delay -max -clock clk 1 [get_ports {a b}]
set_input_delay -min -clock clk 0.2 [get_ports {a b}]
set_output_delay -max -clock clk 1 [get_ports y]
set_output_delay -min -clock clk 0.2 [get_ports y]
set_input_transition 0.05 [get_ports {a b}]
set_clock_uncertainty 0.05 [get_clocks clk]
# Nangate45 capacitance unit is fF: 10 fF = 0.01 pF.
set_load 10.0 [get_ports y]
