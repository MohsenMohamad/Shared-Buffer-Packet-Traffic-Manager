// Retained P03 author list/representation model; independently audited and extended.
module queue_formal import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk, rst_n,
    input commit_t commit,
    input logic request_pop,
    input qid_t pop_qid,
    input logic allocate, complete,
    input desc_id_t allocate_id, complete_id,
    input qid_t witness_qid,
    input desc_id_t witness_desc
);
logic [N_Q*DESC_ID_W-1:0] heads, tails;
logic [N_Q*DESC_COUNT_W-1:0] counts;
desc_link_write_t next_write;
desc_id_t old_head_next, read_id;
dispatch_t dispatch;
logic invariant_error;
// Independent ordered lists. No expected value comes from a physical pointer.
desc_id_t model [N_Q][N_DESC];
logic [DESC_COUNT_W-1:0] length [N_Q];
logic [1:0] startup=0;
logic history_valid=0, reset_busy=0, seen_active=0;
logic take_pop;
integer total;
localparam int FREE=0, RX=1, QUEUED=2, TX=3;
logic [2*N_DESC-1:0] owner;
logic witness_live;
logic [N_DESC-1:0] queued_mask;
always_comb begin
    queued_mask='0;
    witness_live=0;
    for(integer q=0;q<N_Q;q++)
        for(integer k=0;k<N_DESC;k++)
            if(k<length[q]) begin
                queued_mask[model[q][k]]=1;
                if(model[q][k]==witness_desc) witness_live=1;
            end
end
always_comb begin
    total=0;
    for (integer q=0;q<N_Q;q=q+1) total+=length[q];
    take_pop=request_pop && int'(pop_qid)<N_Q && length[pop_qid]>0;
    dispatch='0;
    dispatch.valid=take_pop;
    dispatch.qid=pop_qid;
    dispatch.desc=model[pop_qid][0];
    read_id=heads[pop_qid*DESC_ID_W +: DESC_ID_W];
