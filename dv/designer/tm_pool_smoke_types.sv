package tm_pool_smoke_types;
    localparam int PROFILE = `TM_POOL_SMOKE_PROFILE;
    localparam int PORTS = PROFILE == tm_multi_fixed::SMALL ? 2 : 4;
    localparam int CELLS = PORTS == 2 ? 16 : 1024;
    localparam int DESCRIPTORS = PORTS == 2 ? 8 : 256;
    localparam int QUEUES = 4 * PORTS;
    localparam int MAX_FRAME_CELLS = PORTS == 2 ? 3 : 24;
    localparam int CELL_W = $clog2(CELLS);
    localparam int DESC_W = $clog2(DESCRIPTORS);
    localparam int COUNT_W = $clog2(CELLS + 1);
    localparam int D_COUNT_W = $clog2(DESCRIPTORS + 1);
    localparam int QUEUE_W = $clog2(QUEUES);

    typedef logic [CELL_W-1:0] cell_t;
    typedef logic [DESC_W-1:0] desc_t;
    typedef logic [COUNT_W-1:0] count_t;
    typedef logic [D_COUNT_W-1:0] desc_count_t;
    typedef logic [QUEUE_W-1:0] qid_t;
    typedef logic [PORTS-1:0] mask_t;
    typedef int token_t;

    typedef struct packed {
        bit present;
        int ingress;
        qid_t qid;
        count_t cells;
        bit first_abort;
        logic [15:0] tag;
    } request_t;

    typedef struct packed {
        int token;
        cell_t address;
        desc_t descriptor;
        bit last;
    } retire_t;

    typedef struct packed {
        int token;
        cell_t address;
        count_t released;
        bit has_cell;
        bit done;
    } cleanup_t;

    typedef struct packed {
        request_t [PORTS-1:0] requests;
        retire_t [PORTS-1:0] tx;
        cleanup_t cleanup;
        int write_token;
        token_t [PORTS-1:0] abort_marks;
        bit blocked_write;
    } batch_t;

    typedef struct packed {
        mask_t commit;
        count_t [PORTS-1:0] cells;
        qid_t [PORTS-1:0] qid;
        bit write_offer;
        mask_t tx_present;
        mask_t tx_final;
        cell_t [PORTS-1:0] tx_cell;
        qid_t [PORTS-1:0] tx_qid;
        desc_t [PORTS-1:0] tx_desc;
        bit cleanup_present;
        bit cleanup_has_cell;
        bit cleanup_done;
        cell_t cleanup_cell;
        qid_t cleanup_qid;
        desc_t cleanup_desc;
        count_t cleanup_released;
    } drive_t;

    typedef struct packed {
        count_t f, u, r;
        desc_count_t d;
        count_t [QUEUES-1:0] h;
    } counts_t;

    localparam counts_t EMPTY = '{f:count_t'(CELLS), u:count_t'(CELLS),
                                 r:'0, d:desc_count_t'(DESCRIPTORS), h:'0};

    typedef struct packed {
        logic ready;
        logic write_accept;
        cell_t write_id;
        mask_t rank_valid;
        desc_t [PORTS-1:0] rank_id;
        desc_t [PORTS-1:0] grant_desc;
        counts_t counts;
    } sample_t;

    typedef struct packed {
        int index;
        bit reset_n;
        batch_t intent;
        drive_t pins;
        sample_t pre, post;
    } pool_edge_t;

    typedef struct packed {
        token_t [PORTS-1:0] tokens;
        int address;
    } result_t;

    typedef enum int {
        D0_RETURN, D1_RETURN, D2_RETURN, D_REUSE, U0_RETURN, F1_EXCHANGE, F0_BLOCK,
        ALL_GRANTS, ALL_RETURNS, HIGH_TX, PARTIAL_CLEANUP, ZERO_CLEANUP,
        SPARSE_TX, PARALLEL_RETURNS, GRANT_RETURN, RESET_FULL, RESET_MIXED,
        DENIED_HOLE, ABSENT_HOLE, PERFECT_DRAIN
    } bin_t;

    function automatic request_t request(int ingress, int qid, int cells, bit abort_first = 0);
        return '{1'b1, ingress, qid_t'(qid), count_t'(cells), abort_first, 16'h1357};
    endfunction
endpackage

interface tm_pool_smoke_if;
    import tm_pool_smoke_types::*;
    bit clk, rst_n = 1;
    drive_t pins;
    batch_t intent;
    wire sample_t sampled;
endinterface
