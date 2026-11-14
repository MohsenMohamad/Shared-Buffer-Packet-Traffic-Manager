module tm_metadata_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input cell_link_write_t cell_write,
    input desc_link_write_t queue_write,
    input desc_write_t info_write,
    input cell_id_t tx_cell,
    input cell_id_t abort_cell,
    output cell_id_t tx_next,
    output cell_id_t abort_next,
    input logic [N_Q*DESC_ID_W-1:0] queue_heads,
    output logic [N_Q*DESC_INFO_W-1:0] head_info,
    input desc_id_t queue_head,
    output desc_id_t queue_next
);
`include "tm_validate.svh"
// Register metadata: one RX extension writer and two cell-link read muxes;
// one reservation writer and N_Q descriptor-info read muxes. No reset/bypass.
cell_id_t cell_next [N_CELL];
descriptor_t descriptor_info [N_DESC];
assign tx_next = int'(tx_cell)<N_CELL ? cell_next[tx_cell] : '0;
assign abort_next = int'(abort_cell)<N_CELL ? cell_next[abort_cell] : '0;
for (genvar q=0; q<N_Q; q++) begin : g_head_query
    wire [DESC_ID_W-1:0] id = queue_heads[q*DESC_ID_W +: DESC_ID_W];
    assign head_info[q*DESC_INFO_W +: DESC_INFO_W] =
        int'(id)<N_DESC ? descriptor_info[id] : '0;
end
// The P03 child remains the sole descriptor-next owner: 1W, 1 read mux.
tm_desc_links #(
    .DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES),
    .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES),
    .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY),
    .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .SCHED_MODE(SCHED_MODE),
    .QUANTUM_DEFAULT(QUANTUM_DEFAULT), .TRACE_ENABLE(TRACE_ENABLE),
    .CELL_ID_W(CELL_ID_W), .DESC_ID_W(DESC_ID_W),
    .CELL_COUNT_W(CELL_COUNT_W), .DESC_COUNT_W(DESC_COUNT_W),
    .DEFICIT_W(DEFICIT_W)
) queue_links (.clk, .write_req(queue_write), .read_id(queue_head),
    .read_next(queue_next));
always_ff @(posedge clk) begin
    if (cell_write.valid) cell_next[cell_write.id] <= cell_write.next_id;
    if (info_write.valid) descriptor_info[info_write.id] <= info_write.info;
end
`ifndef SYNTHESIS
always_ff @(posedge clk) begin
    if (cell_write.valid) begin
        assert (int'(cell_write.id)<N_CELL);
        assert (int'(cell_write.next_id)<N_CELL);
    end
    if (info_write.valid) assert (int'(info_write.id)<N_DESC);
    if (queue_write.valid) begin
        assert (int'(queue_write.id)<N_DESC);
        assert (int'(queue_write.next_id)<N_DESC);
    end
end
`endif
endmodule
