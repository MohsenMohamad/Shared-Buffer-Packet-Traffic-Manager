module admission #(
    parameter int P = 4, N_CELL = 1024, N_DESC = 256, MAX_BYTES = 1536, LOOKAHEAD = 0, RX_FRAMING = 0,
    localparam int Q = P * 4, B = $clog2(P), QB = $clog2(Q),
    localparam int K = $clog2(N_CELL+1), D = $clog2(N_DESC),
    localparam int LANES = P+1
) (
    input logic clk, rst_n,
    input logic dynamic_mode, wait_mode,
    input logic [P-1:0] header_valid, bad_first_beat,
    input logic [P-1:0][7:0] first_keep,
    input logic [P-1:0] first_last, receive_space,
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
`ifdef QUEUE_CONTROL_CONNECTED
    , output logic [P-1:0] service_grant, service_abort
    , output logic [P-1:0][D-1:0] service_desc
    , output logic [P-1:0][QB-1:0] service_qid
    , output logic [P-1:0][K-1:0] service_count
`endif
);
    localparam bit FACTORED = LOOKAHEAD >= 2;
    localparam bit STAGED = LOOKAHEAD == 3;
    localparam bit BALANCED = LOOKAHEAD == 4;
    localparam int COUNT = $clog2((MAX_BYTES + 63) / 64 + 1);
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

