# Paths supplied by the bounded runner; fail explicitly on missing timing paths.
read_liberty $::env(TM_LIBERTY)
read_verilog $::env(TM_NETLIST)
link_design mapping
read_sdc $::env(TM_SDC)
check_setup -verbose
puts TM_STA_MAX_BEGIN
report_checks -path_delay max -format full_clock_expanded
puts TM_STA_MIN_BEGIN
report_checks -path_delay min -format full_clock_expanded
puts TM_STA_DONE
exit
