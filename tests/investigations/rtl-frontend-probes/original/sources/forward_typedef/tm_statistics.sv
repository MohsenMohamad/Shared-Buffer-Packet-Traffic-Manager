module tm_statistics_api #(
`include "tm_parameters.svh"
, parameter integer COUNTER_W=64

, localparam integer RX_ID_W=(N_RX>1 ? $clog2(N_RX) : 1),
localparam integer Q_ID_W=(N_Q>1 ? $clog2(N_Q) : 1),
localparam integer WORD_OFF_W=(CELL_BYTES/8>1 ? $clog2(CELL_BYTES/8) : 1),
localparam integer ADDR_W=(N_CELL*CELL_BYTES/8>1 ? $clog2(N_CELL*CELL_BYTES/8) : 1),
localparam integer BEAT_W=DATA_W+DATA_W/8+65,
localparam integer STATUS_W=45,
localparam integer DESC_INFO_W=CELL_ID_W+CELL_COUNT_W+16+Q_ID_W+16+RX_ID_W
) (
    input logic clk,
    input logic rst_n,
    input trace_t events,
    input logic [N_RX-1:0] input_stalled,
    input logic output_stalled,
    input logic output_fire,
    input beat_t output_beat,
    input logic run,
    input live_t live,
    input stats_command_t command,
    output statistics_t live_stats,
    output statistics_t shadow_stats
);
// Module-local packed types: portable through Verilator and Yosys read_verilog -sv.
// Include after tm_parameters.svh, before non-ANSI port declarations.
typedef logic [CELL_ID_W-1:0] cell_id_t;
typedef logic [DESC_ID_W-1:0] desc_id_t;
typedef logic [CELL_COUNT_W-1:0] cell_count_t;
typedef logic [DESC_COUNT_W-1:0] desc_count_t;
typedef logic [DEFICIT_W-1:0] deficit_t;
typedef logic [Q_ID_W-1:0] qid_t;
typedef logic [RX_ID_W-1:0] port_id_t;
typedef enum logic [3:0] {COMMITTED=0, BAD_QID=1, BAD_LENGTH=2,
    QUEUE_LIMIT=3, NO_DESCRIPTOR=4, NO_CELLS=5, FRAME_ERROR=6} status_code_t;
typedef enum logic [2:0] {FREE=0, RX=1, QUEUED=2, TX=3, ABORT=4} owner_t;
typedef enum logic [1:0] {IDLE=0, RECEIVE=1, DRAIN_REJECT=2, ABORT_DRAIN=3} rx_phase_t;
typedef enum logic [1:0] {OKAY=0, SLVERR=2, DECERR=3} axil_resp_t;
typedef struct packed {logic [DATA_W-1:0] data; logic [DATA_W/8-1:0] keep;
    logic last; logic [63:0] user;} beat_t;
typedef struct packed {logic [23:0] reserved; logic [15:0] tag;
    logic [15:0] length; logic [7:0] qid;} input_user_t;
typedef struct packed {logic [15:0] reserved; logic [7:0] source;
    logic [15:0] tag; logic [15:0] length; logic [7:0] qid;} output_user_t;
typedef struct packed {logic valid; status_code_t code; logic [15:0] tag;
    logic [7:0] qid; logic [15:0] length;} status_t;
typedef struct packed {cell_id_t head; cell_count_t ncell; logic [15:0] length;
    qid_t qid; logic [15:0] tag; port_id_t source;} descriptor_t;
typedef struct packed {rx_phase_t phase; logic [7:0] qid;
    logic [15:0] length; logic [15:0] tag; desc_id_t desc;
    cell_id_t head; cell_id_t tail; cell_count_t allocated; cell_count_t reserved;
    logic [15:0] beat_number; logic [WORD_OFF_W-1:0] word_offset;
    logic drain_done; logic cleanup_done;} rx_context_t;
typedef struct packed {logic valid; port_id_t source; beat_t beat; logic sop;} service_t;
typedef struct packed {logic valid; port_id_t source; logic [7:0] qid;
    logic [15:0] tag; logic [15:0] length; cell_count_t ncell;
    logic accept; status_code_t reason; desc_id_t desc;} admission_t;
typedef struct packed {logic valid; desc_id_t desc; qid_t qid;
    descriptor_t info;} commit_t;
typedef struct packed {logic valid; qid_t qid; desc_id_t desc;
    descriptor_t info;} dispatch_t;
typedef struct packed {logic valid; desc_id_t desc;} desc_return_t;
typedef struct packed {logic valid; cell_id_t id; desc_id_t desc;} cell_alloc_t;
typedef struct packed {logic valid; cell_id_t id; logic abort_source;
    qid_t qid; desc_id_t desc;} cell_return_t;
typedef struct packed {logic valid; port_id_t source; desc_id_t desc;
    qid_t qid; cell_id_t head; cell_count_t allocated;
    cell_count_t reserved;} abort_mark_t;
typedef struct packed {logic valid; port_id_t source; desc_id_t desc;
    qid_t qid; cell_count_t ncell;} abort_done_t;
typedef struct packed {logic valid; desc_id_t desc; qid_t qid;
    logic [15:0] length;} tx_done_t;
typedef struct packed {logic valid; logic [ADDR_W-1:0] addr;
    logic [DATA_W-1:0] data;} ram_write_t;
typedef struct packed {logic valid; logic [ADDR_W-1:0] addr;} ram_read_t;
typedef struct packed {logic valid; logic [DATA_W-1:0] data;} ram_response_t;
typedef struct packed {logic valid; cell_id_t id; cell_id_t next_id;} cell_link_write_t;
typedef struct packed {logic valid; desc_id_t id; desc_id_t next_id;} desc_link_write_t;
typedef struct packed {logic valid; desc_id_t id; descriptor_t info;} desc_write_t;
typedef struct packed {logic run; logic wait_mode; logic initialized;
    logic [N_Q*CELL_COUNT_W-1:0] cell_limit;
    logic [N_Q*13-1:0] quantum;} config_t;
// Queue lane q occupies [q*width +: width] on all packed array boundaries.
typedef struct packed {cell_count_t assigned; cell_count_t physical_free;
    cell_count_t unreserved; cell_count_t reserved_free; desc_count_t free_desc;
    logic [N_Q*CELL_COUNT_W-1:0] owned;
    logic [N_Q*DESC_COUNT_W-1:0] queued;
    logic [N_Q*DEFICIT_W-1:0] deficit; logic idle; logic invariant_error;} live_t;
// Global order and per-queue order are specified in registers.md.
typedef struct packed {logic [10*64-1:0] global_counts;
    logic [N_Q*5*64-1:0] queue_counts;
    logic [N_Q*CELL_COUNT_W-1:0] high_water;} statistics_t;
typedef struct packed {logic snapshot; logic clear;} stats_command_t;
typedef struct packed {logic awvalid; logic [31:0] awaddr; logic [2:0] awprot;
    logic wvalid; logic [31:0] wdata; logic [3:0] wstrb; logic bready;
    logic arvalid; logic [31:0] araddr; logic [2:0] arprot; logic rready;} axil_request_t;
typedef struct packed {logic awready; logic wready; logic bvalid; axil_resp_t bresp;
    logic arready; logic rvalid; logic [31:0] rdata; axil_resp_t rresp;} axil_response_t;
// One complete observation batch, sampled on one architectural edge.
// External captures, output and bus handshakes come from independent monitors.
typedef struct packed {service_t rx_service; admission_t admit; commit_t commit;
    dispatch_t dispatch; cell_alloc_t cell_alloc; cell_return_t cell_free;
    abort_mark_t abort_mark; abort_done_t abort_done; tx_done_t tx_done;} trace_t;

generate
endgenerate
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
