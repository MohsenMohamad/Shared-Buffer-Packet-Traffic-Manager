module tm_reservation_accounting #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (
    input  logic clk, rst_n, ready,
    input  logic [N_RX-1:0] reserve_commit,
    input  cell_count_t [N_RX-1:0] reserve_cells,
    input  qid_t [N_RX-1:0] reserve_qid,
    input  logic [N_TX:0] release_present,
    input  cell_count_t [N_TX:0] release_cells,
    input  qid_t [N_TX:0] release_qid,
    output cell_count_t unreserved,
    output cell_count_t [N_Q-1:0] held
);
`include "tm_multi_validate.svh"

    localparam int DELTA_W = CELL_COUNT_W + $clog2(N_RX + N_TX + 2);
    typedef logic [DELTA_W-1:0] delta_t;
    delta_t [N_RX-1:0] reserved_delta;
    delta_t [N_TX:0] released_delta;
    // The caller's committed prefix and release contract bound next U and H by N_CELL.
    /* verilator lint_off UNUSEDSIGNAL */
    delta_t unreserved_next;
    /* verilator lint_on UNUSEDSIGNAL */

    for (genvar lane = 0; lane < N_RX; lane++) begin : g_reservation
        assign reserved_delta[lane] = reserve_commit[lane] ? delta_t'(reserve_cells[lane]) : '0;
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

`ifdef TM_POOL_ASSERTIONS
    localparam int MAX_FRAME_CELLS = (MAX_FRAME_BYTES + 63) / 64;
    always @(posedge clk) begin : check_committed_credit
        int remaining;
        if (ready) begin
            remaining = int'(unreserved);
            for (int lane = 0; lane < N_RX; lane++) begin
                if (reserve_commit[lane]) begin
                    assert_reservation_count: assert (reserve_cells[lane] != 0 &&
                        int'(reserve_cells[lane]) <= MAX_FRAME_CELLS)
                        else $fatal(1, "POOL_ASSERT reservation_count");
                    assert_old_credit: assert (int'(reserve_cells[lane]) <= remaining)
                        else $fatal(1, "POOL_ASSERT old_credit");
                    remaining -= int'(reserve_cells[lane]);
                end
            end
            assert_credit_delta_bounds: assert (unreserved_next <= delta_t'(N_CELL))
                else $fatal(1, "POOL_ASSERT credit_delta_bounds");
        end
    end

    cell_count_t expected_credit;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) expected_credit <= cell_count_t'(N_CELL);
        else if (ready) begin
            assert_credit_update: assert (unreserved == expected_credit)
                else $fatal(1, "POOL_ASSERT credit_update");
            expected_credit <= cell_count_t'(unreserved_next);
        end
    end
`endif

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

`ifdef TM_POOL_ASSERTIONS
        cell_count_t expected_held;
        always_ff @(posedge clk or negedge rst_n) begin : check_queue_delta
            int added, released;
            int expected;
            if (!rst_n) expected_held <= '0;
            else if (ready) begin
                assert_queue_update: assert (held[queue_index] == expected_held)
                    else $fatal(1, "POOL_ASSERT queue_update");
                added = 0;
                released = 0;
                for (int lane = 0; lane < N_RX; lane++)
                    if (reserve_commit[lane] && reserve_qid[lane] == qid_t'(queue_index))
                        added += int'(reserve_cells[lane]);
                for (int lane = 0; lane <= N_TX; lane++)
                    if (release_present[lane] && release_qid[lane] == qid_t'(queue_index))
                        released += int'(release_cells[lane]);

                assert_old_queue_release: assert (released <= int'(held[queue_index]))
                    else $fatal(1, "POOL_ASSERT old_queue_release");
                expected = int'(held[queue_index]) + added - released;
                assert_queue_delta: assert (expected >= 0 && expected <= N_CELL &&
                    int'(held_next) == expected)
                    else $fatal(1, "POOL_ASSERT queue_delta");
                expected_held <= cell_count_t'(expected);
            end
        end
`endif
    end
endmodule