`ifdef QUEUE_CONTROL_CONNECTED
    assign service_grant = grant;
    assign service_abort = malformed;
    assign service_desc = selected;
    assign service_qid = qid;
    assign service_count = reserved;
`endif

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
            ? (spill == 0 || (available >= protected_free + spill && (K+14)'(excess_next) <= (product >> 8)))
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
    logic [P-1:0][QB-1:0] decision_q;
    logic [P-1:0][K:0] decision_n;
    logic [P-1:0] decision_valid, decision_bad_beat, decision_id_valid;
    wire [P-1:0] service_headers = RX_FRAMING != 0 ? header_valid & receive_space : header_valid;
    wire [P-1:0] malformed_first;
    for (genvar p = 0; p < P; p++) begin : framing
        // No legal profile finishes a frame in its first eight-byte beat.
        assign malformed_first[p] = RX_FRAMING != 0 ? first_last[p] || first_keep[p] != 8'hff
                                                    : bad_first_beat[p];
    end
    logic [P-1:0][2:0] header_error, decision_error;
    logic [P-1:0][D-1:0] decision_id;
    logic [P-1:0][K:0] lane_deficit, lane_excess;
    logic [P-1:0][12:0] lane_alpha;

    typedef struct packed {
        logic enough, within_shared, within_minimum, within_limit;
        logic [K:0] shared_next, excess;
    } fit_terms_t;

    function automatic logic [1:0] evaluate_fit(input fit_terms_t terms, input logic [12:0] a);
        logic [K+13:0] product;
        product = a * terms.shared_next;
        if (!terms.enough)
            return 2'd1;
        if (dynamic_mode)
            return terms.within_minimum ||
                   (terms.within_shared && (K+14)'(terms.excess) <= (product >> 8))
                   ? 2'd0 : 2'd2;
        return terms.within_limit ? 2'd0 : 2'd2;
    endfunction

    for (genvar lane = 0; lane < P; lane++) begin : header_check
        wire [B-1:0] port = cursor + B'(lane);
        wire [QB-1:0] q = lane_q[lane];
        assign lane_deficit[lane] = minimum[q] > held[q] ? (K+1)'(minimum[q] - held[q]) : '0;
        assign lane_excess[lane] = held[q] > minimum[q] ? (K+1)'(held[q] - minimum[q]) : '0;
        assign lane_alpha[lane] = alpha[q];
        always_comb begin
            header_error[lane] = '0;
            if (route[port] >= 8'(P) || raw_class[port] >= 8'd4)
                header_error[lane] = 3'd1;
            else if (length[port] < 16'd60 || length[port] > 16'(MAX_BYTES))
                header_error[lane] = 3'd2;
            else if (!policy((K+1)'(N_CELL), '0, full_minimum, lane_n[lane],
                             (K+1)'(minimum[q]), (K+1)'(limit[q]), lane_alpha[lane]))
                header_error[lane] = 3'd3;
        end
    end

    if (STAGED) begin : sampled_batch
        logic pending_batch;
        logic [P-1:0] valid;
        // Header inputs may change after sampling. Returned IDs only enter the
        // live pool; the in-flight batch uses the sampled ranks and fit terms.
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                pending_batch <= 1'b0;
                valid <= '0;
            end else begin
                pending_batch <= !pending_batch && (|service_headers);
                if (!pending_batch) valid <= service_headers;
            end
        end
        always_ff @(posedge clk) begin
            if (!pending_batch) begin
                decision_q <= lane_q;
                decision_n <= lane_n;
                decision_bad_beat <= malformed_first;
                decision_error <= header_error;
                decision_id_valid <= ranked_valid;
                decision_id <= ranked_id;
            end
        end
        assign decision_valid = pending_batch ? valid : '0;
    end else begin : direct_batch
        assign decision_q = lane_q;
        assign decision_n = lane_n;
        assign decision_valid = service_headers;
        assign decision_bad_beat = malformed_first;
        assign decision_error = header_error;
        assign decision_id_valid = ranked_valid;
        assign decision_id = ranked_id;
    end

    if (BALANCED) begin : parallel_protection
        // Form all positive deficits before adding so a queue comparison does
        // not put a mux between successive adders. The legal sum fits K bits.
        wire [K:0] protection [2*Q];
        wire [K:0] minima [2*Q];
        for (genvar j = 0; j < Q; j++) begin : leaves
            assign protection[Q+j] = minimum[j] > held[j] ? (K+1)'(minimum[j] - held[j]) : '0;
            assign minima[Q+j] = (K+1)'(minimum[j]);
        end
        for (genvar j = 1; j < Q; j++) begin : branches
            assign protection[j] = protection[2*j] + protection[2*j+1];
            assign minima[j] = minima[2*j] + minima[2*j+1];
        end
        assign protection[0] = '0;
        assign minima[0] = '0;
        assign old_protected = protection[1];
        assign full_minimum = minima[1];
    end else begin : reference_protection
        always_comb begin
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
        end
    end

    always_comb begin : rotate_inputs
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
                if (FACTORED && mask < (1 << lane)) begin : factored_subset
                    localparam int INCLUDED = mask | (1 << lane);
                    fit_terms_t terms, decision_terms;
                    logic [12:0] decision_alpha;

                    always_comb begin
                        logic [K:0] total, spill_total, lane_total, shared_cost;
                        logic last_of_queue;
                        total = '0;
                        spill_total = '0;
                        terms = '0;
                        for (int j = 0; j <= lane; j++) begin
                            if (((INCLUDED >> j) & 1) != 0) begin
                                total += (K+1)'(lane_n[j][COUNT-1:0]);
                                lane_total = '0;
                                last_of_queue = 1'b1;
                                for (int i = 0; i <= lane; i++) begin
                                    if (((INCLUDED >> i) & 1) != 0 && lane_q[i] == lane_q[j]) begin
                                        if (i > j) last_of_queue = 1'b0;
                                        else lane_total += (K+1)'(lane_n[i][COUNT-1:0]);
                                    end
                                end
                                // Count each queue's contribution once, at its
                                // last member in this hypothetical prefix.
                                if (last_of_queue && lane_total > lane_deficit[j])
                                    spill_total += lane_total - lane_deficit[j];
                                if (j == lane) begin
                                    terms.within_minimum = lane_total <= lane_deficit[j];
                                    terms.excess = lane_excess[j] +
                                        (lane_total > lane_deficit[j] ? lane_total - lane_deficit[j] : '0);
                                    terms.within_limit =
                                        (K+1)'(held[lane_q[j]]) + lane_total <= (K+1)'(limit[lane_q[j]]);
                                end
                            end
                        end
                        shared_cost = old_protected + spill_total;
                        terms.enough = total <= (K+1)'(credit);
                        terms.within_shared = shared_cost <= (K+1)'(credit);
                        // The comparison masks underflow in unreachable or
                        // insufficient-share subsets.
                        terms.shared_next = (K+1)'(credit) - shared_cost;
                    end
                    if (STAGED) begin : sample_terms
                        always_ff @(posedge clk) begin
                            if (!sampled_batch.pending_batch) begin
                                decision_terms <= terms;
                                decision_alpha <= lane_alpha[lane];
                            end
                        end
                    end else begin : same_edge_terms
                        assign decision_terms = terms;
                        assign decision_alpha = lane_alpha[lane];
                    end
                    assign look_result[lane][mask] = evaluate_fit(decision_terms, decision_alpha);
                end else if (mask < (1 << lane)) begin : reachable_subset
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
                            if (((mask >> j) & 1) != 0) begin
                                enough = enough && u >= lane_n[j];
                                u -= lane_n[j];
                                old_h = (K+1)'(held[lane_q[j]]);
                                for (int prior = 0; prior < j; prior++)
                                    if ((((mask >> prior) & 1) != 0) && lane_q[prior] == lane_q[j])
                                        old_h += lane_n[prior];
                                used_protection = (K+1)'(minimum[lane_q[j]]) > old_h
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
        logic [P-1:0] accepted_lanes;
        logic serviced, any_descriptor;
        logic [1:0] fit;
        protected_free = old_protected;
        u = (K+1)'(credit);
        earlier = '0;
        accepted_lanes = '0;
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
            q = decision_q[lane];
            qid[p] = q;
            n = decision_n[lane];
            h = (K+1)'(held[q]);
            for (int j = 0; j < P; j++)
                if (grant[j] && qid[j] == q) h += (K+1)'(reserved[j]);
            min_at_q = (K+1)'(minimum[q]);
            if (LOOKAHEAD != 0) begin
                d = decision_id[earlier_count];
                any_descriptor = decision_id_valid[earlier_count];
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
            if (decision_valid[p]) begin
                if (FACTORED && decision_error[lane] != 0) reason[p] = decision_error[lane];
                else if (!FACTORED && (route[p] >= 8'(P) || raw_class[p] >= 8'd4)) reason[p] = 3'd1;
                else if (!FACTORED && (length[p] < 16'd60 || length[p] > 16'(MAX_BYTES))) reason[p] = 3'd2;
                else if (!FACTORED && !policy((K+1)'(N_CELL), '0, full_minimum, n, min_at_q, (K+1)'(limit[q]), alpha[q]))
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
                    accepted_lanes[lane] = 1'b1;
                    malformed[p] = decision_bad_beat[p];
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
        if (BALANCED) begin
            logic [SUM-1:0] granted_cells, released_cells;
            granted_cells = '0;
            released_cells = '0;
            for (int lane = 0; lane < P; lane++)
                granted_cells += accepted_lanes[lane] ? SUM'(decision_n[lane]) : '0;
            for (int lane = 0; lane < LANES; lane++)
                released_cells += credit_release[lane] ? SUM'(release_count[lane]) : '0;
            credit_wide = SUM'(credit) + released_cells - granted_cells;
            for (int j = 0; j < Q; j++) begin
                logic [SUM-1:0] queue_grants, queue_releases;
                queue_grants = '0;
                queue_releases = '0;
                for (int i = 0; i < P; i++)
                    queue_grants += grant[i] && qid[i] == QB'(j) ? SUM'(reserved[i]) : '0;
                for (int i = 0; i < LANES; i++)
                    queue_releases += credit_release[i] && release_qid[i] == QB'(j)
                                       ? SUM'(release_count[i]) : '0;
                held_wide[j] = SUM'(held[j]) + queue_grants - queue_releases;
            end
        end else begin
            if (FACTORED) begin
                credit_wide = SUM'(credit);
                for (int lane = 0; lane < P; lane++)
                    credit_wide -= accepted_lanes[lane] ? SUM'(decision_n[lane]) : '0;
            end else begin
                credit_wide = SUM'(u);
            end
            for (int j = 0; j < Q; j++) begin
                held_wide[j] = SUM'(held[j]);
                for (int i = 0; i < P; i++)
                    if (grant[i] && qid[i] == QB'(j)) held_wide[j] += SUM'(reserved[i]);
            end
            for (int lane = 0; lane < LANES; lane++) begin
                if (credit_release[lane]) begin
                    credit_wide += SUM'(release_count[lane]);
                    held_wide[release_qid[lane]] -= SUM'(release_count[lane]);
                end
            end
        end
        bad_return = 1'b0;
        returned_mask = '0;
        for (int lane = 0; lane < LANES; lane++) begin
            if (desc_return[lane]) begin
                if (free_desc[return_id[lane]] || returned_mask[return_id[lane]])
                    bad_return = 1'b1;
                returned_mask[return_id[lane]] = 1'b1;
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
