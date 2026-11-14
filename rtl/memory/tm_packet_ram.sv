module tm_packet_ram_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input ram_write_t write_req,
    input ram_read_t read_req,
    output ram_response_t response
);
`include "tm_validate.svh"
localparam integer N_WORD=N_CELL*CELL_BYTES/8;
// Exactly one read and one write. No reset on either array or pipeline.
// A request accepted at e is sampled as a response at e+MEM_RD_LATENCY.
logic [DATA_W-1:0] payload [N_WORD];
logic [MEM_RD_LATENCY-1:0] response_valid;
logic [DATA_W-1:0] response_data [MEM_RD_LATENCY];
assign response.valid = response_valid[MEM_RD_LATENCY-1];
assign response.data = response_data[MEM_RD_LATENCY-1];
always_ff @(posedge clk) begin
    if (write_req.valid) payload[write_req.addr] <= write_req.data;
    response_valid[0] <= read_req.valid;
    if (read_req.valid) response_data[0] <= payload[read_req.addr];
    for (int stage=1; stage<MEM_RD_LATENCY; stage++) begin
        response_valid[stage] <= response_valid[stage-1];
        response_data[stage] <= response_data[stage-1];
    end
end
`ifndef SYNTHESIS
always_ff @(posedge clk) begin
    if (write_req.valid) assert (int'(write_req.addr)<N_WORD);
    if (read_req.valid) assert (int'(read_req.addr)<N_WORD);
    // Ownership must prevent this; simulator read-during-write is irrelevant.
    assert (!(write_req.valid && read_req.valid && write_req.addr==read_req.addr))
        else $fatal(1, "payload ownership: same-word read/write collision");
end
`endif
endmodule
