// F01-compatible observer for a future production pool binding.
module multi_egress_pool_obligations #(
    parameter int N_RX = 2,
    parameter int N_TX = N_RX,
    parameter int N_CELL = 16,
    parameter int N_DESC = 8,
    localparam int N_Q = 4 * N_TX,
    localparam int CW = $clog2(N_CELL),
    localparam int DW = $clog2(N_DESC),
    localparam int QW = $clog2(N_Q),
    localparam int KW = $clog2(N_CELL + 1),
    localparam int DCW = $clog2(N_DESC + 1)
)(
    input logic clk, reset_n, initialized,
    input logic [CW-1:0] witness_cell,
    input logic [DW-1:0] witness_desc,
    input logic [N_CELL-1:0] cell_free,
    input logic [N_DESC-1:0] desc_free,
    input logic [KW-1:0] f_count, u_count, r_count, a_count,
    input logic [DCW-1:0] d_count,
    input logic [N_Q-1:0][KW-1:0] h_count,
    input logic [N_RX-1:0] grant,
    input logic [N_RX-1:0][DW-1:0] grant_desc,
    input logic [N_RX-1:0][QW-1:0] grant_queue,
    input logic [N_RX-1:0][KW-1:0] grant_cells,
    input logic write_cell,
    input logic [CW-1:0] write_addr,
    input logic [N_TX:0] release_cell, release_desc,
    input logic [N_TX:0][CW-1:0] release_addr,
    input logic [N_TX:0][DW-1:0] release_id,
    input logic [N_TX-1:0][QW-1:0] retire_queue,
    input logic cleanup_done,
    input logic [QW-1:0] cleanup_queue,
    input logic [KW-1:0] cleanup_credit,
    // Identity fidelity is established where each caller still knows its epoch.
    input logic write_owner_matches, cleanup_owner_matches,
    input logic [N_TX:0] cell_owner_matches, desc_owner_matches
);
    logic history = 1'b0;
    logic [N_CELL-1:0] next_cell_free;
    logic [N_DESC-1:0] next_desc_free;
    int expected_f, expected_u, expected_r, expected_a, expected_d;
    int queue_delta[N_Q];
    int after_credit, total_owned;
    logic selected_witness_desc, returned_witness_desc, returned_witness_cell;

    always_comb begin
        next_cell_free = cell_free;
        next_desc_free = desc_free;
        if (write_cell)
            next_cell_free[write_addr] = 0;
        for (int i = 0; i < N_RX; ++i)
            if (grant[i])
                next_desc_free[grant_desc[i]] = 0;
        for (int i = 0; i <= N_TX; ++i) begin
            if (release_cell[i])
                next_cell_free[release_addr[i]] = 1;
            if (release_desc[i])
                next_desc_free[release_id[i]] = 1;
        end

        after_credit = int'(u_count);
        expected_f = int'(f_count) + $countones(release_cell) - int'(write_cell);
        expected_a = int'(a_count) - $countones(release_cell) + int'(write_cell);
        expected_d = int'(d_count) + $countones(release_desc) - $countones(grant);
        total_owned = 0;
        queue_delta = '{default:0};
        selected_witness_desc = 0;
        returned_witness_desc = 0;
        returned_witness_cell = 0;
        for (int i = 0; i < N_RX; ++i) begin
            if (grant[i]) begin
                after_credit -= int'(grant_cells[i]);
                queue_delta[grant_queue[i]] += int'(grant_cells[i]);
                selected_witness_desc |= grant_desc[i] == witness_desc;
            end
        end
        for (int i = 0; i < N_TX; ++i)
            if (release_cell[i])
                queue_delta[retire_queue[i]] -= 1;
        if (cleanup_done)
            queue_delta[cleanup_queue] -= int'(cleanup_credit);
        for (int q = 0; q < N_Q; ++q)
            total_owned += int'(h_count[q]);
        for (int i = 0; i <= N_TX; ++i) begin
            returned_witness_desc |= release_desc[i] && release_id[i] == witness_desc;
            returned_witness_cell |= release_cell[i] && release_addr[i] == witness_cell;
        end
        expected_u = after_credit + $countones(release_cell[N_TX-1:0]) + int'(cleanup_credit);
        expected_r = expected_f - expected_u;
    end

    for (genvar lane = 0; lane < N_RX; ++lane) begin : grants
        always @(posedge clk)
            if (reset_n && initialized && grant[lane])
                a_grant_old_free: assert(desc_free[grant_desc[lane]] && grant_cells[lane] != 0);
        for (genvar old = 0; old < lane; ++old) begin : distinct
            always @(posedge clk)
                if (reset_n && initialized)
                    a_distinct: assert(!grant[lane] || !grant[old] || grant_desc[lane] != grant_desc[old]);
        end
    end

    for (genvar lane = 0; lane <= N_TX; ++lane) begin : returns
        always @(posedge clk) begin
            if (reset_n && initialized) begin
                a_cell_live_return: assert(!release_cell[lane] ||
                                            (!cell_free[release_addr[lane]] && cell_owner_matches[lane]));
                a_desc_live_return: assert(!release_desc[lane] ||
                                            (!desc_free[release_id[lane]] && desc_owner_matches[lane]));
            end
        end
        for (genvar old = 0; old < lane; ++old) begin : distinct
            always @(posedge clk) begin
                if (reset_n && initialized) begin
                    a_distinct_cells: assert(!release_cell[lane] || !release_cell[old] ||
                                             release_addr[lane] != release_addr[old]);
                    a_distinct_desc: assert(!release_desc[lane] || !release_desc[old] ||
                                            release_id[lane] != release_id[old]);
                end
            end
        end
    end

    for (genvar queue = 0; queue < N_Q; ++queue) begin : queues
        always @(posedge clk)
            if (history && reset_n && initialized && $past(reset_n && initialized))
                a_queue_credit: assert(int'(h_count[queue]) ==
                                       $past(int'(h_count[queue]) + queue_delta[queue]));
    end

    always @(posedge clk) begin
        history <= 1;
        if (history) begin
            assume(witness_cell == $past(witness_cell));
            assume(witness_desc == $past(witness_desc));
        end

        if (reset_n && initialized) begin
            a_physical_count: assert(int'(f_count) == $countones(cell_free));
            a_descriptor_count: assert(int'(d_count) == $countones(desc_free));
            a_conservation: assert(int'(f_count) == int'(u_count) + int'(r_count) &&
                                  N_CELL == int'(a_count) + int'(f_count) &&
                                  N_CELL == int'(u_count) + total_owned);
            a_prefix_credit: assert(after_credit >= 0);
            a_materialize_old_free: assert(!write_cell || (cell_free[write_addr] && write_owner_matches));
            a_cleanup_atomic: assert(cleanup_done == release_desc[N_TX] &&
                                     (cleanup_done ? cleanup_credit > 0 && cleanup_owner_matches
                                                   : cleanup_credit == 0));
            c_cell_exhaustion: cover(f_count == 0 && release_cell != 0);
            c_desc_exhaustion: cover(d_count == 0 && release_desc != 0);
            c_write_and_return: cover(write_cell && release_cell != 0);
            c_grant_and_return: cover(grant != 0 && release_desc != 0);
            c_all_grants: cover(&grant && |release_desc[N_TX-1:0]);
            c_all_cells: cover(&release_cell && write_cell);
            c_all_descriptors: cover(&release_desc);
            c_cleanup_only_credit: cover(cleanup_done && !release_cell[N_TX] && cleanup_credit != 0);
            c_tx_and_abort: cover(|release_cell[N_TX-1:0] && release_cell[N_TX]);

            if (history && $past(reset_n && initialized)) begin
                a_cell_merge: assert(cell_free == $past(next_cell_free));
                a_desc_merge: assert(desc_free == $past(next_desc_free));
                a_merged_counts: assert(int'(f_count) == $past(expected_f) &&
                                        int'(d_count) == $past(expected_d) &&
                                        int'(u_count) == $past(expected_u) &&
                                        int'(r_count) == $past(expected_r) &&
                                        int'(a_count) == $past(expected_a));
                c_cell_next_edge_reuse: cover($past(returned_witness_cell) &&
                                              write_cell && write_addr == witness_cell);
                c_desc_next_edge_reuse: cover($past(returned_witness_desc) && selected_witness_desc);
            end
            if (history && !$past(initialized)) begin
                a_reset_pool: assert((&cell_free) && (&desc_free) && u_count == KW'(N_CELL) &&
                                     r_count == 0 && a_count == 0 && total_owned == 0);
            end
        end
        if (history && !reset_n && $past(reset_n && initialized))
            c_active_reset: cover($past(a_count != 0 && r_count != 0 && d_count != DCW'(N_DESC)));
    end
endmodule
