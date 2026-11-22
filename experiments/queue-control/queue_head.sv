module queue_head #(
    parameter int P = 4, N_DESC = 256, N_CELL = 1024, CACHED = 0, TOKEN_FEEDBACK = 0,
    localparam int Q = P * 4, QB = $clog2(Q), D = $clog2(N_DESC),
    localparam int C = $clog2(N_CELL), B = $clog2(P),
    // First cell, cell count, ingress, sequence, tag, ECN and mark.
    localparam int META = C + 5 + B + 64 + 16 + 2 + 1,
    localparam int W = META + 16
) (
    input logic clk, rst_n,
    input logic publish,
    input logic [QB-1:0] publish_q,
    input logic [D-1:0] publish_desc,
    input logic [W-1:0] publish_info,
    // Sourced by the active/next frame slots and pre-edge token buckets.
    input logic [P-1:0] bind_window,
    input logic [Q-1:0][15:0] queue_credit_bytes,
    input logic [P-1:0][15:0] port_credit_bytes,
    input logic token_start,
    input logic [19:0] token_rate,
    output logic [Q-1:0] active,
    output logic [P-1:0] bound,
    output logic [P-1:0][1:0] bound_class,
    output logic [P-1:0][D-1:0] bound_desc,
    output logic [P-1:0][W-1:0] bound_info,
    output logic invariant_error
`ifdef QUEUE_CONTROL_CONNECTED
    , input logic [Q-1:0] queue_bucket_enable
    , input logic [P-1:0] port_bucket_enable
    , input logic [Q-1:0][19:0] queue_rate
    , input logic [P-1:0][19:0] port_rate
    , input logic [Q-1:0][12:0] quantum
    , input logic [P-1:0][1:0] scheduler_mode, strict_class
    , output logic [P-1:0] bind_now
    , output logic [P-1:0][1:0] class_now
    , output logic [P-1:0][D-1:0] desc_now
    , output logic [P-1:0][W-1:0] info_now
`endif
);
    logic [Q-1:0][D-1:0] head, tail;
    logic [P-1:0][1:0] cursor;
    logic [W-1:0] metadata [N_DESC];
    logic [D-1:0] next_link [N_DESC];
    logic [W-1:0] cached [Q];
    logic [P-1:0] pop, pop_last;
    logic [P-1:0][1:0] cls;
    logic [P-1:0][D-1:0] old_head, successor;
    logic [P-1:0][W-1:0] selected_info;
    logic [Q-1:0][15:0] queue_available;
    logic [P-1:0][15:0] port_available;

