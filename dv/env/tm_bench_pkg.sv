`timescale 1ns/1ps
package tm_bench_types;
    `include "tm_bench_config.svh"
    `include "tm_types.svh"
    export tm_fixed::*;
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
    // UVM's default $finish exit is zero on this simulator. Keep the genuine
    // UVM report and terminate immediately so errors cannot execute past fatal.
    class tm_report_server extends uvm_default_report_server;
        virtual function void execute_report_message(uvm_report_message report_message,string composed_message);
            bit failed=(report_message.get_severity()==UVM_FATAL || report_message.get_severity()==UVM_ERROR);
            if(failed) report_message.set_action((report_message.get_action() | UVM_DISPLAY) & ~(UVM_EXIT | UVM_STOP | UVM_COUNT));
            super.execute_report_message(report_message,composed_message);
            if(failed) $fatal(1,"TM_UVM_CHECKER_STOP");
        endfunction
    endclass
    `include "tm_stream_agent.svh"
    `include "tm_axil_agent.svh"
    `include "tm_checkers.svh"
    `include "tm_environment.svh"
    `include "tm_foundation_test.svh"
    `include "tm_batch_test.svh"
endpackage
