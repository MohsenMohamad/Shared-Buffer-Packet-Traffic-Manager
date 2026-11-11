module tm_axis_rx_fifo_api #(
`include "tm_parameters.svh"

, localparam integer RX_ID_W=(N_RX>1 ? $clog2(N_RX) : 1),
localparam integer Q_ID_W=(N_Q>1 ? $clog2(N_Q) : 1),
localparam integer WORD_OFF_W=(CELL_BYTES/8>1 ? $clog2(CELL_BYTES/8) : 1),
localparam integer ADDR_W=(N_CELL*CELL_BYTES/8>1 ? $clog2(N_CELL*CELL_BYTES/8) : 1),
localparam integer BEAT_W=DATA_W+DATA_W/8+65,
localparam integer DESC_INFO_W=CELL_ID_W+CELL_COUNT_W+16+Q_ID_W+16+RX_ID_W
) (
    input logic clk,
    input logic rst_n,
    input logic enable,
    input logic s_valid,
    input struct packed {logic [DATA_W-1:0] data; logic [DATA_W/8-1:0] keep;
    logic last; logic [63:0] user;} s_beat,
    output logic s_ready,
    output logic m_valid,
    output struct packed {logic [DATA_W-1:0] data; logic [DATA_W/8-1:0] keep;
    logic last; logic [63:0] user;} m_beat,
    input logic m_ready,
    output logic empty
);
import tm_fixed::*;
// Module-local packed types: portable through Verilator and Yosys read_verilog -sv.
// Include after tm_parameters.svh, before non-ANSI port declarations.

typedef logic [CELL_ID_W-1:0] cell_id_t;
typedef logic [DESC_ID_W-1:0] desc_id_t;
typedef logic [CELL_COUNT_W-1:0] cell_count_t;
typedef logic [DESC_COUNT_W-1:0] desc_count_t;
typedef logic [DEFICIT_W-1:0] deficit_t;
typedef logic [Q_ID_W-1:0] qid_t;
typedef logic [RX_ID_W-1:0] port_id_t;




typedef struct packed {logic [DATA_W-1:0] data; logic [DATA_W/8-1:0] keep;
    logic last; logic [63:0] user;} beat_t;



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



// One complete observation batch, sampled on one architectural edge.
// External captures, output and bus handshakes come from independent monitors.
typedef struct packed {service_t rx_service; admission_t admit; commit_t commit;
    dispatch_t dispatch; cell_alloc_t cell_alloc; cell_return_t cell_free;
    abort_mark_t abort_mark; abort_done_t abort_done; tx_done_t tx_done;} trace_t;

generate
endgenerate
`include "tm_validate.svh"

localparam integer PTR_W=(RX_FIFO_DEPTH>1 ? $clog2(RX_FIFO_DEPTH) : 1);
localparam integer OCC_W=$clog2(RX_FIFO_DEPTH+1);
logic [PTR_W-1:0] rd_ptr, wr_ptr;
logic [OCC_W-1:0] occupancy, next_occupancy;
logic [BEAT_W-1:0] storage [0:RX_FIFO_DEPTH-1];
logic ready_q, push, pop;
// enable is a registered RUN/initialized query at integration. Neither ready
// nor valid depends on the opposite channel's current handshake inputs.
assign s_ready = rst_n && enable && ready_q;
assign m_valid = rst_n && (occupancy != 0);
assign empty = (occupancy == 0);
assign m_beat = storage[rd_ptr];
assign push = s_valid && s_ready;
assign pop = m_valid && m_ready;
always_comb begin
    next_occupancy = occupancy;
    case ({push,pop})
        2'b10: next_occupancy = occupancy + OCC_W'(1);
        2'b01: next_occupancy = occupancy - OCC_W'(1);
        default: ;
    endcase
end
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr <= '0;
        wr_ptr <= '0;
        occupancy <= '0;
        ready_q <= 1'b1;
    end else begin
        occupancy <= next_occupancy;
        ready_q <= (next_occupancy < OCC_W'(RX_FIFO_DEPTH));
        if (push) wr_ptr <= wr_ptr + PTR_W'(1);
        if (pop) rd_ptr <= rd_ptr + PTR_W'(1);
    end
end
// Payload is deliberately unreset. Occupancy is its only validity authority.
always_ff @(posedge clk) begin
    if (push) storage[wr_ptr] <= s_beat;
end
`ifdef FORMAL
`include "fifo_properties.svh"
`endif
endmodule
