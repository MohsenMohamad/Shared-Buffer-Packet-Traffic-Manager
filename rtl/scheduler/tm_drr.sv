module tm_drr_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input config_t cfg,
    input logic [N_Q*DESC_ID_W-1:0] heads,
    input logic [N_Q*DESC_COUNT_W-1:0] counts,
    input logic [N_Q*DESC_INFO_W-1:0] head_info,
    input commit_t commit,
    input logic tx_ready,
    input tx_done_t tx_done,
    output dispatch_t dispatch,
    output logic [N_Q*DEFICIT_W-1:0] deficits
);
`include "tm_validate.svh"
// tm_validate guards DEFICIT_W for the inclusive bound 4096+MAX_PACKET_BYTES-1.
qid_t cursor, cursor_next;
logic visit_active, visit_next, tx_owned;
logic [N_Q*DEFICIT_W-1:0] deficits_next;
descriptor_t selected_info;
logic [DEFICIT_W:0] credit;
logic nonempty, replaced;

assign selected_info = head_info[cursor*DESC_INFO_W +: DESC_INFO_W];
assign nonempty = counts[cursor*DESC_COUNT_W +: DESC_COUNT_W]!=0;
assign replaced = commit.valid && commit.qid==cursor;
function automatic qid_t successor(input qid_t q);
    return int'(q)==N_Q-1 ? '0 : q+Q_ID_W'(1);
endfunction

// Separate elaborations: packet RR has no byte-credit state or arithmetic.
generate if (SCHED_MODE==0) begin : g_packet_rr
    always_comb begin
        dispatch = '0;
        deficits_next = '0;
        cursor_next = cursor;
        visit_next = 1'b0;
        credit = '0;
        if (rst_n && cfg.run && !tx_owned) begin
            if (!nonempty) cursor_next = successor(cursor);
            else if (tx_ready) begin
                dispatch = '{1'b1, cursor, heads[cursor*DESC_ID_W +: DESC_ID_W], selected_info};
                cursor_next = successor(cursor);
            end
        end
    end
end else begin : g_drr
    always_comb begin
        dispatch = '0;
        deficits_next = deficits;
        cursor_next = cursor;
        visit_next = visit_active;
        credit = {1'b0, deficits[cursor*DEFICIT_W +: DEFICIT_W]};
        if (rst_n && cfg.run && !tx_owned) begin
            if (!nonempty) begin
                deficits_next[cursor*DEFICIT_W +: DEFICIT_W] = '0;
                cursor_next = successor(cursor);
                visit_next = 1'b0;
            end else begin
                // This addition is recorded even if a fitting head must wait
                // for readiness. Continuing visits never receive it again.
                if (!visit_active)
                    credit = credit+(DEFICIT_W+1)'(cfg.quantum[cursor*13 +: 13]);
                deficits_next[cursor*DEFICIT_W +: DEFICIT_W] = credit[DEFICIT_W-1:0];
                visit_next = 1'b1;
                if (credit < (DEFICIT_W+1)'(selected_info.length)) begin
                    cursor_next = successor(cursor);
                    visit_next = 1'b0;
                end else if (tx_ready) begin
                    dispatch = '{1'b1, cursor, heads[cursor*DESC_ID_W +: DESC_ID_W], selected_info};
                    deficits_next[cursor*DEFICIT_W +: DEFICIT_W] =
                        DEFICIT_W'(credit-(DEFICIT_W+1)'(selected_info.length));
                    // Only a merged zero count closes a dispatched visit.
                    // A concurrent replacement is first eligible next cycle.
                    if (counts[cursor*DESC_COUNT_W +: DESC_COUNT_W]==1 && !replaced) begin
                        deficits_next[cursor*DEFICIT_W +: DEFICIT_W] = '0;
                        cursor_next = successor(cursor);
                        visit_next = 1'b0;
                    end
                end
            end
        end
    end
end endgenerate

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cursor <= '0;
        visit_active <= 1'b0;
        deficits <= '0;
        tx_owned <= 1'b0;
    end else begin
        cursor <= cursor_next;
        visit_active <= visit_next;
        deficits <= deficits_next;
        // tx_done cannot enable a decision on its own edge, even if ready
        // rises combinationally on the final output handshake.
        if (tx_done.valid) tx_owned <= 1'b0;
        if (dispatch.valid) tx_owned <= 1'b1;
    end
end
endmodule

