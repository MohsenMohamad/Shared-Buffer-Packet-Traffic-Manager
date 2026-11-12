module scheduler_formal import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk, rst_n,
    input config_t cfg,
    input logic [N_Q*DESC_ID_W-1:0] heads,
    input logic [N_Q*DESC_COUNT_W-1:0] counts,
    input logic [N_Q*DESC_INFO_W-1:0] head_info,
    input commit_t commit,
    input logic tx_ready,
    input tx_done_t tx_done
);
dispatch_t dispatch;
logic [N_Q*DEFICIT_W-1:0] deficits;
`define PARAMS .N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),.MAX_PACKET_BYTES(MAX_PACKET_BYTES),.SCHED_MODE(SCHED_MODE)
tm_drr_api #(`PARAMS) dut(.*);
`undef PARAMS
logic history=0;
logic [1:0] startup=0;
logic seen_replace=0, seen_empty=0, seen_busy=0;
logic [N_Q-1:0] emptied='0;
integer expected_credit;
integer merged_count;
descriptor_t selected;
assign selected=head_info[dut.cursor*DESC_INFO_W +: DESC_INFO_W];
always_comb begin
    expected_credit=int'(deficits[dut.cursor*DEFICIT_W +: DEFICIT_W]);
    if(SCHED_MODE==1 && !dut.visit_active && counts[dut.cursor*DESC_COUNT_W +: DESC_COUNT_W]!=0)
        expected_credit+=int'(cfg.quantum[dut.cursor*13 +: 13]);
    merged_count=int'(counts[dut.cursor*DESC_COUNT_W +: DESC_COUNT_W])+int'(commit.valid && commit.qid==dut.cursor)-int'(dispatch.valid);
end
always_ff @(posedge clk) begin
    history<=1;
    if(startup<2) begin assume(!rst_n); startup<=startup+1; end
    // Quanta are static legal software configuration. Safety has no sink
    // progress assumption; ready/completion may stall for arbitrary duration.
    if(!rst_n) begin
        seen_replace<=0; seen_empty<=0; seen_busy<=0; emptied<='0;
        a_reset_grant: assert(!dispatch.valid);
    end else begin
        // Abstract queue/query boundary: legal merged P03 count transitions,
        // no bypass, immutable pre-state head until pop. No assumption removes
        // same/different-qid collisions or last replacement.
        if(commit.valid) assume(int'(commit.qid)<N_Q);
        assume(!tx_done.valid || dut.tx_owned);
        a_cursor: assert(int'(dut.cursor)<N_Q);
        if(SCHED_MODE==1 && !dut.tx_owned && counts[dut.cursor*DESC_COUNT_W +: DESC_COUNT_W]!=0)
            a_add_bound: assert(expected_credit<=4096+MAX_PACKET_BYTES-1);
        if(history && $past(rst_n))
            a_tx_ownership: assert(dut.tx_owned == ($past(dispatch.valid) ||
                ($past(dut.tx_owned) && !$past(tx_done.valid))));
        a_grant: assert(!dispatch.valid || (cfg.run && !dut.tx_owned && tx_ready &&
            counts[dispatch.qid*DESC_COUNT_W +: DESC_COUNT_W]!=0 &&
            dispatch.qid==dut.cursor && dispatch.desc==heads[dispatch.qid*DESC_ID_W +: DESC_ID_W] &&
            dispatch.info==selected && (SCHED_MODE==0 || int'(selected.length)<=expected_credit)));
        a_presence: assert(dispatch.valid == (cfg.run && !dut.tx_owned && tx_ready &&
            counts[dut.cursor*DESC_COUNT_W +: DESC_COUNT_W]!=0 &&
            (SCHED_MODE==0 || int'(selected.length)<=expected_credit)));
        if(counts[dut.cursor*DESC_COUNT_W +: DESC_COUNT_W]!=0)
            assume(selected.length>=1 && selected.length<=MAX_PACKET_BYTES);
        if(dispatch.valid && merged_count==0) begin seen_empty<=1; emptied[dispatch.qid]<=1; end
        if(dispatch.valid && commit.valid && commit.qid==dispatch.qid && counts[dispatch.qid*DESC_COUNT_W +: DESC_COUNT_W]==1)
            seen_replace<=1;
        if(dut.tx_owned && !tx_done.valid) seen_busy<=1;
        c_replace: cover(seen_replace && dut.tx_owned && seen_busy && tx_done.valid);
        c_reactivate: cover(seen_empty && commit.valid && emptied[commit.qid] && counts[commit.qid*DESC_COUNT_W +: DESC_COUNT_W]==0);
        c_different: cover(dispatch.valid && commit.valid && dispatch.qid!=commit.qid);
        c_long: cover(dispatch.valid && commit.valid && dispatch.qid==commit.qid && counts[dispatch.qid*DESC_COUNT_W +: DESC_COUNT_W]==2);
        c_wait: cover(cfg.run && !dut.tx_owned && !tx_ready && counts[dut.cursor*DESC_COUNT_W +: DESC_COUNT_W]!=0 && (SCHED_MODE==0 || int'(selected.length)<=expected_credit));
        if(SCHED_MODE==1) begin
            c_carry: cover(dispatch.valid && !dut.visit_active && deficits[dut.cursor*DEFICIT_W +: DEFICIT_W]!=0);
            c_continue: cover(dispatch.valid && dut.visit_active);
        end
    end
end
for(genvar q=0;q<N_Q;q=q+1) begin : g_credit
    always_ff @(posedge clk) begin
        assume(cfg.quantum[q*13 +: 13]>=64 && cfg.quantum[q*13 +: 13]<=4096);
        if(history) assume(cfg.quantum[q*13 +: 13]==$past(cfg.quantum[q*13 +: 13]));
        if(rst_n) begin
            assume(counts[q*DESC_COUNT_W +: DESC_COUNT_W]<=2);
            if(history) begin
                if(!$past(rst_n)) assume(counts[q*DESC_COUNT_W +: DESC_COUNT_W]==0);
                else begin
                    assume(int'(counts[q*DESC_COUNT_W +: DESC_COUNT_W])==
                        int'($past(counts[q*DESC_COUNT_W +: DESC_COUNT_W]))+
                        int'($past(commit.valid && commit.qid==Q_ID_W'(q)))-
                        int'($past(dispatch.valid && dispatch.qid==Q_ID_W'(q))));
                    if($past(counts[q*DESC_COUNT_W +: DESC_COUNT_W])!=0 &&
                       !$past(dispatch.valid && dispatch.qid==Q_ID_W'(q))) begin
                        assume(head_info[q*DESC_INFO_W +: DESC_INFO_W]==$past(head_info[q*DESC_INFO_W +: DESC_INFO_W]));
                        assume(heads[q*DESC_ID_W +: DESC_ID_W]==$past(heads[q*DESC_ID_W +: DESC_ID_W]));
                    end
                end
            end
            a_bounds: assert(int'(deficits[q*DEFICIT_W +: DEFICIT_W])<=4096+MAX_PACKET_BYTES-1);
            if(SCHED_MODE==0) a_rr_credit: assert(deficits[q*DEFICIT_W +: DEFICIT_W]==0);
            if(SCHED_MODE==1 && (dut.cursor!=Q_ID_W'(q) || !dut.visit_active))
                a_closed_credit: assert(int'(deficits[q*DEFICIT_W +: DEFICIT_W])<MAX_PACKET_BYTES);
            if(history && $past(rst_n)) begin
                // Per-edge add/debit equation includes dispatch into TX;
                // waiting and continuing visits cannot gain a second quantum.
                if(SCHED_MODE==1 && $past(cfg.run && !dut.tx_owned && dut.cursor==Q_ID_W'(q))) begin
                    if($past(counts[q*DESC_COUNT_W +: DESC_COUNT_W])==0 ||
                       $past(dispatch.valid && merged_count==0))
                        a_empty: assert(deficits[q*DEFICIT_W +: DEFICIT_W]==0);
                    else
                        a_credit: assert(int'(deficits[q*DEFICIT_W +: DEFICIT_W])==
                            $past(expected_credit)-int'($past(dispatch.valid))*int'($past(selected.length)));
                end else a_freeze: assert(deficits[q*DEFICIT_W +: DEFICIT_W]==$past(deficits[q*DEFICIT_W +: DEFICIT_W]));
                if($past(dut.tx_owned)) begin
                    a_busy_cursor: assert(dut.cursor==$past(dut.cursor));
                    a_busy_visit: assert(dut.visit_active==$past(dut.visit_active));
                end
            end
        end
    end
end
endmodule