`ifdef QUEUE_CONTROL_CONNECTED
    logic [Q-1:0] open_visit;
    logic [Q-1:0][12:0] deficit;
    logic [P-1:0] drr_attempt, fits_deficit;
    logic [P-1:0][12:0] available_deficit;
    assign bind_now = pop;
    assign class_now = cls;
    assign desc_now = old_head;
    assign info_now = selected_info;
`endif

    // The composed point treats the byte inputs as configured capacities.
    // Every bucket is enabled and shares the supplied Q16.16 refill rate.
    function automatic logic [31:0] update_tokens(
        input logic [31:0] old_balance,
        input logic [15:0] capacity_bytes, charged_bytes,
        input logic [19:0] refill_rate
    );
        logic [32:0] balance, capacity;
        capacity = {1'b0, capacity_bytes, 16'b0};
        balance = {1'b0, old_balance} - {1'b0, charged_bytes, 16'b0} + 33'(refill_rate);
        return token_start || balance >= capacity ? capacity[31:0] : balance[31:0];
    endfunction

    if (TOKEN_FEEDBACK == 0) begin : external_tokens
        assign queue_available = queue_credit_bytes;
        assign port_available = port_credit_bytes;
    end else begin : registered_tokens
        for (genvar e = 0; e < P; e++) begin : port_state
            logic [31:0] balance;
            assign port_available[e] = balance[31:16];
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    balance <= '0;
                else
`ifdef QUEUE_CONTROL_CONNECTED
                    balance <= update_tokens(balance, port_credit_bytes[e],
                         pop[e] && port_bucket_enable[e] ? selected_info[e][15:0] : 16'b0, port_rate[e]);
`else
                    balance <= update_tokens(balance, port_credit_bytes[e],
                                             pop[e] ? selected_info[e][15:0] : 16'b0, token_rate);
`endif
            end
        end
        for (genvar q = 0; q < Q; q++) begin : queue_state
            localparam int E = q / 4;
            logic [31:0] balance;
            wire debit = pop[E] && cls[E] == 2'(q % 4);
            assign queue_available[q] = balance[31:16];
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    balance <= '0;
                else
`ifdef QUEUE_CONTROL_CONNECTED
                    balance <= update_tokens(balance, queue_credit_bytes[q],
                         debit && queue_bucket_enable[q] ? selected_info[E][15:0] : 16'b0, queue_rate[q]);
`else
                    balance <= update_tokens(balance, queue_credit_bytes[q],
                                             debit ? selected_info[E][15:0] : 16'b0, token_rate);
`endif
            end
        end
    end

    for (genvar e = 0; e < P; e++) begin : choose
        logic [3:0] eligible;
        for (genvar c = 0; c < 4; c++) begin : class_head
            localparam int QID = e * 4 + c;
            wire [15:0] length = CACHED != 0 ? cached[QID][15:0] : metadata[head[QID]][15:0];
`ifdef QUEUE_CONTROL_CONNECTED
            assign eligible[c] = active[QID] && !token_start
                                && (!queue_bucket_enable[QID] || length <= queue_available[QID])
                                && (!port_bucket_enable[e] || length <= port_available[e]);
`else
            assign eligible[c] = active[QID] && length <= queue_available[QID]
                                && length <= port_available[e] && !(TOKEN_FEEDBACK != 0 && token_start);
`endif
        end
        wire [3:0] rotated = (eligible >> cursor[e]) | (eligible << (4 - cursor[e]));
        wire [1:0] offset = rotated[0] ? 2'd0 : rotated[1] ? 2'd1 : rotated[2] ? 2'd2 : 2'd3;
        wire [QB-1:0] qid = {B'(e), cls[e]};
`ifdef QUEUE_CONTROL_CONNECTED
        wire strict_wins = scheduler_mode[e] == 2'd2 && eligible[strict_class[e]];
        wire rr_mode = scheduler_mode[e] == 2'd1;
        wire still_queued = !pop_last[e] || (publish && publish_q == qid);
        assign cls[e] = strict_wins ? strict_class[e] : cursor[e] + offset;
        assign drr_attempt[e] = bind_window[e] && (|eligible) && !strict_wins && !rr_mode;
        assign available_deficit[e] = deficit[qid] + (open_visit[qid] ? 13'b0 : quantum[qid]);
        assign fits_deficit[e] = 16'(available_deficit[e]) >= selected_info[e][15:0];
        assign pop[e] = bind_window[e] && (|eligible) && (strict_wins || rr_mode || fits_deficit[e]);
`else
        assign cls[e] = cursor[e] + offset;
        assign pop[e] = bind_window[e] && (|eligible);
`endif
        assign old_head[e] = head[qid];
        assign successor[e] = next_link[old_head[e]];
        assign pop_last[e] = old_head[e] == tail[qid];
        // Only the winning head consumes the non-length fields in direct mode.
        assign selected_info[e] = CACHED != 0 ? cached[qid] : metadata[old_head[e]];

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                cursor[e] <= '0;
                bound[e] <= 1'b0;
                bound_class[e] <= '0;
                bound_desc[e] <= '0;
                bound_info[e] <= '0;
            end else begin
                bound[e] <= pop[e];
`ifdef QUEUE_CONTROL_CONNECTED
                if (drr_attempt[e])
                    cursor[e] <= fits_deficit[e] && still_queued ? cls[e] : cls[e] + 2'd1;
                else if (pop[e] && rr_mode)
                    cursor[e] <= cls[e] + 2'd1;
                else if (bind_window[e] && !token_start && !(|eligible) && !rr_mode &&
                         open_visit[{B'(e), cursor[e]}])
                    cursor[e] <= cursor[e] + 2'd1;
`endif
                if (pop[e]) begin
`ifndef QUEUE_CONTROL_CONNECTED
                    cursor[e] <= cls[e] + 2'd1;
`endif
                    bound_class[e] <= cls[e];
                    bound_desc[e] <= old_head[e];
                    bound_info[e] <= selected_info[e];
                end
            end
        end
    end

    wire [B-1:0] pub_egress = publish_q[QB-1:2];
    wire replaces_last = pop[pub_egress] && pop_last[pub_egress]
                        && cls[pub_egress] == publish_q[1:0];
    always_ff @(posedge clk) begin
        if (publish) begin
            metadata[publish_desc] <= publish_info;
            if (active[publish_q] && !replaces_last)
                next_link[tail[publish_q]] <= publish_desc;
        end
    end

    for (genvar q = 0; q < Q; q++) begin : queue_state
        localparam int E = q / 4;
        wire append = publish && publish_q == QB'(q);
        wire remove = pop[E] && cls[E] == 2'(q % 4);
        wire takes_publication = append && (!active[q] || (remove && pop_last[E]));
        wire follows_successor = remove && !pop_last[E];

`ifdef QUEUE_CONTROL_CONNECTED
        wire drained = remove && pop_last[E] && !append;
        wire attempted = drr_attempt[E] && cls[E] == 2'(q % 4);
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                open_visit[q] <= 1'b0;
                deficit[q] <= '0;
            end else if (drained) begin
                open_visit[q] <= 1'b0;
                deficit[q] <= '0;
            end else if (attempted) begin
                open_visit[q] <= fits_deficit[E];
                deficit[q] <= available_deficit[E] -
                              (fits_deficit[E] ? 13'(selected_info[E][15:0]) : 13'b0);
            end
        end
`endif

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                active[q] <= 1'b0;
                head[q] <= '0;
                tail[q] <= '0;
            end else begin
                active[q] <= append || (active[q] && !(remove && pop_last[E]));
                if (append)
                    tail[q] <= publish_desc;
                if (takes_publication)
                    head[q] <= publish_desc;
                else if (follows_successor)
                    head[q] <= successor[E];
            end
        end

        if (CACHED != 0) begin : refill
            always_ff @(posedge clk) begin
                if (takes_publication)
                    cached[q] <= publish_info;
                else if (follows_successor)
                    cached[q] <= metadata[successor[E]];
            end
        end
    end

    // Flag overlap with the live head or tail. The allocator supplies fresh IDs.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            invariant_error <= 1'b0;
        else if (publish && active[publish_q] &&
                (publish_desc == head[publish_q] || publish_desc == tail[publish_q]))
            invariant_error <= 1'b1;
    end
endmodule
