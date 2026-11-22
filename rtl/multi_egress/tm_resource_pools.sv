// Component boundary. Queue policy and current-epoch owner validation belong to the caller.
module tm_resource_pools #(
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
    output cell_count_t [N_Q-1:0] held
);
`include "tm_multi_validate.svh"

    logic [N_TX:0] cell_present, desc_present, release_present;
    cell_id_t [N_TX:0] return_cell;
    desc_id_t [N_TX:0] return_desc;
    qid_t [N_TX:0] release_qid;
    cell_count_t [N_TX:0] release_cells;
    desc_id_t [N_RX-1:0] rank_id;
    rx_id_t [N_RX-1:0] grant_rank;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) ready <= 1'b0;
        else ready <= 1'b1;
    end

    // A materialization consumes an existing staged reservation. Same-edge
    // grants and returns do not enter this eligibility path.
    assign reserved_free = free_cells - unreserved;

    for (genvar lane = 0; lane < N_TX; lane++) begin : g_tx
        assign cell_present[lane] = tx_present[lane];
        assign desc_present[lane] = tx_present[lane] && tx_final[lane];
        assign release_present[lane] = tx_present[lane];
        assign return_cell[lane] = tx_cell[lane];
        assign return_desc[lane] = tx_desc[lane];
        assign release_qid[lane] = tx_qid[lane];
        assign release_cells[lane] = cell_count_t'(1);
    end

    assign cell_present[N_TX] = cleanup_present && cleanup_has_cell;
    assign desc_present[N_TX] = cleanup_present && cleanup_done;
    assign release_present[N_TX] = desc_present[N_TX];
    assign return_cell[N_TX] = cleanup_cell;
    assign return_desc[N_TX] = cleanup_desc;
    assign release_qid[N_TX] = cleanup_qid;
    assign release_cells[N_TX] = cleanup_released;

    for (genvar lane = 0; lane < N_RX; lane++) begin : g_grant_id
        assign grant_desc[lane] = rank_id[grant_rank[lane]];
    end

    tm_cell_pool #(.PROFILE(PROFILE), .MEM_RD_LATENCY(MEM_RD_LATENCY)) cells (
        .clk, .rst_n, .ready, .write_offer, .reserved_available(free_cells != unreserved),
        .return_present(cell_present), .return_cell, .write_accept, .write_id,
        .free_count(free_cells)
    );

    tm_descriptor_pool #(.PROFILE(PROFILE), .MEM_RD_LATENCY(MEM_RD_LATENCY)) descriptors (
        .clk, .rst_n, .ready, .grant, .return_present(desc_present), .return_desc,
        .rank_id, .free_count(free_desc)
    );

    tm_reservation_accounting #(.PROFILE(PROFILE), .MEM_RD_LATENCY(MEM_RD_LATENCY)) accounting (
        .clk, .rst_n, .ready, .reserve_offer, .free_desc, .reserve_cells, .reserve_qid,
        .release_present, .release_cells, .release_qid, .grant, .grant_rank, .unreserved, .held
    );
endmodule
