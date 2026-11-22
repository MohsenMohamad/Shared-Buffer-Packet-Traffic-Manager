package multi_egress_pool_types;
    localparam int N_RX = `POOL_PORTS;
    localparam int N_TX = N_RX;
    localparam int N_CLASS = tm_multi_fixed::CLASS_COUNT;
    localparam int N_CELL = N_RX == 4 ? 1024 : 16;
    localparam int N_DESC = N_RX == 4 ? 256 : 8;
    localparam int CELL_W = 512;
    localparam int MAX_FRAME_BYTES = N_RX == 4 ? 1536 : 192;
    `include "tm_multi_types.svh"

    typedef struct packed {
        int unsigned physical_free;
        int unsigned unreserved;
        int unsigned reserved_free;
        int unsigned assigned;
        int unsigned descriptor_free;
        logic [N_Q-1:0][31:0] queue_credit;
    } pool_counts_t;

    typedef struct packed {
        bit reset_n;
        bit initialized;
        int unsigned origin;
        int edge_number;
        edge_batch_t batch;
        pool_counts_t counts;
    } pool_sample_t;

    function automatic bit activity(edge_batch_t batch);
        if (batch.cell_write.present || batch.publication.present || batch.cleanup.present)
            return 1;
        for (int lane = 0; lane < N_RX; ++lane)
            if (batch.admission[lane].present || batch.abort_mark[lane].present)
                return 1;
        for (int lane = 0; lane < N_TX; ++lane)
            if (batch.dispatch[lane].present || batch.egress_service[lane].present)
                return 1;
        return 0;
    endfunction
    function automatic bit has_events(edge_batch_t batch);
        if (activity(batch) || batch.read_issue.command.valid || batch.read_response.identity.valid)
            return 1;
        for (int lane = 0; lane < N_RX; ++lane)
            if (batch.ingress_service[lane].present)
                return 1;
        for (int lane = 0; lane <= N_TX; ++lane)
            if (batch.cell_return[lane].present || batch.descriptor_return[lane].present)
                return 1;
        return 0;
    endfunction
endpackage

interface multi_egress_pool_bus(input logic clk);
    import multi_egress_pool_types::*;
    logic sample_valid;
    pool_sample_t sample;

    a_edge_presence: assert property (@(posedge clk)
        sample_valid |-> sample.batch.present == sample.reset_n)
        else $error("POOL_EDGE_PRESENCE");
endinterface

`ifdef POOL_CANDIDATE
interface pool_candidate_bus(input logic clk);
    import multi_egress_pool_types::*;
    typedef logic [N_TX:0] return_lanes_t;

    logic rst_n, ready;
    logic [N_RX-1:0] reserve_commit, rank_valid;
    cell_count_t [N_RX-1:0] reserve_cells;
    qid_t [N_RX-1:0] reserve_qid;
    desc_id_t [N_RX-1:0] rank_id, grant_desc;
    logic write_offer, write_accept;
    cell_id_t write_id;
    logic [N_TX-1:0] tx_present, tx_final;
    desc_id_t [N_TX-1:0] tx_desc;
    cell_id_t [N_TX-1:0] tx_cell;
    qid_t [N_TX-1:0] tx_qid;
    logic cleanup_present, cleanup_has_cell, cleanup_done;
    cell_id_t cleanup_cell;
    desc_id_t cleanup_desc;
    qid_t cleanup_qid;
    cell_count_t cleanup_released;

    return_lanes_t cell_present, desc_present, release_present;
    cell_id_t [N_TX:0] return_cell;
    desc_id_t [N_TX:0] return_desc;
    qid_t [N_TX:0] release_qid;
    cell_count_t [N_TX:0] release_cells;
    cell_count_t free_cells, unreserved, reserved_free;
    desc_count_t free_desc;
    cell_count_t [N_Q-1:0] held;
    logic [N_CELL-1:0] cell_free;
    logic [N_DESC-1:0] desc_free;
endinterface
`endif
