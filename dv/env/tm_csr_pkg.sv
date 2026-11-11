`timescale 1ns/1ps
// Only the stimulus side is driven by the test. Resource/IDLE and observed
// production outputs are separate, so a DUT report cannot manufacture an event.
interface tm_csr_fixture_if(input logic clk);
    import tm_bench_types::*;
    logic rst_n, initialized;
    trace_t events;
    logic [N_RX-1:0] input_stalled;
    logic output_stalled, output_fire, invariant_error;
    beat_t output_beat;
    // ingress, RX, drain, abort cleanup, TX/FIFO, outstanding RAM response
    logic [5:0] busy;
    live_t live;
    config_t cfg;
    statistics_t live_stats, shadow_stats;
    stats_command_t command;
endinterface

package tm_csr_pkg;
    import uvm_pkg::*;
    import tm_bench_types::*;
    import tm_bench_pkg::*;
    `include "uvm_macros.svh"
    `include "tm_csr_model.svh"
    `include "tm_csr_test.svh"
endpackage
