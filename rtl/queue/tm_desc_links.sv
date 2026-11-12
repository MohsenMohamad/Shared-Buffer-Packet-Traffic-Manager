// Metadata-owned production child. P05 instantiates this same array once.
module tm_desc_links import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input desc_link_write_t write_req,
    input desc_id_t read_id,
    output desc_id_t read_next
);
`include "tm_validate.svh"
desc_id_t next_ids [N_DESC];
// No reset or write-through: only links between live queued entries matter.
assign read_next = int'(read_id)<N_DESC ? next_ids[read_id] : '0;
always_ff @(posedge clk) begin
    if (write_req.valid && int'(write_req.id)<N_DESC)
        next_ids[write_req.id] <= write_req.next_id;
end
endmodule
