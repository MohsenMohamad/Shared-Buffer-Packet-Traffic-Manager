// Isolated address and reservation consumers at the same acceptance edge.
module tm_pools_timing #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (
    input  logic clk, rst_n,
    // Ordered eligible offers. A hole or a denied offer consumes no rank.
    input  logic [N_RX-1:0] reserve_offer,
    input  cell_count_t [N_RX-1:0] reserve_cells,
    input  qid_t [N_RX-1:0] reserve_qid,
    output logic [N_RX-1:0] grant,
    output desc_id_t [N_RX-1:0] grant_desc,

    input  logic write_offer,
    output logic write_accept,
    output cell_id_t write_id,

    // TX lanes identify accepted cell-final beats. Final is meaningful only with present.
    input  logic [N_TX-1:0] tx_present, tx_final,
    input  cell_id_t [N_TX-1:0] tx_cell,
    input  qid_t [N_TX-1:0] tx_qid,
    input  desc_id_t [N_TX-1:0] tx_desc,

    // Cleanup is its own lane. Done releases residual credit and the descriptor together.
    input  logic cleanup_present, cleanup_has_cell, cleanup_done,
    input  cell_id_t cleanup_cell,
    input  qid_t cleanup_qid,
    input  desc_id_t cleanup_desc,
    input  cell_count_t cleanup_released,

    output logic ready,
    output cell_count_t free_cells, unreserved, reserved_free,
    output desc_count_t free_desc,
    output cell_count_t [N_Q-1:0] held,
    output cell_id_t captured_write_id,
    output desc_id_t [N_RX-1:0] captured_grant_desc
);
    tm_resource_pools #(.PROFILE(PROFILE)) dut (
        .clk, .rst_n, .reserve_offer, .reserve_cells, .reserve_qid, .grant, .grant_desc,
        .write_offer, .write_accept, .write_id, .tx_present, .tx_final,
        .tx_cell, .tx_qid, .tx_desc, .cleanup_present, .cleanup_has_cell, .cleanup_done,
        .cleanup_cell, .cleanup_qid, .cleanup_desc, .cleanup_released,
        .ready, .free_cells, .unreserved, .reserved_free, .free_desc, .held
    );

    always_ff @(posedge clk) begin
        if (write_accept) captured_write_id <= write_id;
        for (int lane = 0; lane < N_RX; lane++)
            if (grant[lane]) captured_grant_desc[lane] <= grant_desc[lane];
    end
endmodule
