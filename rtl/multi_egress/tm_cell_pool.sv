module tm_cell_pool #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (
    input  logic clk, rst_n, ready,
    input  logic write_offer, reserved_available,
    input  logic [N_TX:0] return_present,
    input  cell_id_t [N_TX:0] return_cell,
    output logic write_accept,
    output cell_id_t write_id,
    output cell_count_t free_count
);
`include "tm_multi_validate.svh"

    localparam int DELTA_W = CELL_COUNT_W + $clog2(N_TX + 2);
    logic [N_CELL-1:0] free_bits, taken, returned;
    logic any_free;
    // Legal events keep the widened result in [0,N_CELL]. Store the public count width.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [DELTA_W-1:0] free_next;
    /* verilator lint_on UNUSEDSIGNAL */

    tm_pool_first_free #(.SIZE(N_CELL), .GROUP_SIZE(N_CELL >= 32 ? 32 : N_CELL)) selector (
        .available(free_bits), .any_free, .selected(write_id)
    );

    assign write_accept = ready && write_offer && reserved_available && any_free;

    always_comb begin : merge_ownership
        logic [DELTA_W-1:0] return_count;
        taken = '0;
        returned = '0;
        return_count = '0;
        if (write_accept) taken[write_id] = 1'b1;
        // The caller supplies each current owner at most once, in its physical lane.
        for (int lane = 0; lane <= N_TX; lane++) begin
            if (return_present[lane]) begin
                returned[return_cell[lane]] = 1'b1;
                return_count += DELTA_W'(1);
            end
        end
        free_next = DELTA_W'(free_count) + return_count - DELTA_W'(write_accept);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            free_bits <= '1;
            free_count <= cell_count_t'(N_CELL);
        end else if (ready) begin
            free_bits <= (free_bits & ~taken) | returned;
            free_count <= cell_count_t'(free_next);
        end
    end
endmodule
