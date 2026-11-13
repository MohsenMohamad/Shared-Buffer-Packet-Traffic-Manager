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
localparam integer WORDS=N_CELL*CELL_BYTES/8;
logic [63:0] words [WORDS];
ram_response_t pipeline [MEM_RD_LATENCY];

// A request sampled at e is sampled as a response at e+L. Data and valid
// traverse the same L registers; there is no response-ready or reset port.
assign response = pipeline[MEM_RD_LATENCY-1];
always_ff @(posedge clk) begin
    pipeline[0].valid <= read_req.valid;
    if (read_req.valid) pipeline[0].data <= words[read_req.addr];
    for (int i=1; i<MEM_RD_LATENCY; i++) pipeline[i] <= pipeline[i-1];
    if (write_req.valid) words[write_req.addr] <= write_req.data;
end

// Ownership/commit must prohibit the collision. No read-during-write mode
// or simulator scheduling result is part of the data-integrity contract.
always @(posedge clk) begin
    if (read_req.valid) assert (int'(read_req.addr)<WORDS);
    if (write_req.valid) assert (int'(write_req.addr)<WORDS);
    assert (!(read_req.valid && write_req.valid && read_req.addr==write_req.addr));
end
endmodule
