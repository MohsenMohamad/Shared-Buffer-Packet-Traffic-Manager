module tm_queue_ctrl_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input commit_t commit,
    input dispatch_t dispatch,
    input desc_id_t old_head_next,
    output logic [N_Q*DESC_ID_W-1:0] heads,
    output logic [N_Q*DESC_ID_W-1:0] tails,
    output logic [N_Q*DESC_COUNT_W-1:0] counts,
    output desc_link_write_t next_write,
    output logic invariant_error
);
`include "tm_validate.svh"
logic [N_Q*DESC_ID_W-1:0] heads_next, tails_next;
logic [N_Q*DESC_COUNT_W-1:0] counts_next;
logic push, pop, bad_action;

always_comb begin
    // Both decisions use registered state. Publication has no ready/bypass.
    pop = 1'b0;
    if (rst_n && dispatch.valid && int'(dispatch.qid)<N_Q)
        pop = counts[dispatch.qid*DESC_COUNT_W +: DESC_COUNT_W]!=0 &&
              dispatch.desc==heads[dispatch.qid*DESC_ID_W +: DESC_ID_W];
    push = 1'b0;
    if (rst_n && commit.valid && int'(commit.qid)<N_Q && int'(commit.desc)<N_DESC)
        push = int'(counts[commit.qid*DESC_COUNT_W +: DESC_COUNT_W])<N_DESC ||
               (pop && dispatch.qid==commit.qid);
    bad_action = (commit.valid && !push) || (dispatch.valid && !pop);
    heads_next = heads;
    tails_next = tails;
    counts_next = counts;
    next_write = '0;
    for (integer q=0; q<N_Q; q=q+1) begin
        case ({push && commit.qid==Q_ID_W'(q), pop && dispatch.qid==Q_ID_W'(q)})
            2'b10: begin
                if (counts[q*DESC_COUNT_W +: DESC_COUNT_W]==0)
                    heads_next[q*DESC_ID_W +: DESC_ID_W] = commit.desc;
                else begin
                    next_write.valid = 1'b1;
                    next_write.id = tails[q*DESC_ID_W +: DESC_ID_W];
                    next_write.next_id = commit.desc;
                end
                tails_next[q*DESC_ID_W +: DESC_ID_W] = commit.desc;
                counts_next[q*DESC_COUNT_W +: DESC_COUNT_W] =
                    counts[q*DESC_COUNT_W +: DESC_COUNT_W] + DESC_COUNT_W'(1);
            end
            2'b01: begin
                if (counts[q*DESC_COUNT_W +: DESC_COUNT_W]>1)
                    heads_next[q*DESC_ID_W +: DESC_ID_W] = old_head_next;
                counts_next[q*DESC_COUNT_W +: DESC_COUNT_W] =
                    counts[q*DESC_COUNT_W +: DESC_COUNT_W] - DESC_COUNT_W'(1);
            end
            2'b11: begin
                // The old last link is stale. Replacement must install the new
                // singleton directly; the dispatched descriptor remains TX-owned.
                if (counts[q*DESC_COUNT_W +: DESC_COUNT_W]==1)
                    heads_next[q*DESC_ID_W +: DESC_ID_W] = commit.desc;
                else begin
                    heads_next[q*DESC_ID_W +: DESC_ID_W] = old_head_next;
                    next_write.valid = 1'b1;
                    next_write.id = tails[q*DESC_ID_W +: DESC_ID_W];
                    next_write.next_id = commit.desc;
                end
                tails_next[q*DESC_ID_W +: DESC_ID_W] = commit.desc;
            end
            default: begin end
        endcase
    end
end
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        heads <= '0;
        tails <= '0;
        counts <= '0;
        invariant_error <= 1'b0;
    end else begin
        heads <= heads_next;
        tails <= tails_next;
        counts <= counts_next;
        invariant_error <= invariant_error || bad_action;
    end
end
endmodule
