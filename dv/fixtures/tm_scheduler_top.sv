`timescale 1ns/1ps
interface tm_scheduler_if(input logic clk);
    import tm_bench_types::*;
    logic rst_n=0, tx_ready=1;
    stream_sample_t output_sample='0;
    cell_return_t cell_free='0;
    config_t cfg='0;
    commit_t commit='0;
    tx_done_t tx_done='0;
    dispatch_t dispatch;
    logic [N_Q*DEFICIT_W-1:0] deficits;
    logic [N_Q*DESC_ID_W-1:0] heads, tails;
    logic [N_Q*DESC_COUNT_W-1:0] counts;
    logic queue_error;
endinterface

package tm_scheduler_tests;
    import uvm_pkg::*;
    import tm_bench_types::*;
    import tm_bench_pkg::*;
    `include "uvm_macros.svh"
    `include "tm_scheduler_events.svh"
    `include "tm_scheduler_inputs.svh"
    `include "tm_scheduler_rtl_test.svh"
    `include "tm_scheduler_stress_test.svh"
endpackage

module tm_scheduler_top;
    import uvm_pkg::*;
    import tm_bench_types::*;
    import tm_bench_pkg::*;
    import tm_scheduler_tests::*;
    bit clk=0;
    always #5 clk=~clk;
    tm_scheduler_if io(clk);
    descriptor_t metadata[N_DESC];
    logic [N_Q*DESC_INFO_W-1:0] head_info;
    desc_link_write_t next_write;
    desc_id_t old_head_next;
    logic observed_tx_owned;
    always_ff @(posedge clk or negedge io.rst_n) begin
        if(!io.rst_n) observed_tx_owned<=0;
        else begin
            if(io.tx_done.valid) observed_tx_owned<=0;
            if(io.dispatch.valid) observed_tx_owned<=1;
        end
    end
    a_eligible: assert property (@(posedge clk) disable iff(!io.rst_n)
        io.dispatch.valid |-> io.cfg.run && io.tx_ready && !observed_tx_owned &&
        io.counts[io.dispatch.qid*DESC_COUNT_W +: DESC_COUNT_W]!=0 &&
        io.dispatch.desc==io.heads[io.dispatch.qid*DESC_ID_W +: DESC_ID_W])
        else $fatal(1,"SCHEDULER_GRANT");
    a_busy_freeze: assert property (@(posedge clk) disable iff(!io.rst_n)
        observed_tx_owned |=> $stable(io.deficits))
        else $fatal(1,"SCHEDULER_FREEZE");
    for(genvar q=0;q<N_Q;q++) begin : g_bounds
        a_bounds: assert property (@(posedge clk) disable iff(!io.rst_n)
            int'(io.deficits[q*DEFICIT_W +: DEFICIT_W])<=4096+MAX_PACKET_BYTES-1)
            else $fatal(1,"SCHEDULER_BOUNDS");
    end
    for(genvar q=0;q<N_Q;q++) begin : g_query
        assign head_info[q*DESC_INFO_W +: DESC_INFO_W]=metadata[io.heads[q*DESC_ID_W +: DESC_ID_W]];
    end
    // Metadata is an unreset pre-state query fixture; no commit bypass.
    always_ff @(posedge clk) if(io.commit.valid) metadata[io.commit.desc]<=io.commit.info;
`define SCHED_PARAMS .N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),.MAX_PACKET_BYTES(MAX_PACKET_BYTES),.SCHED_MODE(SCHED_MODE)
    tm_queue_ctrl_api #(`SCHED_PARAMS) queues(.clk(clk),.rst_n(io.rst_n),.commit(io.commit),.dispatch(io.dispatch),
        .old_head_next(old_head_next),.heads(io.heads),.tails(io.tails),.counts(io.counts),.next_write(next_write),.invariant_error(io.queue_error));
    tm_desc_links #(`SCHED_PARAMS) links(.clk(clk),.write_req(next_write),.read_id(io.dispatch.desc),.read_next(old_head_next));
    tm_drr_api #(`SCHED_PARAMS) scheduler(.clk(clk),.rst_n(io.rst_n),.cfg(io.cfg),.heads(io.heads),.counts(io.counts),
        .head_info(head_info),.commit(io.commit),.tx_ready(io.tx_ready),.tx_done(io.tx_done),.dispatch(io.dispatch),.deficits(io.deficits));
`undef SCHED_PARAMS
    initial begin
        tm_report_server server;
        server=new;
        uvm_report_server::set_server(server);
        uvm_config_db#(virtual tm_scheduler_if)::set(null,"uvm_test_top","vif",io);
        run_test("tm_scheduler_rtl_test");
    end
    initial if($test$plusargs("TRACE")) begin $dumpfile("wave.vcd"); $dumpvars(0,tm_scheduler_top); end
    final begin
`ifdef VERILATOR
        $c("VerilatedCov::write(\"coverage.dat\");");
`endif
    end
    initial begin #10000000; $fatal(1,"TM_SCHEDULER_TIMEOUT"); end
endmodule
