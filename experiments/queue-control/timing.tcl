read_liberty $::env(TM_LIBERTY)
read_verilog $::env(TM_NETLIST)
link_design $::env(TM_TOP)
read_sdc $::env(TM_SDC)
if {[info exists ::env(TM_ADMISSION_MODE)]} {
    set_case_analysis $::env(TM_ADMISSION_MODE) [get_ports dynamic_mode]
}
report_units
if {![check_setup -verbose]} {error "Incomplete constraint coverage"}
set outputs [all_outputs]
set registers [all_registers]
set data_inputs {}
foreach port [all_inputs -no_clocks] {
    if {[get_full_name $port] ne "rst_n"} { lappend data_inputs $port }
}
set data_start [concat $data_inputs [all_registers -clock_pins]]
set data_end [concat [all_registers -data_pins] $outputs]
set reset [get_ports rst_n]
puts "TM_REGISTERS [llength $registers]"
puts "TM_OUTPUTS [llength $outputs]"
foreach delay {max min} {
    puts "TM_DATA_${delay}_BEGIN"
    report_checks -from $data_start -to $data_end -path_delay $delay \
        -group_path_count 1 -sort_by_slack -digits 5 -fields {slew capacitance fanout} -format full_clock_expanded
    puts "TM_DATA_${delay}_END"
    puts "TM_RESET_${delay}_BEGIN"
    report_checks -rise_from $reset -path_group asynchronous -path_delay $delay \
        -group_path_count 1 -sort_by_slack -digits 5 -fields {slew capacitance fanout} -format full_clock_expanded
    puts "TM_RESET_${delay}_END"
    puts "TM_RESET_CONTROL_${delay}_BEGIN"
    report_checks -rise_from $reset -path_group clk -to $data_end -path_delay $delay \
        -group_path_count 1 -sort_by_slack -digits 5 -fields {slew capacitance fanout} -format full_clock_expanded
    puts "TM_RESET_CONTROL_${delay}_END"
}
puts TM_CHECK_TYPES_BEGIN
report_check_types -max_delay -min_delay -recovery -removal -max_slew -max_capacitance -max_fanout -digits 5
puts TM_CHECK_TYPES_END
if {[info exists ::env(TM_DETAIL)]} {
    puts TM_CAP_VIOLATIONS_BEGIN
    report_check_types -max_capacitance -violators -digits 5
    puts TM_CAP_VIOLATIONS_END
}
puts TM_STA_DONE
exit
