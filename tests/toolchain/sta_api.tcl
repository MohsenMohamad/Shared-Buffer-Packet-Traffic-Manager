# Availability is distinct from a measured scene/variation/noise study.
foreach command {define_scene read_spef set_timing_derate annotate_noise_delays} {
    if {[llength [info commands $command]] != 1} {
        error "Missing required current OpenSTA API: $command"
    }
    puts "TM_STA_API $command"
}
if {$sta_pocv_mode != "scalar" || $sta_pocv_quantile != 3} {
    error "Unexpected default statistical analysis mode"
}
puts "TM_STA_POCV mode=$sta_pocv_mode quantile=$sta_pocv_quantile"
puts TM_STA_API_PASS
exit
