module tm_reservation_accounting #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (
    input  logic clk, rst_n, ready,
    input  logic [N_RX-1:0] reserve_offer,
    input  desc_count_t free_desc,
    input  cell_count_t [N_RX-1:0] reserve_cells,
    input  qid_t [N_RX-1:0] reserve_qid,
    input  logic [N_TX:0] release_present,
    input  cell_count_t [N_TX:0] release_cells,
    input  qid_t [N_TX:0] release_qid,
    output logic [N_RX-1:0] grant,
    output rx_id_t [N_RX-1:0] grant_rank,
    output cell_count_t unreserved,
    output cell_count_t [N_Q-1:0] held
);
`include "tm_multi_validate.svh"

    localparam int DELTA_W = CELL_COUNT_W + $clog2(N_RX + N_TX + 2);
    localparam int MAX_FRAME_CELLS = (MAX_FRAME_BYTES + 63) / 64;
    typedef logic [DELTA_W-1:0] delta_t;
    delta_t [N_RX-1:0] reserved_delta;
    delta_t [N_TX:0] released_delta;
    // The prefix and the caller's ownership guarantee bound next U and H by N_CELL.
    /* verilator lint_off UNUSEDSIGNAL */
    delta_t unreserved_next;
    /* verilator lint_on UNUSEDSIGNAL */

    always_comb begin : grant_prefix
        delta_t remaining, asked;
        rx_id_t rank;
        remaining = delta_t'(unreserved);
        rank = '0;
        grant = '0;
        grant_rank = '0;
        for (int lane = 0; lane < N_RX; lane++) begin
            asked = delta_t'(reserve_cells[lane]);
            if (ready && reserve_offer[lane] && desc_count_t'(rank) < free_desc &&
                asked != 0 && asked <= delta_t'(MAX_FRAME_CELLS) && asked <= remaining) begin
                grant[lane] = 1'b1;
                grant_rank[lane] = rank;
                remaining -= asked;
                // The counter need only encode the ranks used within this prefix.
                rank += rx_id_t'(1);
            end
        end
    end

    for (genvar lane = 0; lane < N_RX; lane++) begin : g_reservation
        assign reserved_delta[lane] = grant[lane] ? delta_t'(reserve_cells[lane]) : '0;
    end

    for (genvar lane = 0; lane <= N_TX; lane++) begin : g_release
        assign released_delta[lane] = release_present[lane] ? delta_t'(release_cells[lane]) : '0;
    end

    always_comb begin : merge_pool_credit
        delta_t reserved_sum, released_sum;
        reserved_sum = '0;
        released_sum = '0;
        for (int lane = 0; lane < N_RX; lane++) reserved_sum += reserved_delta[lane];
        for (int lane = 0; lane <= N_TX; lane++) released_sum += released_delta[lane];
        unreserved_next = delta_t'(unreserved) + released_sum - reserved_sum;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) unreserved <= cell_count_t'(N_CELL);
        else if (ready) unreserved <= cell_count_t'(unreserved_next);
    end

    for (genvar queue_index = 0; queue_index < N_Q; queue_index++) begin : g_held
        // The two widened sums are independent before the single edge update.
        /* verilator lint_off UNUSEDSIGNAL */
        delta_t held_next;
        /* verilator lint_on UNUSEDSIGNAL */
        always_comb begin : merge_queue_credit
            delta_t reserved_sum, released_sum;
            reserved_sum = '0;
            released_sum = '0;
            for (int lane = 0; lane < N_RX; lane++)
                if (reserve_qid[lane] == qid_t'(queue_index)) reserved_sum += reserved_delta[lane];
            for (int lane = 0; lane <= N_TX; lane++)
                if (release_qid[lane] == qid_t'(queue_index)) released_sum += released_delta[lane];
            held_next = delta_t'(held[queue_index]) + reserved_sum - released_sum;
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) held[queue_index] <= '0;
            else if (ready) held[queue_index] <= cell_count_t'(held_next);
        end
    end
endmodule
