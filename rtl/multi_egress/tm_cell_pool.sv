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
`ifdef TM_POOL_ASSERTIONS
    always @(posedge clk) begin : check_cell_contract
        logic [N_CELL-1:0] seen;
        if (ready) begin
            assert_cell_population: assert ($countones(free_bits) == int'(free_count))
                else $fatal(1, "POOL_ASSERT cell_population");
            assert_write_old_free: assert (!write_accept || (reserved_available && free_bits[write_id]))
                else $fatal(1, "POOL_ASSERT write_old_free");

            seen = '0;
            for (int lane = 0; lane <= N_TX; lane++) begin
                if (return_present[lane]) begin
                    assert_cell_return_allocated: assert (!free_bits[return_cell[lane]])
                        else $fatal(1, "POOL_ASSERT cell_return_allocated");
                    assert_cell_return_distinct: assert (!seen[return_cell[lane]])
                        else $fatal(1, "POOL_ASSERT cell_return_distinct");
                    seen[return_cell[lane]] = 1'b1;
                end
            end
            assert_cell_delta_bounds: assert (free_next <= DELTA_W'(N_CELL))
                else $fatal(1, "POOL_ASSERT cell_delta_bounds");
        end
    end

    // Sample the edge's widened result and compare the stored count at the next active edge.
    cell_count_t expected_free_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) expected_free_count <= cell_count_t'(N_CELL);
        else if (ready) begin
            assert_cell_update: assert (free_count == expected_free_count)
                else $fatal(1, "POOL_ASSERT cell_update");
            expected_free_count <= cell_count_t'(free_next);
        end
    end
`endif
endmodule
