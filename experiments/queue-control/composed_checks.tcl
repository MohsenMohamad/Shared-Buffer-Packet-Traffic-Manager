# Reuse the reference checks without ending the STA process before focused STA.
rename exit tm_exit
proc exit {} {}
source [file join [file dirname [info script]] timing.tcl]
rename exit {}
rename tm_exit exit

if {[info exists ::env(TM_COMPOSED_GROUPS)]} {
    set group_file [open $::env(TM_COMPOSED_GROUPS) r]
    foreach record [split [string trimright [read $group_file] "\n"] "\n"] {
        lassign [split $record "|"] group start_pins inputs end_pins
        set from_pins [get_pins -quiet $start_pins]
        set from_ports [get_ports -quiet $inputs]
        set to_pins [get_pins -quiet $end_pins]
        set from [concat $from_pins $from_ports]
        if {[llength $from] == 0 || [llength $to_pins] == 0} {
            error "Empty endpoint selection for $group"
        }
        if {[llength $from_pins] != [llength $start_pins] ||
            [llength $to_pins] != [llength $end_pins]} {
            error "Missing mapped pin for $group"
        }
        foreach delay {max min} {
            puts "TM_GROUP_${group}_${delay}_BEGIN"
            report_checks -from $from -to $to_pins -path_delay $delay \
                -group_path_count 1 -sort_by_slack -digits 5 \
                -fields {slew capacitance fanout} -format full_clock_expanded
            puts "TM_GROUP_${group}_${delay}_END"
        }
    }
    close $group_file
}
if {[info exists ::env(TM_HOLD_DETAIL)]} {
    puts TM_SHORT_PATHS_BEGIN
    report_checks -from $data_start -to $data_end -path_delay min -slack_max 0.0 \
        -group_path_count 256 -endpoint_path_count 1 -sort_by_slack -digits 5 \
        -fields {slew capacitance fanout} -format full_clock_expanded
    puts TM_SHORT_PATHS_END
}
if {[info exists ::env(TM_RESET_SAMPLES)]} {
    set reset_write_pins {}
    if {[info exists ::env(TM_RESET_WRITE_PINS)]} {
        set pin_file [open $::env(TM_RESET_WRITE_PINS) r]
        set requested [read $pin_file]
        close $pin_file
        set reset_write_pins [get_pins -quiet $requested]
        if {[llength $reset_write_pins] != [llength $requested]} {
            error "Missing reset-to-write capture pin"
        }
    }
    set scenarios {reference}
    lappend scenarios {*}$::env(TM_RESET_SAMPLES)
    foreach arrival $scenarios {
        if {$arrival ne "reference"} {
            set_input_delay -rise -min -clock clk $arrival $reset
            set_input_delay -rise -max -clock clk $arrival $reset
        }
        foreach delay {max min} {
            if {$arrival ne "reference"} {
                puts "TM_SAMPLE_${arrival}_reset_${delay}_BEGIN"
                report_checks -rise_from $reset -path_group asynchronous -path_delay $delay \
                    -group_path_count 1 -sort_by_slack -digits 5 -format full_clock_expanded
                puts "TM_SAMPLE_${arrival}_reset_${delay}_END"
                puts "TM_SAMPLE_${arrival}_reset_control_${delay}_BEGIN"
                report_checks -rise_from $reset -path_group clk -to $data_end -path_delay $delay \
                    -group_path_count 1 -sort_by_slack -digits 5 -format full_clock_expanded
                puts "TM_SAMPLE_${arrival}_reset_control_${delay}_END"
            }
            if {[llength $reset_write_pins]} {
                puts "TM_SAMPLE_${arrival}_reset_write_${delay}_BEGIN"
                report_checks -rise_from $reset -path_group clk -to $reset_write_pins -path_delay $delay \
                    -group_path_count 1 -sort_by_slack -digits 5 -format full_clock_expanded
                puts "TM_SAMPLE_${arrival}_reset_write_${delay}_END"
            }
        }
    }
}
puts TM_COMPOSED_DONE
exit
