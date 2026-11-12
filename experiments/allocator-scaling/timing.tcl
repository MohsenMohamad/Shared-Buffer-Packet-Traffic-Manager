read_liberty $::env(TM_LIBERTY)
read_verilog $::env(TM_NETLIST)
link_design $::env(TM_TOP)
read_sdc $::env(TM_SDC)
report_units
puts TM_COVERAGE_BEGIN
if {![check_setup -verbose]} {error "Constraint coverage failed"}
# An output with no timing path must not qualify through an empty report.
foreach port [all_outputs] {
    foreach delay {max min} {
        set paths [find_timing_paths -to $port -path_delay $delay]
        if {[llength $paths] == 0} {error "No $delay path to [get_full_name $port]"}
    }
}
puts "TM_OUTPUTS [llength [all_outputs]]"
puts "TM_REGISTERS [llength [all_registers]]"
puts TM_COVERAGE_DONE
foreach delay {max min} {
    puts "TM_OVERALL_${delay}_BEGIN"
    report_checks -path_delay $delay -group_path_count 1 -sort_by_slack -digits 5 -fields {slew capacitance fanout} -format full_clock_expanded
    puts "TM_OVERALL_${delay}_END"
    foreach group {selection availability count} {
        puts "TM_${group}_${delay}_BEGIN"
        report_checks -path_delay $delay -path_group $group -group_path_count 1 -digits 5 -fields {slew capacitance fanout} -format full_clock_expanded
        puts "TM_${group}_${delay}_END"
    }
}
puts TM_CHECK_TYPES_BEGIN
report_check_types -max_delay -min_delay -recovery -removal -max_slew -max_capacitance -max_fanout -digits 5
puts TM_CHECK_TYPES_END
puts TM_STA_DONE
exit
