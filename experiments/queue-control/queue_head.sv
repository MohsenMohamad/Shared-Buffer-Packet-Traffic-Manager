module queue_head #(
    parameter int P = 4, N_DESC = 256, N_CELL = 1024, CACHED = 0,
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
    output logic [Q-1:0] active,
    output logic [P-1:0] bound,
    output logic [P-1:0][1:0] bound_class,
    output logic [P-1:0][D-1:0] bound_desc,
    output logic [P-1:0][W-1:0] bound_info,
    output logic invariant_error
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

    for (genvar e = 0; e < P; e++) begin : choose
        logic [3:0] eligible;
        for (genvar c = 0; c < 4; c++) begin : class_head
            localparam int QID = e * 4 + c;
            wire [15:0] length = CACHED != 0 ? cached[QID][15:0] : metadata[head[QID]][15:0];
            assign eligible[c] = active[QID] && length <= queue_credit_bytes[QID]
                                && length <= port_credit_bytes[e];
        end
        wire [3:0] rotated = (eligible >> cursor[e]) | (eligible << (4 - cursor[e]));
        wire [1:0] offset = rotated[0] ? 2'd0 : rotated[1] ? 2'd1 : rotated[2] ? 2'd2 : 2'd3;
        wire [QB-1:0] qid = {B'(e), cls[e]};
        assign cls[e] = cursor[e] + offset;
        assign pop[e] = bind_window[e] && (|eligible);
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
                if (pop[e]) begin
                    cursor[e] <= cls[e] + 2'd1;
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
