`timescale 1ns/1ps
// Component fixture only: independent architectural actions and busy contexts,
// no packet parser, CPU, pools, scheduler or payload datapath. Resource deltas
// are stimulus bookkeeping, not traffic-manager ownership verification.
module tm_csr_fixture(input logic clk, tm_axil_if bus, tm_csr_fixture_if f);
    import tm_bench_types::*;
    live_t resources, next_resources;
    integer u,r,a,d,h[N_Q],queued[N_Q];
    always_comb begin
        next_resources=resources;
        u=int'(resources.unreserved);r=int'(resources.reserved_free);
        a=int'(resources.assigned);d=int'(resources.free_desc);
        for(int q=0;q<N_Q;q++) begin
            h[q]=int'(resources.owned[q*CELL_COUNT_W+:CELL_COUNT_W]);
            queued[q]=int'(resources.queued[q*DESC_COUNT_W+:DESC_COUNT_W]);
        end
        if(f.events.admit.valid && f.events.admit.accept && int'(f.events.admit.qid)<N_Q) begin
            u-=int'(f.events.admit.ncell);r+=int'(f.events.admit.ncell);d--;
            h[int'(f.events.admit.qid)]+=int'(f.events.admit.ncell);
        end
        if(f.events.cell_alloc.valid) begin a++;r--;end
        if(f.events.cell_free.valid) begin
            a--;
            if(f.events.cell_free.abort_source) r++;
            else begin u++;h[int'(f.events.cell_free.qid)]--;end
        end
        if(f.events.abort_done.valid) begin
            u+=int'(f.events.abort_done.ncell);r-=int'(f.events.abort_done.ncell);d++;
            h[int'(f.events.abort_done.qid)]-=int'(f.events.abort_done.ncell);
        end
        if(f.events.tx_done.valid) d++;
        if(f.events.commit.valid) queued[int'(f.events.commit.qid)]++;
        if(f.events.dispatch.valid) queued[int'(f.events.dispatch.qid)]--;
        next_resources.unreserved=CELL_COUNT_W'(u);next_resources.reserved_free=CELL_COUNT_W'(r);
        next_resources.assigned=CELL_COUNT_W'(a);next_resources.physical_free=CELL_COUNT_W'(N_CELL-a);
        next_resources.free_desc=DESC_COUNT_W'(d);
        for(int q=0;q<N_Q;q++) begin
            next_resources.owned[q*CELL_COUNT_W+:CELL_COUNT_W]=CELL_COUNT_W'(h[q]);
            next_resources.queued[q*DESC_COUNT_W+:DESC_COUNT_W]=DESC_COUNT_W'(queued[q]);
        end
        f.live=resources;
        f.live.idle=(f.busy==0 && resources.owned==0 && resources.queued==0 &&
            resources.unreserved==CELL_COUNT_W'(N_CELL) && resources.reserved_free==0 &&
            resources.assigned==0 && resources.free_desc==DESC_COUNT_W'(N_DESC));
        f.live.invariant_error=f.invariant_error;
        // Nonzero live deficits exercise the CSR lane mux independently.
        for(int q=0;q<N_Q;q++) f.live.deficit[q*DEFICIT_W+:DEFICIT_W]=DEFICIT_W'(q*17);
    end
    always_ff @(posedge clk or negedge f.rst_n) begin
        if(!f.rst_n) begin
            resources<='0;resources.unreserved<=CELL_COUNT_W'(N_CELL);
            resources.physical_free<=CELL_COUNT_W'(N_CELL);resources.free_desc<=DESC_COUNT_W'(N_DESC);
            f.initialized<=0;
        end else begin resources<=next_resources;f.initialized<=1;end
    end
    tm_axil_regs_api #(`include "tm_csr_params.svh"
    ) regs(.clk(clk),.rst_n(f.rst_n),.initialized(f.initialized),.bus_req(bus.req),.bus_rsp(bus.rsp),
        .live(f.live),.live_stats(f.live_stats),.shadow_stats(f.shadow_stats),.cfg(f.cfg),.stats_command(f.command));
    tm_statistics_api #(`include "tm_csr_params.svh"
        ,.COUNTER_W(CSR_COUNTER_W)
    ) stats(.clk(clk),.rst_n(f.rst_n),.events(f.events),.input_stalled(f.input_stalled),
        .output_stalled(f.output_stalled),.output_fire(f.output_fire),.output_beat(f.output_beat),
        .run(f.cfg.run),.live(f.live),.command(f.command),.live_stats(f.live_stats),.shadow_stats(f.shadow_stats));
endmodule