end
`define QUEUE_PARAMS .N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),.MAX_PACKET_BYTES(MAX_PACKET_BYTES)
tm_queue_ctrl_api #(`QUEUE_PARAMS) dut(.*);
tm_desc_links #(`QUEUE_PARAMS) links(.clk(clk),.write_req(next_write),.read_id(read_id),.read_next(old_head_next));
`undef QUEUE_PARAMS
for(genvar q=0;q<N_Q;q=q+1) begin : g_order
    always_ff @(posedge clk)
        if(rst_n) begin
            a_count: assert(int'(counts[q*DESC_COUNT_W +: DESC_COUNT_W])==length[q]);
            if(length[q]>0)
                a_order: assert(heads[q*DESC_ID_W +: DESC_ID_W]==model[q][0]);
        end
end
for(genvar id=0;id<N_DESC;id++) begin : g_owner
    always_ff @(posedge clk)
        if(rst_n) a_owner_membership: assert((owner[2*int'(id)+:2]==QUEUED)==queued_mask[id]);
end
always_ff @(posedge clk) begin
    history_valid<=1;
    // F01 fixed arbitrary witnesses are stable even across later DUT resets.
    if(history_valid) begin
        assume(witness_qid==$past(witness_qid));
        assume(witness_desc==$past(witness_desc));
    end
    assume(int'(witness_qid)<N_Q && int'(witness_desc)<N_DESC);
    if (startup<2) begin assume(!rst_n); startup<=startup+1; end
    if (!rst_n) begin
        for (integer q=0;q<N_Q;q=q+1) length[q]<=0;
        for(integer id=0;id<N_DESC;id++) owner[2*int'(id)+:2]<=FREE;
        if (history_valid && seen_active && total>0) reset_busy<=1;
        a_reset_write: assert(!next_write.valid);
        c_reset_active: cover(history_valid && seen_active && total>0 && commit.valid && take_pop);
    end else begin
        seen_active<=1;
        // Local caller ownership model. Allocation/complete are abstract API
        // actions, not proofs of real pools, packet completion or TX timing.
        if(allocate) begin
            assume(int'(allocate_id)<N_DESC);
            assume(owner[2*int'(allocate_id)+:2]==FREE);
            owner[2*int'(allocate_id)+:2]<=RX;
        end
        if(complete) begin
            assume(int'(complete_id)<N_DESC);
            assume(owner[2*int'(complete_id)+:2]==TX);
            owner[2*int'(complete_id)+:2]<=FREE;
        end
        if(take_pop) owner[2*int'(dispatch.desc)+:2]<=TX;
        if(commit.valid) begin
            assume(owner[2*int'(commit.desc)+:2]==RX || (allocate && allocate_id==commit.desc));
            owner[2*int'(commit.desc)+:2]<=QUEUED;
        end
        // Caller contract: a commit is an RX-owned descriptor, disjoint
        // from ALL pre-state queues (including the descriptor being popped).
        if (commit.valid) begin
            assume(int'(commit.qid)<N_Q && int'(commit.desc)<N_DESC);
            assume(total<N_DESC);
            for(integer q=0;q<N_Q;q=q+1)
                for(integer k=0;k<N_DESC;k=k+1)
                    if(k<length[q]) assume(commit.desc!=model[q][k]);
        end
        a_witness_owner: assert(witness_live==(owner[2*int'(witness_desc)+:2]==QUEUED));
        if(length[witness_qid]>0 && model[witness_qid][0]==witness_desc)
            a_witness_head: assert(heads[witness_qid*DESC_ID_W+:DESC_ID_W]==witness_desc);
        if(commit.valid && length[commit.qid]>0 &&
           !(take_pop && pop_qid==commit.qid && length[commit.qid]==1)) begin
            a_link_payload: assert(next_write.id==model[commit.qid][length[commit.qid]-1] && next_write.next_id==commit.desc);
        end
        a_link_port: assert(next_write.valid == (commit.valid && length[commit.qid]>0 &&
            !(take_pop && pop_qid==commit.qid && length[commit.qid]==1)));
        a_error: assert(!invariant_error);
        a_total: assert(total>=0 && total<=N_DESC);
        for(integer q=0;q<N_Q;q=q+1) begin
            assert(length[q]>=0 && length[q]<=N_DESC);
            if(length[q]>0) begin
                assert(tails[q*DESC_ID_W +: DESC_ID_W]==model[q][length[q]-1]);
            end
            for(integer k=0;k<N_DESC;k=k+1) begin
                if(k<length[q]) begin
                    assert(int'(model[q][k])<N_DESC);
                    assert(owner[2*int'(model[q][k])+:2]==QUEUED);
                    // Inductive representation invariant on the ACTUAL child.
                    if(k+1<length[q])
                        assert(links.next_ids[model[q][k]]==model[q][k+1]);
                    for(integer r=0;r<N_Q;r=r+1)
                        for(integer j=0;j<N_DESC;j=j+1)
                            if(j<length[r] && (q!=r || k!=j))
                                assert(model[q][k]!=model[r][j]);
                end
            end
            if(take_pop && pop_qid==Q_ID_W'(q))
                for(integer k=0;k<N_DESC-1;k=k+1) model[q][k]<=model[q][k+1];
            if(commit.valid && commit.qid==Q_ID_W'(q))
                model[q][length[q]-int'(take_pop && pop_qid==Q_ID_W'(q))]<=commit.desc;
            length[q]<=length[q]+int'(commit.valid && commit.qid==Q_ID_W'(q))-
                int'(take_pop && pop_qid==Q_ID_W'(q));
        end
        c_last_replace: cover(take_pop && commit.valid && pop_qid==commit.qid && length[pop_qid]==1);
        c_long_replace: cover(take_pop && commit.valid && pop_qid==commit.qid && length[pop_qid]>1);
        c_two_qids: cover(length[0]>0 && length[1]>0 && take_pop && commit.valid && pop_qid!=commit.qid);
        c_witness_live: cover(witness_live && length[witness_qid]>1);
        c_witness_reset: cover(reset_busy && witness_live);
        c_tx_owned: cover(owner[2*int'(witness_desc)+:2]==TX && total==0);
        c_full: cover(total==N_DESC);
        c_empty_attempt: cover(request_pop && length[pop_qid]==0 && commit.valid && pop_qid==commit.qid);
        c_reset_collision: cover(reset_busy && total==0 && request_pop && commit.valid);
    end
end
endmodule
