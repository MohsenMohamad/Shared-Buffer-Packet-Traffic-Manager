module tm_statistics_api #(
`include "tm_parameters.svh"
, parameter integer COUNTER_W=64
) (clk, rst_n, events, input_stalled, output_stalled, output_fire, output_beat, run, live, command, live_stats, shadow_stats);
`include "tm_types.svh"
input logic clk, rst_n;
input trace_t events;
input logic [N_RX-1:0] input_stalled;
input logic output_stalled, output_fire, run;
input beat_t output_beat;
input live_t live;
input stats_command_t command;
output statistics_t live_stats, shadow_stats;
`include "tm_validate.svh"
generate if (COUNTER_W<1 || COUNTER_W>64) begin : g_invalid_counter
    TM_INVALID_CONFIGURATION invalid_counter_width();
end endgenerate
logic [COUNTER_W-1:0] globals [0:9];
logic [COUNTER_W-1:0] queues [0:N_Q*5-1];
logic [N_Q*CELL_COUNT_W-1:0] high_water;
integer global_delta [0:9];
integer queue_delta [0:N_Q*5-1];
integer h_after [0:N_Q-1];
integer bytes_sent;

always_comb begin
    bytes_sent = 0;
    for (integer lane=0; lane<DATA_W/8; lane=lane+1)
        if (output_beat.keep[lane]) bytes_sent = bytes_sent+1;
    for (integer k=0; k<10; k=k+1) global_delta[k] = 0;
    for (integer k=0; k<N_Q*5; k=k+1) queue_delta[k] = 0;
    global_delta[0] = int'(events.rx_service.valid && events.rx_service.sop);
    global_delta[1] = int'(events.admit.valid && events.admit.accept);
    global_delta[2] = int'(events.commit.valid);
    global_delta[3] = int'(events.admit.valid && !events.admit.accept &&
        (events.admit.reason == QUEUE_LIMIT || events.admit.reason == NO_DESCRIPTOR || events.admit.reason == NO_CELLS));
    // A bad header and a different packet's first abort can share an edge.
    global_delta[4] = int'(events.admit.valid && !events.admit.accept &&
        (events.admit.reason == BAD_QID || events.admit.reason == BAD_LENGTH)) + int'(events.abort_mark.valid);
    global_delta[5] = int'(events.tx_done.valid);
    global_delta[6] = output_fire ? bytes_sent : 0;
    global_delta[7] = int'(run);
    global_delta[8] = int'(|input_stalled);
    global_delta[9] = int'(output_stalled);
    for (integer q=0; q<N_Q; q=q+1) begin
        // Comparisons, rather than truncated qid indexing, preserve BAD_QID.
        queue_delta[q*5] = int'(events.admit.valid && events.admit.accept && events.admit.qid == 8'(q));
        queue_delta[q*5+1] = (events.admit.qid == 8'(q)) ? global_delta[3] : 0;
        queue_delta[q*5+2] = int'(events.tx_done.valid && events.tx_done.qid == Q_ID_W'(q));
        queue_delta[q*5+3] = (output_fire && output_beat.user[7:0] == 8'(q)) ? bytes_sent : 0;
        queue_delta[q*5+4] = int'(events.abort_mark.valid && events.abort_mark.qid == Q_ID_W'(q));
        h_after[q] = int'(live.owned[q*CELL_COUNT_W +: CELL_COUNT_W]);
        if (events.admit.valid && events.admit.accept && events.admit.qid == 8'(q))
            h_after[q] = h_after[q] + int'(events.admit.ncell);
        if (events.cell_free.valid && !events.cell_free.abort_source && events.cell_free.qid == Q_ID_W'(q))
            h_after[q] = h_after[q] - 1;
        if (events.abort_done.valid && events.abort_done.qid == Q_ID_W'(q))
            h_after[q] = h_after[q] - int'(events.abort_done.ncell);
    end
    live_stats = '0;
    for (integer k=0; k<10; k=k+1) live_stats.global_counts[k*64 +: 64] = 64'(globals[k]);
    for (integer k=0; k<N_Q*5; k=k+1) live_stats.queue_counts[k*64 +: 64] = 64'(queues[k]);
    live_stats.high_water = high_water;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (integer k=0; k<10; k=k+1) globals[k] <= '0;
        for (integer k=0; k<N_Q*5; k=k+1) queues[k] <= '0;
        high_water <= '0;
        shadow_stats <= '0;
    end else if (command.clear && !run && live.idle) begin
        for (integer k=0; k<10; k=k+1) globals[k] <= '0;
        for (integer k=0; k<N_Q*5; k=k+1) queues[k] <= '0;
        high_water <= '0;
        shadow_stats <= '0;
    end else begin
        if (command.snapshot) shadow_stats <= live_stats;
        for (integer k=0; k<10; k=k+1) globals[k] <= globals[k] + COUNTER_W'(global_delta[k]);
        for (integer k=0; k<N_Q*5; k=k+1) queues[k] <= queues[k] + COUNTER_W'(queue_delta[k]);
        for (integer q=0; q<N_Q; q=q+1)
            if (h_after[q] >= 0 && h_after[q] <= N_CELL && h_after[q] > int'(high_water[q*CELL_COUNT_W +: CELL_COUNT_W]))
                high_water[q*CELL_COUNT_W +: CELL_COUNT_W] <= CELL_COUNT_W'(h_after[q]);
    end
end
endmodule
