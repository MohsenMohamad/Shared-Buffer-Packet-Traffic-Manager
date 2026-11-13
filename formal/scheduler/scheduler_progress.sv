// Separate conditional progress task. Constant-length continuously backlogged
// queues abstract the P03 API; safety tasks do not inherit these assumptions.
module scheduler_progress import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
)(input logic clk,rst_n,input logic retire);
localparam int TX_BOUND=20;
localparam int RESPONSE_BOUND=(SCHED_MODE==1 ? 2 : 1)*N_Q*(TX_BOUND+4);
config_t cfg;
commit_t commit;
dispatch_t dispatch;
tx_done_t tx_done;
logic [N_Q*DESC_ID_W-1:0] heads;
logic [N_Q*DESC_COUNT_W-1:0] counts;
logic [N_Q*DESC_INFO_W-1:0] head_info;
logic [N_Q*DEFICIT_W-1:0] deficits;
logic [1:0] startup=0;
logic [1:0] fill;
logic owned;
dispatch_t owner;
integer tx_age, response_age;
`define PARAMS .N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),.MAX_PACKET_BYTES(MAX_PACKET_BYTES),.SCHED_MODE(SCHED_MODE)
tm_drr_api #(`PARAMS) dut(.clk,.rst_n,.cfg,.heads,.counts,.head_info,.commit,
    .tx_ready(1'b1),.tx_done,.dispatch,.deficits);
`undef PARAMS
always_comb begin
    cfg='0; cfg.run=fill==2;
    cfg.quantum[0+:13]=13'(64);
    cfg.quantum[13+:13]=13'(128);
    head_info='0; counts='0;
    for(int q=0;q<N_Q;q++) begin
        descriptor_t info;
        info='0; info.length=16'(MAX_PACKET_BYTES); info.qid=Q_ID_W'(q);
        info.ncell=CELL_COUNT_W'((MAX_PACKET_BYTES+CELL_BYTES-1)/CELL_BYTES);
        head_info[q*DESC_INFO_W+:DESC_INFO_W]=info;
        counts[q*DESC_COUNT_W+:DESC_COUNT_W]=DESC_COUNT_W'(int'(fill)>q);
    end
    commit='0;
    if(rst_n) begin
        if(fill<2) begin
            commit.valid=1; commit.qid=Q_ID_W'(fill); commit.desc=DESC_ID_W'(2*int'(fill));
        end else if(dispatch.valid) begin
            commit.valid=1; commit.qid=dispatch.qid; commit.desc=dispatch.desc^DESC_ID_W'(1);
        end
        commit.info=head_info[commit.qid*DESC_INFO_W+:DESC_INFO_W];
    end
    tx_done='0;
    if(owned && retire)
        tx_done='{1'b1,owner.desc,owner.qid,owner.info.length};
end
always_ff @(posedge clk) begin
    if(startup<2) begin assume(!rst_n); startup<=startup+1; end
    if(!rst_n) begin
        fill<=0; heads<='0; owned<=0; owner<='0;
        tx_age<=0; response_age<=0;
    end else begin
        // Explicitly progressing endpoint: an accepted packet completes within
        // twenty clocks. Readiness is continuous. Neither applies to safety.
        assume(!retire || owned);
        assume(!owned || tx_age<TX_BOUND-1 || retire);
        if(fill<2) begin
            heads[int'(fill)*DESC_ID_W+:DESC_ID_W]<=DESC_ID_W'(2*int'(fill));
            fill<=fill+1;
        end
        if(dispatch.valid) begin
            heads[dispatch.qid*DESC_ID_W+:DESC_ID_W]<=commit.desc;
            owned<=1; owner<=dispatch;
        end else if(tx_done.valid) owned<=0;
        if(!owned || tx_done.valid) tx_age<=0;
        else tx_age<=tx_age+1;
        if(fill<2 || (dispatch.valid && dispatch.qid==0)) response_age<=0;
        else response_age<=response_age+1;
        // Length 128 / quantum 64 requires two funded visits; packet RR needs
        // one. The other queue has length=quantum=128, at most one packet per
        // visit. One round includes both retirement budgets and scan edges.
        a_fill_range: assert(fill<=2);
        a_event_owner: assert(dut.tx_owned==owned);
        a_retirement_age: assert(tx_age>=0 && tx_age<TX_BOUND);
        a_response_nonnegative: assert(response_age>=0);
        // With fixed 128-byte heads and ready high, q0 carries only 0/64;
        // q1's 128-byte quantum is debited on its entry dispatch. These are
        // asserted concept-derived invariants, not environment assumptions.
        a_credit_lattice: assert(deficits[0+:DEFICIT_W]==0 ||
            (SCHED_MODE==1 && deficits[0+:DEFICIT_W]==64));
        a_other_credit: assert(deficits[DEFICIT_W+:DEFICIT_W]==0);
        a_bounded_response: assert(response_age<=RESPONSE_BOUND);
        a_progress_owned: assert(!dispatch.valid || !owned);
        c_response: cover(fill==2 && dispatch.valid && dispatch.qid==0 && response_age>TX_BOUND);
    end
end
endmodule
