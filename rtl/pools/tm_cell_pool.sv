module tm_cell_pool_api #(
`include "tm_parameters.svh"
) (clk, rst_n, allocate, release_cell, available_id, free_count, available, invariant_error);
`include "tm_types.svh"
input logic clk, rst_n;
input cell_alloc_t allocate;
input cell_return_t release_cell;
output cell_id_t available_id;
output cell_count_t free_count;
output logic available, invariant_error;
`include "tm_validate.svh"

tm_bitmap_pool #(.CAPACITY(N_CELL), .ID_W(CELL_ID_W), .COUNT_W(CELL_COUNT_W), .RETURNS(1)) pool (
    .clk(clk), .rst_n(rst_n), .alloc_valid(allocate.valid), .alloc_id(allocate.id),
    .return_valid(release_cell.valid), .return_id(release_cell.id),
    .available_id(available_id), .free_count(free_count),
    .available(available), .invariant_error(invariant_error));
endmodule
