module tm_axis_rx_fifo_api #(
`include "tm_parameters.svh"
, localparam integer BEAT_W=DATA_W+DATA_W/8+65
) (
    input logic clk,
    input logic rst_n,
    input logic enable,
    input logic s_valid,
    input logic [BEAT_W-1:0] s_beat,
    output logic s_ready,
    output logic m_valid,
    output logic [BEAT_W-1:0] m_beat,
    input logic m_ready,
    output logic empty
);
`include "tm_validate.svh"

localparam integer PTR_W=(RX_FIFO_DEPTH>1 ? $clog2(RX_FIFO_DEPTH) : 1);
localparam integer OCC_W=$clog2(RX_FIFO_DEPTH+1);
logic [PTR_W-1:0] rd_ptr, wr_ptr;
logic [OCC_W-1:0] occupancy, next_occupancy;
// Whole-beat bit copies need no field/type adaptation. Record arrays also infer
// correctly on the selected stack; fifo-mapping compares both against baseline.
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
