module tm_axil_regs_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input logic initialized,
    input axil_request_t bus_req,
    output axil_response_t bus_rsp,
    input live_t live,
    // Retained P01 input; statistics reads select shadow_stats.
    input statistics_t live_stats,
    input statistics_t shadow_stats,
    output config_t cfg,
    output stats_command_t stats_command
);
`include "tm_validate.svh"

logic have_aw, have_w, have_ar, bvalid, rvalid;
logic [31:0] awaddr, wdata, araddr, rdata;
logic [3:0] wstrb;
axil_resp_t bresp, rresp, write_response, read_response;
logic run_q, wait_q, invariant_q;
logic [N_Q*CELL_COUNT_W-1:0] limits;
logic [N_Q*13-1:0] quanta;
logic [31:0] write_word, read_word, old_word, merged_word, read_value;
logic write_execute, read_execute;
integer write_q, read_q;

// Decode the aligned word before checking alignment. A hole, including an
// invalid queue encoding, is DECERR even when its byte address is unaligned.
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
    cfg.run = run_q;
    cfg.wait_mode = wait_q;
    cfg.initialized = initialized;
    cfg.cell_limit = limits;
    cfg.quantum = quanta;
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
    write_response = OKAY;
    stats_command = '0;
    if (!mapped(write_word)) write_response = DECERR;
    else if (awaddr[1:0] != 0) write_response = SLVERR;
    else if (wstrb == 0) begin end // Mapped zero-strobe writes include RO words.
    else begin
        case (write_word)
            32'h010: if (wstrb[0] && !merged_word[0] && !live.idle) write_response = SLVERR;
            32'h018: stats_command.snapshot = write_execute && merged_word[0];
            32'h01c: begin
                if (merged_word[0] && (run_q || !live.idle)) write_response = SLVERR;
                else stats_command.clear = write_execute && merged_word[0];
            end
            32'h020: if (run_q || !live.idle || merged_word > 1) write_response = SLVERR;
            default: begin
                if (write_word >= 32'h400 && write_word < 32'h400 + 32'(N_Q*64) &&
                    (write_word[5:0] == 0 || write_word[5:0] == 4)) begin
                    if (run_q || !live.idle) write_response = SLVERR;
                    else if (write_word[5:0] == 0 && (merged_word < 1 || merged_word > 32'(N_CELL))) write_response = SLVERR;
                    else if (write_word[5:0] == 4 && (merged_word < 64 || merged_word > 4096)) write_response = SLVERR;
                end else write_response = SLVERR;
            end
        endcase
    end
end

always_comb begin
    read_word = {araddr[31:2],2'b00};
    read_q = 0;
    read_value = '0;
    read_response = OKAY;
    if (!mapped(read_word)) read_response = DECERR;
    else if (araddr[1:0] != 0) read_response = SLVERR;
    else begin
        case (read_word)
            32'h000: read_value = 32'h544d0100;
            32'h004: read_value = 32'h00010000;
            32'h008: read_value = {8'(CELL_BYTES),8'(DATA_W/8),8'(N_Q),8'(N_RX)};
            32'h00c: read_value = {16'(N_DESC),16'(N_CELL)};
            32'h010: read_value = {31'b0,run_q};
            32'h014: read_value = {28'b0,(invariant_q || live.invariant_error),initialized,live.idle,run_q};
            32'h020: read_value = {31'b0,wait_q};
            32'h024: read_value = 32'(live.unreserved);
            32'h028: read_value = 32'(live.reserved_free);
            32'h02c: read_value = 32'(live.free_desc);
            32'h030: read_value = 32'(SCHED_MODE);
            32'h034: read_value = 32'(MAX_PACKET_BYTES);
            default: begin
                if (read_word >= 32'h100 && read_word < 32'h150)
                    read_value = shadow_stats.global_counts[int'(read_word-32'h100)*8 +: 32];
                if (read_word >= 32'h400 && read_word < 32'h400 + 32'(N_Q*64)) begin
                    read_q = int'((read_word-32'h400) >> 6);
                    case (read_word[5:0])
                        0: read_value = 32'(limits[read_q*CELL_COUNT_W +: CELL_COUNT_W]);
                        4: read_value = 32'(quanta[read_q*13 +: 13]);
                        8: read_value = 32'(live.owned[read_q*CELL_COUNT_W +: CELL_COUNT_W]);
                        12: read_value = 32'(live.queued[read_q*DESC_COUNT_W +: DESC_COUNT_W]);
                        16: read_value = 32'(live.deficit[read_q*DEFICIT_W +: DEFICIT_W]);
                        20: read_value = 32'(shadow_stats.high_water[read_q*CELL_COUNT_W +: CELL_COUNT_W]);
                        default: read_value = shadow_stats.queue_counts[read_q*320+(int'(read_word[5:0])-24)*8 +: 32];
                    endcase
                end
            end
        endcase
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        have_aw <= 0; have_w <= 0; have_ar <= 0;
        bvalid <= 0; rvalid <= 0; bresp <= OKAY; rresp <= OKAY;
        awaddr <= 0; wdata <= 0; wstrb <= 0; araddr <= 0; rdata <= 0;
        run_q <= 0; wait_q <= 0; invariant_q <= 0;
        for (integer q=0; q<N_Q; q=q+1) begin
            limits[q*CELL_COUNT_W +: CELL_COUNT_W] <= CELL_COUNT_W'(N_CELL);
            quanta[q*13 +: 13] <= 13'(MAX_PACKET_BYTES);
        end
    end else begin
        invariant_q <= invariant_q || live.invariant_error;
        if (bus_req.awvalid && bus_rsp.awready) begin have_aw <= 1; awaddr <= bus_req.awaddr; end
        if (bus_req.wvalid && bus_rsp.wready) begin have_w <= 1; wdata <= bus_req.wdata; wstrb <= bus_req.wstrb; end
        if (bus_req.arvalid && bus_rsp.arready) begin have_ar <= 1; araddr <= bus_req.araddr; end
        if (write_execute) begin
            bvalid <= 1;
            bresp <= write_response;
            if (write_response == OKAY && wstrb != 0) begin
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
