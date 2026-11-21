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
puts TM_COMPOSED_DONE
exit
