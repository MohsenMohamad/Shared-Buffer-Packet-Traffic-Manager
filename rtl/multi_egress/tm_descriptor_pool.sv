module tm_descriptor_pool #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (
    input  logic clk, rst_n, ready,
    input  logic [N_RX-1:0] reserve_commit,
    input  logic [N_TX:0] return_present,
    input  desc_id_t [N_TX:0] return_desc,
    output logic [N_RX-1:0] rank_valid,
    output desc_id_t [N_RX-1:0] rank_id,
    output desc_count_t free_count
);
`include "tm_multi_validate.svh"

    localparam int DELTA_W = DESC_COUNT_W + $clog2(N_TX + 2);
    logic [N_DESC-1:0] free_bits, returned;
    // Successive ranks remove only the pre-edge selection from the prior rank.
    logic [N_DESC-1:0] rank_bits [N_RX];
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
        logic [DELTA_W-1:0] commit_count, return_count;
        taken = '0;
        returned = '0;
        commit_count = '0;
        return_count = '0;
        for (int lane = 0; lane < N_RX; lane++)
            commit_count += DELTA_W'(reserve_commit[lane]);

        // The commit population consumes that many pre-edge ranks.
        for (int rank = 0; rank < N_RX; rank++)
            if (DELTA_W'(rank) < commit_count) taken |= rank_mask[rank];

        for (int lane = 0; lane <= N_TX; lane++) begin
            if (return_present[lane]) begin
                returned[return_desc[lane]] = 1'b1;
                return_count += DELTA_W'(1);
            end
        end
        free_next = DELTA_W'(free_count) + return_count - commit_count;
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
`ifdef TM_POOL_ASSERTIONS
    always @(posedge clk) begin : check_descriptor_contract
        logic [N_DESC-1:0] seen;
        seen = '0;
        if (ready) begin
            assert_old_descriptor_credit: assert ($countones(reserve_commit) <= int'(free_count))
                else $fatal(1, "POOL_ASSERT old_descriptor_credit");
            assert_descriptor_population: assert ($countones(free_bits) == int'(free_count))
                else $fatal(1, "POOL_ASSERT descriptor_population");

            for (int rank = 0; rank < N_RX; rank++) begin
                assert_descriptor_rank_valid: assert (rank_valid[rank] == (rank < int'(free_count)))
                    else $fatal(1, "POOL_ASSERT descriptor_rank_valid");
                if (rank_valid[rank]) begin
                    assert_descriptor_rank_old_free: assert (free_bits[rank_id[rank]] &&
                        !seen[rank_id[rank]])
                        else $fatal(1, "POOL_ASSERT descriptor_rank_old_free");
                    seen[rank_id[rank]] = 1'b1;
                end
            end

            seen = '0;
            for (int lane = 0; lane <= N_TX; lane++) begin
                if (return_present[lane]) begin
                    assert_descriptor_return_allocated: assert (!free_bits[return_desc[lane]])
                        else $fatal(1, "POOL_ASSERT descriptor_return_allocated");
                    assert_descriptor_return_distinct: assert (!seen[return_desc[lane]])
                        else $fatal(1, "POOL_ASSERT descriptor_return_distinct");
                    seen[return_desc[lane]] = 1'b1;
                end
            end
            assert_descriptor_delta_bounds: assert (free_next <= DELTA_W'(N_DESC))
                else $fatal(1, "POOL_ASSERT descriptor_delta_bounds");
        end
    end

    // Sample the edge's widened result and compare the stored count at the next active edge.
    desc_count_t expected_free_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) expected_free_count <= desc_count_t'(N_DESC);
        else if (ready) begin
            assert_descriptor_update: assert (free_count == expected_free_count)
                else $fatal(1, "POOL_ASSERT descriptor_update");
            expected_free_count <= desc_count_t'(free_next);
        end
    end
`endif
endmodule
