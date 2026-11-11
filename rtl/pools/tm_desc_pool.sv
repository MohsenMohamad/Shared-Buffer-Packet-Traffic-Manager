module tm_desc_pool_api #(
`include "tm_parameters.svh"
) (clk, rst_n, admit, tx_return, abort_return, available_id, free_count, available, invariant_error);
`include "tm_types.svh"
input logic clk, rst_n;
input admission_t admit;
input desc_return_t tx_return, abort_return;
output desc_id_t available_id;
output desc_count_t free_count;
output logic available, invariant_error;
`include "tm_validate.svh"

tm_bitmap_pool #(.CAPACITY(N_DESC), .ID_W(DESC_ID_W), .COUNT_W(DESC_COUNT_W), .RETURNS(2)) pool (
    .clk(clk), .rst_n(rst_n), .alloc_valid(admit.valid && admit.accept), .alloc_id(admit.desc),
    .return_valid({abort_return.valid,tx_return.valid}),
    .return_id({abort_return.desc,tx_return.desc}),
    .available_id(available_id), .free_count(free_count),
    .available(available), .invariant_error(invariant_error));
endmodule
