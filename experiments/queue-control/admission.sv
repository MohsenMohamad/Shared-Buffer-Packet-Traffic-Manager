module admission #(
    parameter int P = 4, N_CELL = 1024, N_DESC = 256, MAX_BYTES = 1536,
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

    always_comb begin : prefix
        logic [K:0] u, protected_free, total_min, h, min_at_q, n, consumed;
        logic [QB-1:0] q;
        logic [B-1:0] p;
        logic [D-1:0] d;
        logic [N_DESC-1:0] remaining;
        logic serviced;
        logic [SUM-1:0] min_sum, protected_sum;
        min_sum = '0;
        protected_sum = '0;
        for (int j = 0; j < Q; j++) begin
            min_sum += SUM'(minimum[j]);
            if (minimum[j] > held[j])
                protected_sum += SUM'(minimum[j]) - SUM'(held[j]);
        end
        protected_free = (K+1)'(protected_sum);
        total_min = (K+1)'(min_sum);
        u = (K+1)'(credit);
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
            q = {route[p][B-1:0], raw_class[p][1:0]};
            qid[p] = q;
            n = (K+1)'(({1'b0, length[p]} + 17'd63) >> 6);
            h = (K+1)'(held[q]);
            for (int j = 0; j < P; j++)
                if (grant[j] && qid[j] == q) h += (K+1)'(reserved[j]);
            min_at_q = (K+1)'(minimum[q]);
            d = first_free(remaining);
            if (header_valid[p]) begin
                if (route[p] >= 8'(P) || raw_class[p] >= 8'd4) reason[p] = 3'd1;
                else if (length[p] < 16'd60 || length[p] > 16'(MAX_BYTES)) reason[p] = 3'd2;
                else if (!policy((K+1)'(N_CELL), '0, total_min, n, min_at_q, (K+1)'(limit[q]), alpha[q]))
                    reason[p] = 3'd3;
                else if (remaining == '0) begin
                    reason[p] = 3'd4;
                    pending[p] = wait_mode;
                end else if (n > u) begin
                    reason[p] = 3'd5;
                    pending[p] = wait_mode;
                end else if (!policy(u, h, protected_free, n, min_at_q, (K+1)'(limit[q]), alpha[q])) begin
                    reason[p] = 3'd3;
                    pending[p] = wait_mode;
                end else begin
                    grant[p] = 1'b1;
                    malformed[p] = bad_first_beat[p];
                    selected[p] = d;
                    reserved[p] = K'(n);
                    remaining[d] = 1'b0;
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
