// Scoped parameter-dependent types, declared before ANSI port use.
// TM_ANSI_TYPES selects commas for a parameter list; body inclusion uses
// semicolons. One definition serves RTL, formal harnesses and monitor packages.
`ifdef TM_ANSI_TYPES
`define TM_TYPE_END ,
`else
import tm_fixed::*;
`define TM_TYPE_END ;
`endif
localparam integer RX_ID_W=(N_RX>1 ? $clog2(N_RX) : 1) `TM_TYPE_END
localparam integer Q_ID_W=(N_Q>1 ? $clog2(N_Q) : 1) `TM_TYPE_END
localparam integer WORD_OFF_W=(CELL_BYTES/8>1 ? $clog2(CELL_BYTES/8) : 1) `TM_TYPE_END
localparam integer ADDR_W=(N_CELL*CELL_BYTES/8>1 ? $clog2(N_CELL*CELL_BYTES/8) : 1) `TM_TYPE_END
localparam type cell_id_t = logic [CELL_ID_W-1:0] `TM_TYPE_END
localparam type desc_id_t = logic [DESC_ID_W-1:0] `TM_TYPE_END
localparam type cell_count_t = logic [CELL_COUNT_W-1:0] `TM_TYPE_END
localparam type desc_count_t = logic [DESC_COUNT_W-1:0] `TM_TYPE_END
localparam type deficit_t = logic [DEFICIT_W-1:0] `TM_TYPE_END
localparam type qid_t = logic [Q_ID_W-1:0] `TM_TYPE_END
localparam type port_id_t = logic [RX_ID_W-1:0] `TM_TYPE_END
localparam type beat_t = struct packed {
    logic [DATA_W-1:0] data;
    logic [DATA_W/8-1:0] keep;
    logic last;
    logic [63:0] user;
} `TM_TYPE_END
localparam type descriptor_t = struct packed {
    cell_id_t head;
    cell_count_t ncell;
    logic [15:0] length;
    qid_t qid;
    logic [15:0] tag;
    port_id_t source;
} `TM_TYPE_END
localparam type rx_context_t = struct packed {
    rx_phase_t phase;
    logic [7:0] qid;
    logic [15:0] length;
    logic [15:0] tag;
    desc_id_t desc;
    cell_id_t head;
    cell_id_t tail;
    cell_count_t allocated;
    cell_count_t reserved;
    logic [15:0] beat_number;
    logic [WORD_OFF_W-1:0] word_offset;
    logic drain_done;
    logic cleanup_done;
} `TM_TYPE_END
localparam type service_t = struct packed {
    logic valid;
    port_id_t source;
    beat_t beat;
    logic sop;
} `TM_TYPE_END
localparam type admission_t = struct packed {
    logic valid;
    port_id_t source;
    logic [7:0] qid;
    logic [15:0] tag;
    logic [15:0] length;
    cell_count_t ncell;
    logic accept;
    status_code_t reason;
    desc_id_t desc;
} `TM_TYPE_END
localparam type commit_t = struct packed {
    logic valid;
    desc_id_t desc;
    qid_t qid;
    descriptor_t info;
} `TM_TYPE_END
localparam type dispatch_t = struct packed {
    logic valid;
    qid_t qid;
    desc_id_t desc;
    descriptor_t info;
} `TM_TYPE_END
localparam type desc_return_t = struct packed {
    logic valid;
    desc_id_t desc;
} `TM_TYPE_END
localparam type cell_alloc_t = struct packed {
    logic valid;
    cell_id_t id;
    desc_id_t desc;
} `TM_TYPE_END
localparam type cell_return_t = struct packed {
    logic valid;
    cell_id_t id;
    logic abort_source;
    qid_t qid;
    desc_id_t desc;
} `TM_TYPE_END
localparam type abort_mark_t = struct packed {
    logic valid;
    port_id_t source;
    desc_id_t desc;
    qid_t qid;
    cell_id_t head;
    cell_count_t allocated;
    cell_count_t reserved;
} `TM_TYPE_END
localparam type abort_done_t = struct packed {
    logic valid;
    port_id_t source;
    desc_id_t desc;
    qid_t qid;
    cell_count_t ncell;
} `TM_TYPE_END
localparam type tx_done_t = struct packed {
    logic valid;
    desc_id_t desc;
    qid_t qid;
    logic [15:0] length;
} `TM_TYPE_END
localparam type ram_write_t = struct packed {
    logic valid;
    logic [ADDR_W-1:0] addr;
    logic [DATA_W-1:0] data;
} `TM_TYPE_END
localparam type ram_read_t = struct packed {
    logic valid;
    logic [ADDR_W-1:0] addr;
} `TM_TYPE_END
localparam type ram_response_t = struct packed {
    logic valid;
    logic [DATA_W-1:0] data;
} `TM_TYPE_END
localparam type cell_link_write_t = struct packed {
    logic valid;
    cell_id_t id;
    cell_id_t next_id;
} `TM_TYPE_END
localparam type desc_link_write_t = struct packed {
    logic valid;
    desc_id_t id;
    desc_id_t next_id;
} `TM_TYPE_END
localparam type desc_write_t = struct packed {
    logic valid;
    desc_id_t id;
    descriptor_t info;
} `TM_TYPE_END
localparam type config_t = struct packed {
    logic run;
    logic wait_mode;
    logic initialized;
    logic [N_Q*CELL_COUNT_W-1:0] cell_limit;
    logic [N_Q*13-1:0] quantum;
} `TM_TYPE_END
localparam type live_t = struct packed {
    cell_count_t assigned;
    cell_count_t physical_free;
    cell_count_t unreserved;
    cell_count_t reserved_free;
    desc_count_t free_desc;
    logic [N_Q*CELL_COUNT_W-1:0] owned;
    logic [N_Q*DESC_COUNT_W-1:0] queued;
    logic [N_Q*DEFICIT_W-1:0] deficit;
    logic idle;
    logic invariant_error;
} `TM_TYPE_END
localparam type statistics_t = struct packed {
    logic [10*64-1:0] global_counts;
    logic [N_Q*5*64-1:0] queue_counts;
    logic [N_Q*CELL_COUNT_W-1:0] high_water;
} `TM_TYPE_END
localparam type trace_t = struct packed {
    service_t rx_service;
    admission_t admit;
    commit_t commit;
    dispatch_t dispatch;
    cell_alloc_t cell_alloc;
    cell_return_t cell_free;
    abort_mark_t abort_mark;
    abort_done_t abort_done;
    tx_done_t tx_done;
} `TM_TYPE_END
localparam integer BEAT_W=$bits(beat_t) `TM_TYPE_END
localparam integer DESC_INFO_W=$bits(descriptor_t)
`ifndef TM_ANSI_TYPES
;
`endif
`undef TM_TYPE_END
