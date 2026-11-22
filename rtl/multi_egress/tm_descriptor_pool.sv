module tm_descriptor_pool #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (
    input  logic clk, rst_n, ready,
    input  logic [N_RX-1:0] grant,
    input  logic [N_TX:0] return_present,
    input  desc_id_t [N_TX:0] return_desc,
    output desc_id_t [N_RX-1:0] rank_id,
    output desc_count_t free_count
);
`include "tm_multi_validate.svh"

    localparam int DELTA_W = DESC_COUNT_W + $clog2(N_TX + 2);
    logic [N_DESC-1:0] free_bits, returned;
    logic [N_RX-1:0] rank_valid;
    // Successive ranks remove only the pre-edge selection from the prior rank.
    /* verilator lint_off UNOPTFLAT */
    logic [N_DESC-1:0] rank_bits [N_RX];
    /* verilator lint_on UNOPTFLAT */
    logic [N_DESC-1:0] rank_mask [N_RX];
    logic [N_DESC-1:0] taken;
    // The atomic grant/return contract bounds the widened result by N_DESC.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [DELTA_W-1:0] free_next;
    /* verilator lint_on UNUSEDSIGNAL */

    assign rank_bits[0] = free_bits;
    for (genvar rank = 0; rank < N_RX; rank++) begin : g_rank
        tm_pool_first_free #(.SIZE(N_DESC), .GROUP_SIZE(N_DESC >= 16 ? 16 : N_DESC)) selector (
            .available(rank_bits[rank]), .any_free(rank_valid[rank]), .selected(rank_id[rank])
        );
        assign rank_mask[rank] = rank_valid[rank] ? (N_DESC'(1) << rank_id[rank]) : '0;
        if (rank + 1 < N_RX) begin : g_next_rank
            assign rank_bits[rank+1] = rank_bits[rank] & ~rank_mask[rank];
        end
    end

    always_comb begin : merge_ownership
        logic [DELTA_W-1:0] grant_count, return_count;
        taken = '0;
        returned = '0;
        grant_count = '0;
        return_count = '0;
        for (int lane = 0; lane < N_RX; lane++)
            grant_count += DELTA_W'(grant[lane]);

        // One rank per successful grant, regardless of holes in the offer/result vectors.
        for (int rank = 0; rank < N_RX; rank++)
            if (DELTA_W'(rank) < grant_count) taken |= rank_mask[rank];

        for (int lane = 0; lane <= N_TX; lane++) begin
            if (return_present[lane]) begin
                returned[return_desc[lane]] = 1'b1;
                return_count += DELTA_W'(1);
            end
        end
        free_next = DELTA_W'(free_count) + return_count - grant_count;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            free_bits <= '1;
            free_count <= desc_count_t'(N_DESC);
        end else if (ready) begin
            free_bits <= (free_bits & ~taken) | returned;
            free_count <= desc_count_t'(free_next);
        end
    end
endmodule
