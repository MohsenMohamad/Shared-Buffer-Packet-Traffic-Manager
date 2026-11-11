`timescale 1ns/1ps
package tm_bench_types;
    `include "tm_bench_config.svh"
    `include "tm_types.svh"
    `include "tm_monitor_types.svh"
endpackage

interface tm_stream_if(input logic clk, input logic rst_n);
    import tm_bench_types::*;
    logic valid, ready;
    beat_t beat;
    a_hold: assert property (@(posedge clk) disable iff(!rst_n)
        valid && !ready |=> valid && $stable(beat))
        else $fatal(1,"TM_STREAM_HOLD");
endinterface

interface tm_axil_if(input logic clk, input logic rst_n);
    import tm_bench_types::*;
    axil_request_t req;
    axil_response_t rsp;
    a_aw: assert property (@(posedge clk) disable iff(!rst_n)
        req.awvalid && !rsp.awready |=> req.awvalid && $stable({req.awaddr,req.awprot}));
    a_w: assert property (@(posedge clk) disable iff(!rst_n)
        req.wvalid && !rsp.wready |=> req.wvalid && $stable({req.wdata,req.wstrb}));
    a_ar: assert property (@(posedge clk) disable iff(!rst_n)
        req.arvalid && !rsp.arready |=> req.arvalid && $stable({req.araddr,req.arprot}));
    a_b: assert property (@(posedge clk) disable iff(!rst_n)
        rsp.bvalid && !req.bready |=> rsp.bvalid && $stable(rsp.bresp));
    a_r: assert property (@(posedge clk) disable iff(!rst_n)
        rsp.rvalid && !req.rready |=> rsp.rvalid && $stable({rsp.rdata,rsp.rresp}));
endinterface

interface tm_observe_if(input logic clk);
    import tm_bench_types::*;
    logic rst_n;
    trace_t trace_events;
    logic [N_RX*STATUS_W-1:0] statuses;
    live_t live;
endinterface

package tm_bench_pkg;
    import uvm_pkg::*;
    import tm_bench_types::*;
    `include "uvm_macros.svh"
    `include "tm_stream_agent.svh"
    `include "tm_axil_agent.svh"
    `include "tm_checkers.svh"
    `include "tm_environment.svh"
    `include "tm_foundation_test.svh"
endpackage
