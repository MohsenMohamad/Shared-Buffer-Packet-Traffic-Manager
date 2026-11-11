// Capability harness: actual FIFO plus a small CSR snapshot/packed-lane stage.
module snapshot_probe #(
`include "tm_parameters.svh"
) (
    input logic clk,input logic rst_n,input logic snapshot,
    input logic [N_Q*CELL_COUNT_W-1:0] owned,
    output logic [N_Q*CELL_COUNT_W-1:0] shadow_owned,
    output tm_fixed::axil_resp_t response
);
`include "tm_scoped_types.svh"
live_t live_record;
statistics_t shadow_record;
always_comb begin
    live_record='0;
    live_record.owned=owned;
    response=tm_fixed::OKAY;
end
assign shadow_owned=shadow_record.high_water;
always_ff @(posedge clk) begin
    if(!rst_n) shadow_record<='0;
    else if(snapshot) begin
`ifdef MUTATION
        shadow_record.high_water<=live_record.owned ^ 1;
`else
        shadow_record.high_water<=live_record.owned;
`endif
    end
end
logic past_valid=0;
always @(posedge clk) begin
    past_valid<=1;
    if(past_valid && $past(rst_n && snapshot)) begin
        a_snapshot: assert(shadow_owned==$past(owned));
        a_enum: assert(response==tm_fixed::OKAY);
    end
    c_snapshot_last_lane: cover(past_valid && rst_n && shadow_owned[(N_Q-1)*CELL_COUNT_W +: CELL_COUNT_W]==CELL_COUNT_W'(3));
end
endmodule

module formal_top(input clk);
logic [1:0] startup=0;
(* anyseq *) logic rst_n;
always @(posedge clk) if(startup!=2) startup<=startup+1;
always @(posedge clk) if(startup!=2) assume(!rst_n);
(* anyseq *) logic snapshot;
(* anyseq *) logic [23:0] owned;
wire [9:0] shadow_a;
wire [23:0] shadow_b;
tm_fixed::axil_resp_t response_a,response_b;
snapshot_probe #(.N_RX(1),.N_Q(2),.N_CELL(16),.N_DESC(8),.CELL_BYTES(16),.MAX_PACKET_BYTES(128)) a(
    .clk(clk),.rst_n(rst_n),.snapshot(snapshot),.owned(owned[9:0]),.shadow_owned(shadow_a),.response(response_a));
snapshot_probe #(.N_RX(2),.N_Q(4),.N_CELL(32),.N_DESC(16),.CELL_BYTES(16),.MAX_PACKET_BYTES(128)) b(
    .clk(clk),.rst_n(rst_n),.snapshot(snapshot),.owned(owned),.shadow_owned(shadow_b),.response(response_b));
(* anyseq *) logic s_valid,m_ready;
(* anyseq *) logic [136:0] s_beat;
wire s_ready,m_valid,empty;
wire [136:0] m_beat;
tm_axis_rx_fifo_api #(.N_RX(1),.N_Q(2),.N_CELL(16),.N_DESC(8),.CELL_BYTES(16),.MAX_PACKET_BYTES(128)) fifo(
    .clk(clk),.rst_n(rst_n),.enable(1'b1),.s_valid(s_valid),.s_beat(s_beat),
    .s_ready(s_ready),.m_valid(m_valid),.m_beat(m_beat),.m_ready(m_ready),.empty(empty));
endmodule
