// Control timing fixture. Inputs represent old capture heads, staged cells and
// the fixed-latency payload interface. There is no payload byte array.
module connected_control #(
    parameter int P = 4, N_CELL = 1024, N_DESC = 256, MAX_BYTES = 1536,
    localparam int Q = 4 * P, B = $clog2(P), QB = $clog2(Q),
    localparam int C = $clog2(N_CELL), D = $clog2(N_DESC), K = $clog2(N_CELL+1),
    localparam int W = C + 5 + B + 64 + 16 + 2 + 1 + 16
) (
    input logic clk, rst_n, run_enable, token_start, dynamic_mode, wait_mode,
    input logic [63:0] epoch,
    input logic [P-1:0] header_valid, first_last, staged_cell, abort_late, sink_ready,
    input logic [P-1:0][7:0] first_keep, route, raw_class,
    input logic [P-1:0][15:0] length, header_tag,
    input logic [P-1:0][63:0] header_sequence,
    input logic [P-1:0][1:0] header_ecn,
    input logic [Q-1:0][K-1:0] minimum, limit, ecn_threshold,
    input logic [Q-1:0] ecn_enable, queue_bucket_enable,
    input logic [Q-1:0][12:0] alpha, quantum,
    input logic [Q-1:0][15:0] queue_capacity,
    input logic [Q-1:0][19:0] queue_rate,
    input logic [P-1:0] port_bucket_enable,
    input logic [P-1:0][15:0] port_capacity,
    input logic [P-1:0][19:0] port_rate,
    input logic [P-1:0][1:0] scheduler_mode, strict_class,
    input logic response_valid,
    input logic [63:0] response_epoch,
    input logic [B-1:0] response_port,
    input logic [2:0] response_slot,
    input logic [C-1:0] response_address,
    input logic [D-1:0] response_desc,
    output logic [P-1:0] rx_grant, rx_reject, rx_wait, rx_abort,
    output logic [P-1:0][2:0] rx_reason,
    output logic [P-1:0][D-1:0] rx_desc,
    output logic [K-1:0] credit,
    output logic [Q-1:0][K-1:0] held,
    output logic [Q-1:0] active,
    output logic write_event, publish_event, issue_event, response_accepted, cleanup_event,
    output logic [D-1:0] published_desc, issue_desc,
    output logic [B-1:0] issue_port,
    output logic [2:0] issue_slot,
    output logic [C-1:0] write_address, issue_address,
    output logic [P-1:0] bound, tx_valid, tx_last,
    output logic [P-1:0][1:0] bound_class,
    output logic [P-1:0][D-1:0] bound_desc,
    output logic [P-1:0][W-1:0] bound_info,
    output logic [P-1:0][2:0] occupied,
    output logic [P:0] cell_returns, desc_returns,
    output logic [P:0][C-1:0] returned_cell,
    output logic [P:0][D-1:0] returned_desc,
    output logic invariant_error
);
    wire enabled = run_enable && rst_n;
    logic [P-1:0] grant, bad_first, rx_owned, rx_cleaning;
    logic [P-1:0][D-1:0] grant_desc, rx_owner;
    logic [P-1:0][QB-1:0] grant_qid, rx_queue;
    logic [P-1:0][K-1:0] grant_count, rx_reservation;
    logic [P-1:0][15:0] rx_length, rx_tag;
    logic [P-1:0][63:0] rx_sequence;
    logic [P-1:0][1:0] rx_ecn;
    logic [P-1:0][4:0] written_count;
    logic [P-1:0][C-1:0] first_cell, tail_cell;
    logic [P-1:0] write_candidate, write_final, append_link, abort_mark;
    logic [P-1:0][4:0] abort_count;
    logic [P-1:0][C-1:0] abort_first;
    logic [P-1:0][D-1:0] abort_owner;

    logic [P-1:0] bind_window, bind_now;
    logic [P-1:0][1:0] class_now;
    logic [P-1:0][D-1:0] desc_now;
    logic [P-1:0][W-1:0] info_now;
    logic [QB-1:0] publish_queue;
    logic [W-1:0] unpublished_info, published_info;
    logic [1:0] published_ecn;
    logic write_now, read_now, cleanup_now, cleanup_done, cleanup_cell;
    logic [B-1:0] write_lane, cleanup_lane, read_lane;
    logic [C-1:0] allocation, read_link, cleanup_address;
    logic [D-1:0] cleanup_owner;

    logic [P-1:0] read_eligible, read_more, tx_retire, tx_finish;
    logic [P-1:0][C-1:0] read_cell;
    logic [P-1:0][D-1:0] read_desc;
    logic [P:0][QB-1:0] release_qid;
    logic [P:0][K-1:0] release_count;
    logic admission_error, queue_error, pool_error;

    admission #(.P(P), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_BYTES(MAX_BYTES),
                .LOOKAHEAD(4), .RX_FRAMING(1)) admission_logic (
        .clk, .rst_n, .dynamic_mode, .wait_mode, .header_valid, .bad_first_beat('0),
        .first_keep, .first_last, .receive_space({P{enabled}} & ~rx_owned), .route, .raw_class,
        .length, .minimum, .limit, .alpha, .desc_return(desc_returns), .credit_release(desc_returns | cell_returns),
        .return_id(returned_desc), .release_qid, .release_count,
        .rx_grant, .rx_reject, .rx_wait, .rx_abort, .rx_reason, .rx_desc,
        .rx_qid(), .rx_reserved(), .credit, .held, .invariant_error(admission_error),
        .service_grant(grant), .service_abort(bad_first), .service_desc(grant_desc),
        .service_qid(grant_qid), .service_count(grant_count)
    );

    cell_control #(.P(P), .N_CELL(N_CELL), .N_DESC(N_DESC), .ABORT_FEEDBACK(1)) pool (
        .clk, .rst_n, .staged_valid(write_candidate), .staged_final(write_final),
        .previous_valid(append_link), .previous_cell(tail_cell), .staged_desc(rx_owner),
        .read_eligible, .read_more, .read_cell, .read_desc,
        .abort_valid(abort_mark), .abort_has_cell('0), .abort_more('0),
        .abort_cells(abort_count), .abort_cell(abort_first), .abort_desc(abort_owner),
        .tx_return(tx_retire), .tx_return_cell(returned_cell[P-1:0]),
        .tx_return_desc(returned_desc[P-1:0]), .write_valid(), .final_write(),
        .issue_valid(), .cleanup_valid(), .cleanup_done(), .write_port(),
        .issue_port(), .cleanup_port(), .write_addr(), .payload_read_addr(),
        .tx_successor(), .abort_successor(), .write_owner(), .invariant_error(pool_error),
        .write_now, .read_now, .cleanup_now, .cleanup_final_now(cleanup_done),
        .write_lane, .read_lane, .cleanup_lane, .allocation, .read_link_now(read_link),
        .cleanup_addr_now(cleanup_address), .cleanup_owner_now(cleanup_owner), .cleanup_cell_now(cleanup_cell)
    );

    assign published_ecn = unpublished_info[18:17];
    always_comb begin
        published_info = unpublished_info;
        published_info[16] = ecn_enable[publish_queue] &&
                             (published_ecn == 2'd1 || published_ecn == 2'd2) &&
                             held[publish_queue] >= ecn_threshold[publish_queue];
    end

    queue_head #(.P(P), .N_DESC(N_DESC), .N_CELL(N_CELL), .CACHED(1), .TOKEN_FEEDBACK(1)) heads (
        .clk, .rst_n, .publish(publish_event), .publish_q(publish_queue),
        .publish_desc(published_desc), .publish_info(published_info), .bind_window,
        .queue_credit_bytes(queue_capacity), .port_credit_bytes(port_capacity), .token_start, .token_rate('0),
        .active, .bound, .bound_class, .bound_desc, .bound_info, .invariant_error(queue_error),
        .queue_bucket_enable, .port_bucket_enable, .queue_rate, .port_rate,
        .quantum, .scheduler_mode, .strict_class, .bind_now, .class_now, .desc_now, .info_now
    );

    for (genvar p = 0; p < P; p++) begin : receive
        wire writes_here = write_now && write_lane == B'(p);
        wire late_mark = enabled && rx_owned[p] && !rx_cleaning[p] && abort_late[p];
        wire cleanup_here = cleanup_done && cleanup_lane == B'(p);
        assign write_candidate[p] = enabled && rx_owned[p] && !rx_cleaning[p] && staged_cell[p];
        assign append_link[p] = written_count[p] != 0;
        assign write_final[p] = K'(written_count[p]) + K'(1) == rx_reservation[p];
        assign abort_mark[p] = (grant[p] && bad_first[p]) || late_mark;
        assign abort_count[p] = late_mark ? written_count[p] + 5'(writes_here) : 5'b0;
        assign abort_first[p] = append_link[p] ? first_cell[p] : allocation;
        assign abort_owner[p] = late_mark ? rx_owner[p] : grant_desc[p];

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                rx_owned[p] <= 1'b0;
                rx_cleaning[p] <= 1'b0;
                rx_owner[p] <= '0;
                rx_queue[p] <= '0;
                rx_reservation[p] <= '0;
                rx_length[p] <= '0;
                rx_tag[p] <= '0;
                rx_sequence[p] <= '0;
                rx_ecn[p] <= '0;
                written_count[p] <= '0;
                first_cell[p] <= '0;
                tail_cell[p] <= '0;
            end else begin
                if (grant[p]) begin
                    rx_owned[p] <= 1'b1;
                    rx_cleaning[p] <= bad_first[p];
                    rx_owner[p] <= grant_desc[p];
                    rx_queue[p] <= grant_qid[p];
                    rx_reservation[p] <= grant_count[p];
                    rx_length[p] <= length[p];
                    rx_tag[p] <= header_tag[p];
                    rx_sequence[p] <= header_sequence[p];
                    rx_ecn[p] <= header_ecn[p];
                    written_count[p] <= '0;
                end
                if (writes_here) begin
                    if (!append_link[p]) first_cell[p] <= allocation;
                    tail_cell[p] <= allocation;
                    written_count[p] <= written_count[p] + 5'd1;
                    if (write_final[p] && !late_mark) rx_owned[p] <= 1'b0;
                end
                if (late_mark) rx_cleaning[p] <= 1'b1;
                if (cleanup_here) begin
                    rx_owned[p] <= 1'b0;
                    rx_cleaning[p] <= 1'b0;
                end
            end
        end
    end

    wire final_written = write_now && write_final[write_lane] && !abort_mark[write_lane];
    logic publication_pending;
    assign publish_event = enabled && publication_pending;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            publication_pending <= 1'b0;
            publish_queue <= '0;
            published_desc <= '0;
            unpublished_info <= '0;
        end else begin
            publication_pending <= final_written;
            if (final_written) begin
                publish_queue <= rx_queue[write_lane];
                published_desc <= rx_owner[write_lane];
                unpublished_info <= {append_link[write_lane] ? first_cell[write_lane] : allocation,
                    5'(rx_reservation[write_lane]), write_lane, rx_sequence[write_lane],
                    rx_tag[write_lane], rx_ecn[write_lane], 1'b0, rx_length[write_lane]};
            end
        end
    end

    // Each issue reserves a ring entry. Response visibility and retirement
    // change that entry's state only on a clock edge.
    logic [P-1:0][2:0] push_index, pop_index;
    logic [P-1:0][5:0] pending, ready;
    logic [P-1:0][5:0][C-1:0] slot_address;
    logic [P-1:0][5:0][D-1:0] slot_owner;
    logic [P-1:0][1:0] frame_live;
    logic [P-1:0] front_slot;
    logic [P-1:0][1:0][D-1:0] frame_desc;
    logic [P-1:0][1:0][QB-1:0] frame_queue;
    logic [P-1:0][1:0][4:0] unread;
    logic [P-1:0][1:0][C-1:0] next_read;
    logic [P-1:0][1:0][7:0] beats_left;
    logic [P-1:0][2:0] beat_in_cell;

    function automatic logic [2:0] ring_next(input logic [2:0] index);
        return index == 3'd5 ? 3'd0 : index + 3'd1;
    endfunction

    assign write_event = write_now;
    assign write_address = allocation;
    assign cleanup_event = enabled && cleanup_now;
    assign cell_returns = {enabled && cleanup_cell, tx_retire};
    assign desc_returns = {enabled && cleanup_done, tx_finish};
    assign returned_cell[P] = cleanup_address;
    assign returned_desc[P] = cleanup_owner;
    assign release_qid[P] = rx_queue[cleanup_lane];
    assign release_count[P] = cleanup_done ? rx_reservation[cleanup_lane] : K'(0);

    assign issue_event = read_now;
    assign issue_port = read_lane;
    assign issue_slot = push_index[read_lane];
    assign issue_address = read_cell[read_lane];
    assign issue_desc = read_desc[read_lane];
    assign response_accepted = enabled && response_valid && response_epoch == epoch &&
        response_slot < 3'd6 && pending[response_port][response_slot] &&
        response_address == slot_address[response_port][response_slot] &&
        response_desc == slot_owner[response_port][response_slot];
    assign invariant_error = admission_error || queue_error || pool_error;

    for (genvar e = 0; e < P; e++) begin : transmit
        wire front = front_slot[e];
        wire front_live = frame_live[e][front];
        wire tail_live = frame_live[e][!front];
        wire bind_slot = front_live ? !front : front;
        wire select_slot = front_live && unread[e][front] != 0 ? front : !front;
        wire [2:0] push_at = push_index[e], pop_at = pop_index[e];
        wire issues_here = read_now && read_lane == B'(e);
        wire receives_here = response_accepted && response_port == B'(e);
        wire accepts_beat = tx_valid[e] && sink_ready[e];
        wire [15:0] byte_length = info_now[e][15:0];
        wire [16:0] rounded_beats = (17'(byte_length) + 17'd7) >> 3;

        assign bind_window[e] = enabled && (!front_live || (!tail_live && beats_left[e][front] <= 8'd16));
        assign read_eligible[e] = enabled && occupied[e] < 3'd6 &&
                                  frame_live[e][select_slot] && unread[e][select_slot] != 0;
        assign read_more[e] = unread[e][select_slot] > 5'd1;
        assign read_cell[e] = next_read[e][select_slot];
        assign read_desc[e] = frame_desc[e][select_slot];
        assign tx_valid[e] = enabled && front_live && ready[e][pop_at] && slot_owner[e][pop_at] == frame_desc[e][front];
        assign tx_last[e] = tx_valid[e] && beats_left[e][front] == 8'd1;
        assign tx_finish[e] = accepts_beat && tx_last[e];
        assign tx_retire[e] = accepts_beat && (tx_last[e] || beat_in_cell[e] == 3'd7);
        assign returned_cell[e] = slot_address[e][pop_at];
        assign returned_desc[e] = frame_desc[e][front];
        assign release_qid[e] = frame_queue[e][front];
        assign release_count[e] = K'(tx_retire[e]);

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                push_index[e] <= '0;
                pop_index[e] <= '0;
                occupied[e] <= '0;
                pending[e] <= '0;
                ready[e] <= '0;
                slot_address[e] <= '0;
                slot_owner[e] <= '0;
                frame_live[e] <= '0;
                front_slot[e] <= '0;
                frame_desc[e] <= '0;
                frame_queue[e] <= '0;
                unread[e] <= '0;
                next_read[e] <= '0;
                beats_left[e] <= '0;
                beat_in_cell[e] <= '0;
            end else begin
                occupied[e] <= occupied[e] + 3'(issues_here) - 3'(tx_retire[e]);
                if (issues_here) begin
                    push_index[e] <= ring_next(push_at);
                    pending[e][push_at] <= 1'b1;
                    slot_address[e][push_at] <= read_cell[e];
                    slot_owner[e][push_at] <= read_desc[e];
                    unread[e][select_slot] <= unread[e][select_slot] - 5'd1;
                    if (read_more[e]) next_read[e][select_slot] <= read_link;
                end
                if (receives_here) begin
                    pending[e][response_slot] <= 1'b0;
                    ready[e][response_slot] <= 1'b1;
                end
                if (accepts_beat) begin
                    beats_left[e][front] <= beats_left[e][front] - 8'd1;
                    beat_in_cell[e] <= tx_retire[e] ? 3'd0 : beat_in_cell[e] + 3'd1;
                end
                if (tx_retire[e]) begin
                    ready[e][pop_at] <= 1'b0;
                    pop_index[e] <= ring_next(pop_at);
                end
                if (tx_finish[e]) begin
                    frame_live[e][front] <= 1'b0;
                    if (tail_live || bind_now[e]) front_slot[e] <= !front;
                end
                if (bind_now[e]) begin
                    frame_live[e][bind_slot] <= 1'b1;
                    frame_desc[e][bind_slot] <= desc_now[e];
                    frame_queue[e][bind_slot] <= {B'(e), class_now[e]};
                    unread[e][bind_slot] <= info_now[e][W-C-1 -: 5];
                    next_read[e][bind_slot] <= info_now[e][W-1 -: C];
                    beats_left[e][bind_slot] <= 8'(rounded_beats);
                end
            end
        end
    end
endmodule
