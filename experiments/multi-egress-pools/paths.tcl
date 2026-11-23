proc endpoints {net_prefix pins} {
    set result {}
    foreach pin [get_pins $pins] {
        lappend result $pin
    }
    if {[llength $result] == 0} {error "Missing endpoints for $net_prefix"}
    return $result
}

# The driver generates the cell-pin lists from mapped JSON aliases.
source $::env(TM_FOCUS_TCL)
foreach {label from to} $tm_focus {
    foreach delay {max min} {
        puts "TM_${label}_${delay}_BEGIN"
        report_checks -from $from -to $to -path_delay $delay \
            -group_path_count 1 -sort_by_slack -digits 5 -fields {slew capacitance fanout} \
            -format full_clock_expanded
        puts "TM_${label}_${delay}_END"
    }
}
