module admission #(
    parameter int P = 4, N_CELL = 1024, N_DESC = 256, MAX_BYTES = 1536, LOOKAHEAD = 0,
    localparam int Q = P * 4, B = $clog2(P), QB = $clog2(Q),
    localparam int K = $clog2(N_CELL+1), D = $clog2(N_DESC),
    localparam int LANES = P+1
) (
    input logic clk, rst_n,
    input logic dynamic_mode, wait_mode,
    input logic [P-1:0] header_valid, bad_first_beat,
    input logic [P-1:0][7:0] route, raw_class,
    input logic [P-1:0][15:0] length,
    input logic [Q-1:0][K-1:0] minimum, limit,
    input logic [Q-1:0][12:0] alpha,
    input logic [LANES-1:0] desc_return, credit_release,
    input logic [LANES-1:0][D-1:0] return_id,
    input logic [LANES-1:0][QB-1:0] release_qid,
    input logic [LANES-1:0][K-1:0] release_count,
    output logic [P-1:0] rx_grant, rx_reject, rx_wait, rx_abort,
    output logic [P-1:0][2:0] rx_reason,
    output logic [P-1:0][D-1:0] rx_desc,
    output logic [P-1:0][QB-1:0] rx_qid,
    output logic [P-1:0][K-1:0] rx_reserved,
    output logic [K-1:0] credit,
    output logic [Q-1:0][K-1:0] held,
    output logic invariant_error
);
    localparam int SUM = K + $clog2(Q+LANES+1);
    localparam int GROUP = N_DESC >= 16 ? 16 : N_DESC;
    localparam int GROUPS = N_DESC / GROUP;
    logic [N_DESC-1:0] free_desc, used_mask, returned_mask;
    logic [B-1:0] cursor;
    logic [Q-1:0][K-1:0] held_next;
    logic [K-1:0] credit_next;
    logic [P-1:0] grant, reject, pending, malformed;
    logic [P-1:0][2:0] reason;
    logic [P-1:0][D-1:0] selected;
    logic [P-1:0][QB-1:0] qid;
    logic [P-1:0][K-1:0] reserved;
    logic [B-1:0] cursor_next;
    logic bad_return;
    logic [SUM-1:0] held_wide [Q], credit_wide;

    function automatic logic [D-1:0] first_free(input logic [N_DESC-1:0] bits);
        logic [GROUPS-1:0] nonempty;
        logic [D-1:0] block_id, within_group;
        logic [GROUP-1:0] local_bits;
        for (int g = 0; g < GROUPS; g++)
            nonempty[g] = |bits[g*GROUP +: GROUP];
        block_id = '0;
        for (int g = GROUPS-1; g >= 0; g--)
            if (nonempty[g]) block_id = D'(g);
        local_bits = bits[block_id * GROUP +: GROUP];
        within_group = '0;
        for (int b = GROUP-1; b >= 0; b--)
            if (local_bits[b]) within_group = D'(b);
        return D'(block_id * GROUP) | within_group;
    endfunction

    function automatic logic policy(
        input logic [K:0] available, occupancy, protected_free, count,
        input logic [K:0] min_cells, static_limit,
        input logic [12:0] a
    );
        logic [K:0] excess, excess_next, spill, shared_next;
        logic [K+13:0] product;
        excess = occupancy > min_cells ? occupancy - min_cells : '0;
        excess_next = occupancy + count > min_cells ? occupancy + count - min_cells : '0;
        spill = excess_next - excess;
        shared_next = available >= protected_free + spill ? available - protected_free - spill : '0;
        product = a * shared_next;
        return dynamic_mode
            ? (spill == 0 || (available >= protected_free + spill && excess_next <= (product >> 8)))
            : (occupancy + count <= static_limit);
    endfunction

    // The lookahead version evaluates all possible earlier grant masks before
    // the lane decisions are known. A mask that overdraws credit is unreachable.
    logic [P-1:0][QB-1:0] lane_q;
    logic [P-1:0][K:0] lane_n;
    logic [P-1:0][(1 << (P-1))-1:0][1:0] look_result;
    logic [P-1:0] ranked_valid;
    logic [P-1:0][D-1:0] ranked_id;
    logic [K:0] old_protected, full_minimum;

    always_comb begin : inputs_and_minima
        logic [SUM-1:0] min_sum, protected_sum;
        min_sum = '0;
        protected_sum = '0;
        for (int j = 0; j < Q; j++) begin
            min_sum += SUM'(minimum[j]);
            if (minimum[j] > held[j])
                protected_sum += SUM'(minimum[j]) - SUM'(held[j]);
        end
        old_protected = (K+1)'(protected_sum);
        full_minimum = (K+1)'(min_sum);
        for (int lane = 0; lane < P; lane++) begin
            automatic logic [B-1:0] port = cursor + B'(lane);
            lane_q[lane] = {route[port][B-1:0], raw_class[port][1:0]};
            lane_n[lane] = (K+1)'(({1'b0, length[port]} + 17'd63) >> 6);
        end
    end

    if (LOOKAHEAD != 0) begin : parallel_prefix
        always_comb begin : rank_ids
            logic [N_DESC-1:0] available;
            available = free_desc;
            for (int rank = 0; rank < P; rank++) begin
                ranked_valid[rank] = |available;
                ranked_id[rank] = first_free(available);
                available[ranked_id[rank]] = 1'b0;
            end
        end

        for (genvar lane = 0; lane < P; lane++) begin : positions
            for (genvar mask = 0; mask < (1 << (P-1)); mask++) begin : subsets
                if (mask < (1 << lane)) begin : reachable_subset
                    always_comb begin
                        logic [K:0] u, prot, h, old_h, used_protection;
                        logic enough;
                        u = (K+1)'(credit);
                        prot = old_protected;
                        h = (K+1)'(held[lane_q[lane]]);
                        old_h = '0;
                        used_protection = '0;
                        enough = 1'b1;
                        for (int j = 0; j < lane; j++) begin
                            if ((mask >> j) & 1) begin
                                enough = enough && u >= lane_n[j];
                                u -= lane_n[j];
                                old_h = (K+1)'(held[lane_q[j]]);
                                for (int prior = 0; prior < j; prior++)
                                    if (((mask >> prior) & 1) && lane_q[prior] == lane_q[j])
                                        old_h += lane_n[prior];
                                used_protection = minimum[lane_q[j]] > old_h
                                    ? (K+1)'(minimum[lane_q[j]]) - old_h : '0;
                                prot -= used_protection < lane_n[j] ? used_protection : lane_n[j];
                                if (lane_q[j] == lane_q[lane]) h += lane_n[j];
                            end
                        end
                        if (!enough || u < lane_n[lane])
                            look_result[lane][mask] = 2'd1;
                        else if (!policy(u, h, prot, lane_n[lane], (K+1)'(minimum[lane_q[lane]]),
                                         (K+1)'(limit[lane_q[lane]]), alpha[lane_q[lane]]))
                            look_result[lane][mask] = 2'd2;
                        else
                            look_result[lane][mask] = 2'd0;
                    end
                end else begin : unused_subset
                    assign look_result[lane][mask] = '0;
                end
            end
        end
    end else begin : serial_prefix
        assign ranked_valid = '0;
        assign ranked_id = '0;
        assign look_result = '0;
    end

    always_comb begin : prefix
        logic [K:0] u, protected_free, h, min_at_q, n, consumed;
        logic [QB-1:0] q;
        logic [B-1:0] p, earlier_count;
        logic [D-1:0] d;
        logic [N_DESC-1:0] remaining;
        logic [P-2:0] earlier;
        logic serviced, any_descriptor;
        logic [1:0] fit;
        protected_free = old_protected;
        u = (K+1)'(credit);
        earlier = '0;
        earlier_count = '0;
        remaining = free_desc;
        grant = '0;
        reject = '0;
        pending = '0;
        malformed = '0;
        reason = '0;
        selected = '0;
        qid = '0;
        reserved = '0;
        used_mask = '0;
        serviced = 1'b0;
        cursor_next = cursor;
        consumed = '0;
        for (int lane = 0; lane < P; lane++) begin
            p = cursor + B'(lane);
            q = lane_q[lane];
            qid[p] = q;
            n = lane_n[lane];
            h = (K+1)'(held[q]);
            for (int j = 0; j < P; j++)
                if (grant[j] && qid[j] == q) h += (K+1)'(reserved[j]);
            min_at_q = (K+1)'(minimum[q]);
            if (LOOKAHEAD != 0) begin
                d = ranked_id[earlier_count];
                any_descriptor = ranked_valid[earlier_count];
                fit = look_result[lane][earlier];
            end else begin
                d = first_free(remaining);
                any_descriptor = |remaining;
                if (n > u)
                    fit = 2'd1;
                else if (!policy(u, h, protected_free, n, min_at_q, (K+1)'(limit[q]), alpha[q]))
                    fit = 2'd2;
                else
                    fit = 2'd0;
            end
            if (header_valid[p]) begin
                if (route[p] >= 8'(P) || raw_class[p] >= 8'd4) reason[p] = 3'd1;
                else if (length[p] < 16'd60 || length[p] > 16'(MAX_BYTES)) reason[p] = 3'd2;
                else if (!policy((K+1)'(N_CELL), '0, full_minimum, n, min_at_q, (K+1)'(limit[q]), alpha[q]))
                    reason[p] = 3'd3;
                else if (!any_descriptor) begin
                    reason[p] = 3'd4;
                    pending[p] = wait_mode;
                end else if (fit == 2'd1) begin
                    reason[p] = 3'd5;
                    pending[p] = wait_mode;
                end else if (fit == 2'd2) begin
                    reason[p] = 3'd3;
                    pending[p] = wait_mode;
                end else begin
                    grant[p] = 1'b1;
                    malformed[p] = bad_first_beat[p];
                    selected[p] = d;
                    reserved[p] = K'(n);
                    remaining[d] = 1'b0;
                    if (lane < P-1) earlier[lane] = 1'b1;
                    earlier_count += B'(1);
                    used_mask[d] = 1'b1;
                    u -= n;
                    consumed = min_at_q > h ? min_at_q - h : '0;
                    protected_free -= consumed < n ? consumed : n;
                end
                reject[p] = reason[p] != '0 && !pending[p];
                if (!serviced && !pending[p]) begin
                    cursor_next = p + B'(1);
                    serviced = 1'b1;
                end
            end
        end
        credit_wide = SUM'(u);
        for (int j = 0; j < Q; j++) begin
            held_wide[j] = SUM'(held[j]);
            for (int i = 0; i < P; i++)
                if (grant[i] && qid[i] == QB'(j)) held_wide[j] += SUM'(reserved[i]);
        end
        bad_return = 1'b0;
        returned_mask = '0;
        for (int lane = 0; lane < LANES; lane++) begin
            if (desc_return[lane]) begin
                if (free_desc[return_id[lane]] || returned_mask[return_id[lane]])
                    bad_return = 1'b1;
                returned_mask[return_id[lane]] = 1'b1;
            end
            if (credit_release[lane]) begin
                credit_wide += SUM'(release_count[lane]);
                held_wide[release_qid[lane]] -= SUM'(release_count[lane]);
            end
        end
        credit_next = K'(credit_wide);
        for (int j = 0; j < Q; j++) begin
            held_next[j] = K'(held_wide[j]);
            if (held_wide[j] > SUM'(N_CELL)) bad_return = 1'b1;
        end
        if (credit_wide > SUM'(N_CELL)) bad_return = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cursor <= '0;
            free_desc <= '1;
            credit <= K'(N_CELL);
            held <= '0;
            rx_grant <= '0;
            rx_reject <= '0;
            rx_wait <= '0;
            rx_abort <= '0;
            rx_reason <= '0;
            rx_desc <= '0;
            rx_qid <= '0;
            rx_reserved <= '0;
            invariant_error <= 1'b0;
        end else begin
            cursor <= cursor_next;
            free_desc <= (free_desc & ~used_mask) | returned_mask;
            credit <= credit_next;
            held <= held_next;
            rx_grant <= grant;
            rx_reject <= reject;
            rx_wait <= pending;
            rx_abort <= malformed;
            rx_reason <= reason;
            rx_desc <= selected;
            rx_qid <= qid;
            rx_reserved <= reserved;
            invariant_error <= invariant_error || bad_return;
        end
    end
endmodule
