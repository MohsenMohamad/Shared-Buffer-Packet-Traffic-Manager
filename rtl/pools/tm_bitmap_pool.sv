// One pre-state allocation and RETURNS independently checked return lanes.
module tm_bitmap_pool #(
    parameter integer CAPACITY=16,
    parameter integer ID_W=(CAPACITY>1 ? $clog2(CAPACITY) : 1),
    parameter integer COUNT_W=$clog2(CAPACITY+1),
    parameter integer RETURNS=1
) (
    input logic clk, rst_n, alloc_valid,
    input logic [ID_W-1:0] alloc_id,
    input logic [RETURNS-1:0] return_valid,
    input logic [RETURNS*ID_W-1:0] return_id,
    output logic [ID_W-1:0] available_id,
    output logic [COUNT_W-1:0] free_count,
    output logic available, invariant_error
);
logic [CAPACITY-1:0] free_bitmap, next_bitmap;
logic [RETURNS-1:0] return_ok;
logic alloc_ok, error_now, found;
localparam integer DELTA_W=COUNT_W+3;
logic signed [DELTA_W-1:0] next_count;
integer lane, earlier;
generate if (CAPACITY<1 || ID_W<1 || ID_W<$clog2(CAPACITY) ||
             COUNT_W<$clog2(CAPACITY+1) || (RETURNS!=1 && RETURNS!=2)) begin : g_invalid
    TM_INVALID_CONFIGURATION invalid_configuration();
end endgenerate
always_comb begin
    available_id = '0;
    found = 1'b0;
    for (integer id=0; id<CAPACITY; id=id+1) begin
        if (free_bitmap[id] && !found) begin
            available_id = ID_W'(id);
            found = 1'b1;
        end
    end
end
assign available = rst_n && found;
always_comb begin
    next_bitmap = free_bitmap;
    next_count = $signed({3'b0,free_count});
    error_now = 1'b0;
    alloc_ok = rst_n && alloc_valid && found && alloc_id==available_id;
    return_ok = '0;
    lane = 0;
    earlier = 0;
    if (rst_n) begin
        if (alloc_valid && !alloc_ok) error_now = 1'b1;
        if (alloc_ok) begin
            next_bitmap[int'(alloc_id)] = 1'b0;
            next_count = next_count - DELTA_W'(1);
        end
        for (lane=0; lane<RETURNS; lane=lane+1) begin
            if (return_valid[lane]) begin
                // Range validation precedes the pre-state ownership lookup.
                if ({1'b0,return_id[lane*ID_W +: ID_W]} < (ID_W+1)'(CAPACITY))
                    return_ok[lane] = !free_bitmap[int'(return_id[lane*ID_W +: ID_W])];
                for (earlier=0; earlier<RETURNS; earlier=earlier+1) begin
                    if (earlier<lane && return_ok[earlier] &&
                        return_id[lane*ID_W +: ID_W]==return_id[earlier*ID_W +: ID_W])
                        return_ok[lane] = 1'b0;
                end
                if (return_ok[lane]) begin
                    next_bitmap[int'(return_id[lane*ID_W +: ID_W])] = 1'b1;
                    next_count = next_count + DELTA_W'(1);
                end else error_now = 1'b1;
            end
        end
    end
end
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        free_bitmap <= '1;
        free_count <= COUNT_W'(CAPACITY);
        invariant_error <= 1'b0;
    end else begin
        free_bitmap <= next_bitmap;
        free_count <= COUNT_W'(next_count);
        invariant_error <= invariant_error || error_now;
    end
end
`ifdef FORMAL
`include "bitmap_properties.svh"
`endif
endmodule
