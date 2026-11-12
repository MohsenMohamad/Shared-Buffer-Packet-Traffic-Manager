module storage_formal(clk,rst_n,
`ifdef PROVE_CELL
allocate,release_cell
`elsif PROVE_DESC
admit,tx_return,abort_return
`else
enable,s_valid,m_ready,s_beat
`endif
);
input clk;
// Only reset startup is constrained. Later resets and all action inputs are
// arbitrary, including illegal IDs, duplicates and source/sink stalls.
input logic rst_n;
logic [1:0] startup=0;
always @(posedge clk) begin
    if(startup<2) begin assume(!rst_n); startup<=startup+1; end
end
localparam integer DATA_W=64, N_RX=1, N_Q=2, N_CELL=16, N_DESC=8,
    CELL_BYTES=16, MAX_PACKET_BYTES=128, RX_FIFO_DEPTH=2, MEM_RD_LATENCY=1,
    TX_FIFO_DEPTH=4, SCHED_MODE=1, QUANTUM_DEFAULT=128, TRACE_ENABLE=1,
    CELL_COUNT_W=5, DESC_COUNT_W=4, DEFICIT_W=13;
`ifdef PROVE_CELL
localparam integer CELL_ID_W=5, DESC_ID_W=3;
`else
localparam integer CELL_ID_W=4, DESC_ID_W=4;
`endif
`include "tm_types.svh"
`ifdef PROVE_CELL
input cell_alloc_t allocate;
input cell_return_t release_cell;
tm_cell_pool_api #(.N_RX(1),.N_Q(2),.N_CELL(16),.N_DESC(8),.CELL_BYTES(16),
    .MAX_PACKET_BYTES(128),.CELL_ID_W(5)) dut (
    .clk(clk),.rst_n(rst_n),.allocate(allocate),.release_cell(release_cell));
`elsif PROVE_DESC
input admission_t admit;
input desc_return_t tx_return,abort_return;
tm_desc_pool_api #(.N_RX(1),.N_Q(2),.N_CELL(16),.N_DESC(8),.CELL_BYTES(16),
    .MAX_PACKET_BYTES(128),.DESC_ID_W(4)) dut (
    .clk(clk),.rst_n(rst_n),.admit(admit),.tx_return(tx_return),.abort_return(abort_return));
`else
input logic enable,s_valid,m_ready;
input beat_t s_beat;
tm_axis_rx_fifo_api #(.N_RX(1),.N_Q(2),.N_CELL(16),.N_DESC(8),.CELL_BYTES(16),
    .MAX_PACKET_BYTES(128),.RX_FIFO_DEPTH(`FIFO_DEPTH)) dut (
    .clk(clk),.rst_n(rst_n),.enable(enable),.s_valid(s_valid),.s_beat(s_beat),.m_ready(m_ready));
`endif
endmodule
