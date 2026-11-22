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
endpackage

interface multi_egress_pool_bus(input logic clk);
    import multi_egress_pool_types::*;
    logic sample_valid;
    pool_sample_t sample;

    a_edge_presence: assert property (@(posedge clk)
        sample_valid |-> sample.batch.present == sample.reset_n)
        else $error("POOL_EDGE_PRESENCE");
endinterface
