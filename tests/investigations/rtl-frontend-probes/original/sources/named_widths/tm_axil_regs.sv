module tm_axil_regs_api #(
`include "tm_parameters.svh"

, localparam integer RX_ID_W=(N_RX>1 ? $clog2(N_RX) : 1),
localparam integer Q_ID_W=(N_Q>1 ? $clog2(N_Q) : 1),
localparam integer WORD_OFF_W=(CELL_BYTES/8>1 ? $clog2(CELL_BYTES/8) : 1),
localparam integer ADDR_W=(N_CELL*CELL_BYTES/8>1 ? $clog2(N_CELL*CELL_BYTES/8) : 1),
localparam integer BEAT_W=DATA_W+DATA_W/8+65,
localparam integer DESC_INFO_W=CELL_ID_W+CELL_COUNT_W+16+Q_ID_W+16+RX_ID_W,
localparam integer LIVE_W=((CELL_COUNT_W)+(CELL_COUNT_W)+(CELL_COUNT_W)+(CELL_COUNT_W)+(DESC_COUNT_W)+(N_Q*CELL_COUNT_W)+(N_Q*DESC_COUNT_W)+(N_Q*DEFICIT_W)+(1)+(1)),
localparam integer STATISTICS_W=((10*64)+(N_Q*5*64)+(N_Q*CELL_COUNT_W)),
localparam integer CONFIG_W=((1)+(1)+(1)+(N_Q*CELL_COUNT_W)+(N_Q*13))
) (
    input logic clk,
    input logic rst_n,
    input logic initialized,
    input tm_fixed::axil_request_t bus_req,
    output tm_fixed::axil_response_t bus_rsp,
    input logic [LIVE_W-1:0] live,
    input logic [STATISTICS_W-1:0] live_stats,
    input logic [STATISTICS_W-1:0] shadow_stats,
    output logic [CONFIG_W-1:0] cfg,
    output tm_fixed::stats_command_t stats_command
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




typedef struct packed {logic [DATA_W-1:0] data; logic [DATA_W/8-1:0] keep;
    logic last; logic [63:0] user;} beat_t;



typedef struct packed {cell_id_t head; cell_count_t ncell; logic [15:0] length;
    qid_t qid; logic [15:0] tag; port_id_t source;} descriptor_t;
typedef struct packed {tm_fixed::rx_phase_t phase; logic [7:0] qid;
    logic [15:0] length; logic [15:0] tag; desc_id_t desc;
    cell_id_t head; cell_id_t tail; cell_count_t allocated; cell_count_t reserved;
    logic [15:0] beat_number; logic [WORD_OFF_W-1:0] word_offset;
    logic drain_done; logic cleanup_done;} rx_context_t;
typedef struct packed {logic valid; port_id_t source; beat_t beat; logic sop;} service_t;
typedef struct packed {logic valid; port_id_t source; logic [7:0] qid;
    logic [15:0] tag; logic [15:0] length; cell_count_t ncell;
    logic accept; tm_fixed::status_code_t reason; desc_id_t desc;} admission_t;
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

live_t live_typed;
assign live_typed = live;
statistics_t live_stats_typed;
assign live_stats_typed = live_stats;
statistics_t shadow_stats_typed;
assign shadow_stats_typed = shadow_stats;
config_t cfg_typed;
assign cfg = cfg_typed;
generate
if ($bits(live_typed) != $bits(live)) begin : g_width_live TM_INVALID_LAYOUT bad(); end
if ($bits(live_stats_typed) != $bits(live_stats)) begin : g_width_live_stats TM_INVALID_LAYOUT bad(); end
if ($bits(shadow_stats_typed) != $bits(shadow_stats)) begin : g_width_shadow_stats TM_INVALID_LAYOUT bad(); end
if ($bits(cfg_typed) != $bits(cfg)) begin : g_width_cfg TM_INVALID_LAYOUT bad(); end
endgenerate
`include "tm_validate.svh"

logic have_aw, have_w, have_ar, bvalid, rvalid;
logic [31:0] awaddr, wdata, araddr, rdata;
logic [3:0] wstrb;
tm_fixed::axil_resp_t bresp, rresp, write_response, read_response;
logic run_q, wait_q, invariant_q;
logic [N_Q*CELL_COUNT_W-1:0] limits;
logic [N_Q*13-1:0] quanta;
logic [31:0] write_word, read_word, old_word, merged_word, read_value;
logic write_execute, read_execute;
integer write_q, read_q;

