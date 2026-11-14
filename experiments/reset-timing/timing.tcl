# Shared reporting/coverage gate; inputs and expected envelope supplied by runner.
read_liberty $::env(TM_LIBERTY)
read_verilog $::env(TM_NETLIST)
link_design $::env(TM_TOP)
# Observe explicit reset bounds while OpenSTA executes the SDC. OpenSTA can
# silently reuse a lone max bound for min; that is not an explicit min model.
rename set_input_delay r01_input_delay
proc set_input_delay {args} {
    if {[lsearch -exact [lindex $args end] [get_ports rst_n]] >= 0} {
        foreach bound {min max} {
            if {[lsearch -exact $args -$bound] >= 0} {
                set ::r01_reset($bound) [lindex $args end-1]
            }
        }
        set ::r01_edge [expr {[lsearch -exact $args -clock_fall] >= 0 ? "fall" : "rise"}]
    }
    uplevel 1 [linsert $args 0 r01_input_delay]
}
# No timing exceptions are part of this recipe; reject rather than hide checks.
foreach command {set_false_path set_disable_timing set_multicycle_path} {
    rename $command r01_$command
    proc $command {args} {error "R01_TIMING_EXCEPTION"}
}
read_sdc $::env(TM_SDC)
foreach bound {min max} {
    if {![info exists ::r01_reset($bound)]} {error "R01_MISSING_RESET_$bound"}
    if {$::r01_reset($bound) != $::env(TM_RESET_[string toupper $bound])} {error "R01_RESET_BOUND_$bound"}
}
if {$::r01_edge ne $::env(TM_RESET_EDGE)} {error "R01_RESET_EDGE"}
report_units
if {![check_setup -verbose]} {error "R01_CONSTRAINT_COVERAGE"}
set reset [get_ports rst_n]
set data_inputs [get_ports -filter {direction == input && name != clk && name != rst_n}]
set regs [all_registers -clock_pins]
set data_pins [all_registers -data_pins]
set async_pins [all_registers -async_pins]
if {[llength $async_pins] == 0} {error "R01_NO_RESET_PINS"}
# Collect one worst path per endpoint in bulk, then prove set equality. This
# avoids repeated full-design searches on the 1036-pin mapped allocator.
proc require_endpoints {name endpoints args} {
    foreach delay {max min} {
        set seen [dict create]
        foreach path [find_timing_paths -path_delay $delay -to $endpoints -group_path_count [llength $endpoints] -endpoint_path_count 1 {*}$args] {
            dict set seen [get_full_name [get_property $path endpoint]] 1
        }
        foreach endpoint $endpoints {
            if {![dict exists $seen [get_full_name $endpoint]]} {error "R01_${name}_PATH_$delay [get_full_name $endpoint]"}
        }
    }
}
require_endpoints RESET $async_pins -rise_from $reset
require_endpoints OUTPUT [all_outputs]
puts "R01_COVERAGE [llength [all_outputs]] [llength $regs] [llength $async_pins]"
# Explicit sections retain each endpoint class without reassigning path groups.
proc section {name required args} {
    foreach delay {max min} {
        set paths [find_timing_paths -path_delay $delay {*}$args]
        if {$required && [llength $paths] == 0} {error "R01_EMPTY_${name}_$delay"}
        puts "R01_${name}_${delay}_BEGIN"
        if {[llength $paths]} {
            report_checks -path_delay $delay {*}$args -group_path_count 1 -sort_by_slack -digits 5 -fields {slew capacitance fanout} -format full_clock_expanded
        } else {puts R01_NOT_PRESENT}
        puts "R01_${name}_${delay}_END"
    }
}
section overall 1
section data 1 -from [concat $data_inputs $regs] -to [concat $data_pins [all_outputs]]
section data_rr 1 -from $regs -to $data_pins
section data_ir 1 -from $data_inputs -to $data_pins
section data_ro 1 -from $regs -to [all_outputs]
section data_io 0 -from $data_inputs -to [all_outputs]
section reset_checks 1 -rise_from $reset -to $async_pins
section reset_effects 1 -path_group clk -from $reset -to [concat $data_pins [all_outputs]]
if {$::env(TM_TOP) ne "tm_axis_rx_fifo_api"} {
    section selection 1 -from $regs -to [get_ports {available_id*}]
    section availability 1 -to [get_ports available]
    section count 1 -to [get_ports {free_count*}]
}
report_check_types -max_delay -min_delay -recovery -removal -max_slew -max_capacitance -max_fanout -digits 5
puts R01_DONE
exit
