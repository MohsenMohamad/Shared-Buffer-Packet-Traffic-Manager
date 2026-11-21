# Reuse the reference checks without ending the STA process before focused STA.
rename exit tm_exit
proc exit {} {}
source [file join [file dirname [info script]] timing.tcl]
rename exit {}
rename tm_exit exit

if {[info exists ::env(TM_COMPOSED_GROUPS)]} {
    foreach group $::env(TM_COMPOSED_GROUPS) {
        set from_pins [get_pins -quiet $::env(TM_FROM_${group})]
        set from_ports [get_ports -quiet $::env(TM_INPUT_${group})]
        set to_pins [get_pins -quiet $::env(TM_TO_${group})]
        set from [concat $from_pins $from_ports]
        if {[llength $from] == 0 || [llength $to_pins] == 0} {
            error "Empty endpoint selection for $group"
        }
        if {[llength $from_pins] != [llength $::env(TM_FROM_${group})] ||
            [llength $to_pins] != [llength $::env(TM_TO_${group})]} {
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
}
puts TM_COMPOSED_DONE
exit