// Decode the aligned word before checking alignment. A hole, including an
// invalid queue encoding, is tm_fixed::DECERR even when its byte address is unaligned.
function automatic logic mapped(input logic [31:0] word_addr);
    mapped = (word_addr <= 32'h034) ||
        (word_addr >= 32'h100 && word_addr < 32'h150) ||
        (word_addr >= 32'h400 && word_addr < 32'h400 + 32'(N_Q*64));
endfunction
function automatic logic [31:0] merge_bytes(input logic [31:0] old_value,
    input logic [31:0] new_value, input logic [3:0] strobes);
    for (integer lane=0; lane<4; lane=lane+1)
        merge_bytes[lane*8 +: 8] = strobes[lane] ? new_value[lane*8 +: 8] : old_value[lane*8 +: 8];
endfunction

// All bus outputs depend only on state (and reset), never current bus inputs.
always_comb begin
    bus_rsp = '0;
    bus_rsp.awready = rst_n && !have_aw && !bvalid;
    bus_rsp.wready = rst_n && !have_w && !bvalid;
    bus_rsp.arready = rst_n && !have_ar && !rvalid;
    bus_rsp.bvalid = rst_n && bvalid;
    bus_rsp.bresp = bresp;
    bus_rsp.rvalid = rst_n && rvalid;
    bus_rsp.rdata = rdata;
    bus_rsp.rresp = rresp;
    cfg_typed.run = run_q;
    cfg_typed.wait_mode = wait_q;
    cfg_typed.initialized = initialized;
    cfg_typed.cell_limit = limits;
    cfg_typed.quantum = quanta;
end
assign write_execute = rst_n && have_aw && have_w && !bvalid;
assign read_execute = rst_n && have_ar && !rvalid;

always_comb begin
    write_word = {awaddr[31:2],2'b00};
    write_q = 0;
    old_word = '0;
    if (write_word == 32'h010) old_word = {31'b0,run_q};
    if (write_word == 32'h020) old_word = {31'b0,wait_q};
    // Validate the full address before deriving an array subscript.
    if (write_word >= 32'h400 && write_word < 32'h400 + 32'(N_Q*64)) begin
        write_q = int'((write_word-32'h400) >> 6);
        if (write_word[5:0] == 0) old_word = 32'(limits[write_q*CELL_COUNT_W +: CELL_COUNT_W]);
        if (write_word[5:0] == 4) old_word = 32'(quanta[write_q*13 +: 13]);
    end
    merged_word = merge_bytes(old_word,wdata,wstrb);
    write_response = tm_fixed::OKAY;
    stats_command = '0;
    if (!mapped(write_word)) write_response = tm_fixed::DECERR;
    else if (awaddr[1:0] != 0) write_response = tm_fixed::SLVERR;
    else if (wstrb == 0) begin end // Mapped zero-strobe writes include RO words.
    else begin
        case (write_word)
            32'h010: if (wstrb[0] && !merged_word[0] && !live_typed.idle) write_response = tm_fixed::SLVERR;
            32'h018: stats_command.snapshot = write_execute && merged_word[0];
            32'h01c: begin
                if (merged_word[0] && (run_q || !live_typed.idle)) write_response = tm_fixed::SLVERR;
                else stats_command.clear = write_execute && merged_word[0];
            end
            32'h020: if (run_q || !live_typed.idle || merged_word > 1) write_response = tm_fixed::SLVERR;
            default: begin
                if (write_word >= 32'h400 && write_word < 32'h400 + 32'(N_Q*64) &&
                    (write_word[5:0] == 0 || write_word[5:0] == 4)) begin
                    if (run_q || !live_typed.idle) write_response = tm_fixed::SLVERR;
                    else if (write_word[5:0] == 0 && (merged_word < 1 || merged_word > 32'(N_CELL))) write_response = tm_fixed::SLVERR;
                    else if (write_word[5:0] == 4 && (merged_word < 64 || merged_word > 4096)) write_response = tm_fixed::SLVERR;
                end else write_response = tm_fixed::SLVERR;
            end
        endcase
    end
end

always_comb begin
    read_word = {araddr[31:2],2'b00};
    read_q = 0;
    read_value = '0;
    read_response = tm_fixed::OKAY;
    if (!mapped(read_word)) read_response = tm_fixed::DECERR;
    else if (araddr[1:0] != 0) read_response = tm_fixed::SLVERR;
    else begin
        case (read_word)
            32'h000: read_value = 32'h544d0100;
            32'h004: read_value = 32'h00010000;
            32'h008: read_value = {8'(CELL_BYTES),8'(DATA_W/8),8'(N_Q),8'(N_RX)};
            32'h00c: read_value = {16'(N_DESC),16'(N_CELL)};
            32'h010: read_value = {31'b0,run_q};
            32'h014: read_value = {28'b0,(invariant_q || live_typed.invariant_error),initialized,live_typed.idle,run_q};
            32'h020: read_value = {31'b0,wait_q};
            32'h024: read_value = 32'(live_typed.unreserved);
            32'h028: read_value = 32'(live_typed.reserved_free);
            32'h02c: read_value = 32'(live_typed.free_desc);
            32'h030: read_value = 32'(SCHED_MODE);
            32'h034: read_value = 32'(MAX_PACKET_BYTES);
            default: begin
                if (read_word >= 32'h100 && read_word < 32'h150)
                    read_value = shadow_stats_typed.global_counts[int'(read_word-32'h100)*8 +: 32];
                if (read_word >= 32'h400 && read_word < 32'h400 + 32'(N_Q*64)) begin
                    read_q = int'((read_word-32'h400) >> 6);
                    case (read_word[5:0])
                        0: read_value = 32'(limits[read_q*CELL_COUNT_W +: CELL_COUNT_W]);
                        4: read_value = 32'(quanta[read_q*13 +: 13]);
                        8: read_value = 32'(live_typed.owned[read_q*CELL_COUNT_W +: CELL_COUNT_W]);
                        12: read_value = 32'(live_typed.queued[read_q*DESC_COUNT_W +: DESC_COUNT_W]);
                        16: read_value = 32'(live_typed.deficit[read_q*DEFICIT_W +: DEFICIT_W]);
                        20: read_value = 32'(shadow_stats_typed.high_water[read_q*CELL_COUNT_W +: CELL_COUNT_W]);
                        default: read_value = shadow_stats_typed.queue_counts[read_q*320+(int'(read_word[5:0])-24)*8 +: 32];
                    endcase
                end
            end
        endcase
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        have_aw <= 0; have_w <= 0; have_ar <= 0;
        bvalid <= 0; rvalid <= 0; bresp <= tm_fixed::OKAY; rresp <= tm_fixed::OKAY;
        awaddr <= 0; wdata <= 0; wstrb <= 0; araddr <= 0; rdata <= 0;
        run_q <= 0; wait_q <= 0; invariant_q <= 0;
        for (integer q=0; q<N_Q; q=q+1) begin
            limits[q*CELL_COUNT_W +: CELL_COUNT_W] <= CELL_COUNT_W'(N_CELL);
            quanta[q*13 +: 13] <= 13'(MAX_PACKET_BYTES);
        end
    end else begin
        invariant_q <= invariant_q || live_typed.invariant_error;
        if (bus_req.awvalid && bus_rsp.awready) begin have_aw <= 1; awaddr <= bus_req.awaddr; end
        if (bus_req.wvalid && bus_rsp.wready) begin have_w <= 1; wdata <= bus_req.wdata; wstrb <= bus_req.wstrb; end
        if (bus_req.arvalid && bus_rsp.arready) begin have_ar <= 1; araddr <= bus_req.araddr; end
        if (write_execute) begin
            bvalid <= 1;
            bresp <= write_response;
            if (write_response == tm_fixed::OKAY && wstrb != 0) begin
                if (write_word == 32'h010 && wstrb[0]) run_q <= merged_word[0];
                if (write_word == 32'h020) wait_q <= merged_word[0];
                if (write_word >= 32'h400 && write_word < 32'h400 + 32'(N_Q*64)) begin
                    if (write_word[5:0] == 0) limits[write_q*CELL_COUNT_W +: CELL_COUNT_W] <= CELL_COUNT_W'(merged_word);
                    if (write_word[5:0] == 4) quanta[write_q*13 +: 13] <= 13'(merged_word);
                end
            end
        end
        if (bvalid && bus_req.bready) begin bvalid <= 0; have_aw <= 0; have_w <= 0; end
        // Nonblocking updates give read-before-write and pre-snapshot reads.
        if (read_execute) begin rvalid <= 1; rdata <= read_value; rresp <= read_response; end
        if (rvalid && bus_req.rready) begin rvalid <= 0; have_ar <= 0; end
    end
end
`ifdef FORMAL
`include "csr_properties.svh"
`endif
endmodule
