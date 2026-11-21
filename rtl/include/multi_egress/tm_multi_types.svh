// Include in an ANSI parameter list or a module/package body.
`ifdef TM_MULTI_ANSI_TYPES
`define TM_MULTI_TYPE_END ,
`else
`define TM_MULTI_TYPE_END ;
`endif

localparam int N_Q = N_TX * N_CLASS `TM_MULTI_TYPE_END
localparam int RX_ID_W = N_RX > 1 ? $clog2(N_RX) : 1 `TM_MULTI_TYPE_END
localparam int TX_ID_W = N_TX > 1 ? $clog2(N_TX) : 1 `TM_MULTI_TYPE_END
localparam int Q_ID_W = N_Q > 1 ? $clog2(N_Q) : 1 `TM_MULTI_TYPE_END
localparam int CELL_ID_W = N_CELL > 1 ? $clog2(N_CELL) : 1 `TM_MULTI_TYPE_END
localparam int DESC_ID_W = N_DESC > 1 ? $clog2(N_DESC) : 1 `TM_MULTI_TYPE_END
localparam int CELL_COUNT_W = N_CELL > 0 ? $clog2(N_CELL + 1) : 1 `TM_MULTI_TYPE_END
localparam int DESC_COUNT_W = N_DESC > 0 ? $clog2(N_DESC + 1) : 1 `TM_MULTI_TYPE_END
localparam int DEFICIT_W = MAX_FRAME_BYTES > 0 ?
    $clog2(tm_multi_fixed::MAX_QUANTUM + MAX_FRAME_BYTES) : 1 `TM_MULTI_TYPE_END
localparam type rx_id_t = logic [RX_ID_W-1:0] `TM_MULTI_TYPE_END
localparam type tx_id_t = logic [TX_ID_W-1:0] `TM_MULTI_TYPE_END
localparam type qid_t = logic [Q_ID_W-1:0] `TM_MULTI_TYPE_END
localparam type cell_id_t = logic [CELL_ID_W-1:0] `TM_MULTI_TYPE_END
localparam type desc_id_t = logic [DESC_ID_W-1:0] `TM_MULTI_TYPE_END
localparam type cell_count_t = logic [CELL_COUNT_W-1:0] `TM_MULTI_TYPE_END
localparam type desc_count_t = logic [DESC_COUNT_W-1:0] `TM_MULTI_TYPE_END
localparam type deficit_t = logic [DEFICIT_W-1:0] `TM_MULTI_TYPE_END
localparam type class_id_t = logic [1:0] `TM_MULTI_TYPE_END
localparam type cell_payload_t = logic [CELL_W-1:0] `TM_MULTI_TYPE_END

localparam type egress_t = struct packed {
    logic valid;
    tm_multi_fixed::stream_beat_t beat;
    rx_id_t source;
    tx_id_t destination;
    class_id_t traffic_class;
    logic [15:0] length;
    tm_multi_fixed::opaque_tag_t tag_value;
    logic [1:0] original_ecn;
    logic mark_request;
} `TM_MULTI_TYPE_END

localparam type frame_id_t = struct packed {
    tm_multi_fixed::epoch_t epoch;
    rx_id_t source;
    tm_multi_fixed::frame_sequence_t sequence_number;
} `TM_MULTI_TYPE_END
localparam type owner_t = struct packed {
    frame_id_t frame;
    qid_t qid;
    desc_id_t desc;
    tm_multi_fixed::opaque_tag_t tag_value;
} `TM_MULTI_TYPE_END

localparam type read_tag_t = struct packed {
    owner_t owner;
    tx_id_t destination;
    cell_count_t cell_index;
} `TM_MULTI_TYPE_END
localparam type memory_read_t = struct packed {
    logic valid;
    read_tag_t tag_value;
    cell_id_t address;
} `TM_MULTI_TYPE_END
localparam type memory_write_t = struct packed {
    logic valid;
    cell_id_t address;
    cell_payload_t data;
} `TM_MULTI_TYPE_END
localparam type memory_response_t = struct packed {
    logic valid;
    read_tag_t tag_value;
    cell_id_t address;
    cell_payload_t data;
} `TM_MULTI_TYPE_END

localparam type ingress_service_t = struct packed {
    logic present;
    frame_id_t frame;
    logic first;
    logic discard;
    tm_multi_fixed::stream_beat_t beat;
} `TM_MULTI_TYPE_END
localparam type admission_t = struct packed {
    logic present;
    frame_id_t frame;
    tm_multi_fixed::ingress_metadata_t metadata;
    tm_multi_fixed::admission_result_t result;
    tm_multi_fixed::disposition_code_t reason;
    logic qid_valid;
    qid_t qid;
    cell_count_t requested;
    desc_id_t desc;
} `TM_MULTI_TYPE_END
localparam type cell_write_event_t = struct packed {
    logic present;
    owner_t owner;
    cell_count_t cell_index;
    cell_id_t address;
    logic final_cell;
} `TM_MULTI_TYPE_END
localparam type publication_t = struct packed {
    logic present;
    owner_t owner;
    cell_id_t head;
    cell_count_t cells;
    logic [15:0] length;
    logic [1:0] original_ecn;
    logic mark_request;
} `TM_MULTI_TYPE_END
localparam type dispatch_t = struct packed {
    logic present;
    owner_t owner;
    logic [15:0] length;
} `TM_MULTI_TYPE_END
localparam type egress_service_t = struct packed {
    logic present;
    owner_t owner;
    cell_id_t address;
    logic cell_last;
    logic frame_last;
} `TM_MULTI_TYPE_END
localparam type read_issue_t = struct packed {
    memory_read_t command;
    logic next_valid;
    cell_id_t next_cell;
} `TM_MULTI_TYPE_END
localparam type read_response_event_t = struct packed {
    memory_read_t identity;
    logic accepted_epoch;
} `TM_MULTI_TYPE_END
localparam type abort_mark_t = struct packed {
    logic present;
    owner_t owner;
    cell_count_t reserved;
} `TM_MULTI_TYPE_END
localparam type cleanup_t = struct packed {
    logic present;
    owner_t owner;
    logic done;
    cell_count_t released;
} `TM_MULTI_TYPE_END
localparam type cell_return_t = struct packed {
    logic present;
    owner_t owner;
    cell_id_t address;
} `TM_MULTI_TYPE_END
localparam type descriptor_return_t = struct packed {
    logic present;
    owner_t owner;
} `TM_MULTI_TYPE_END

localparam type ingress_ports_t = tm_multi_fixed::ingress_t [N_RX-1:0] `TM_MULTI_TYPE_END
localparam type egress_ports_t = egress_t [N_TX-1:0] `TM_MULTI_TYPE_END
localparam type disposition_ports_t = tm_multi_fixed::disposition_t [N_RX-1:0] `TM_MULTI_TYPE_END
localparam type ingress_services_t = ingress_service_t [N_RX-1:0] `TM_MULTI_TYPE_END
localparam type admissions_t = admission_t [N_RX-1:0] `TM_MULTI_TYPE_END
localparam type abort_marks_t = abort_mark_t [N_RX-1:0] `TM_MULTI_TYPE_END
localparam type dispatches_t = dispatch_t [N_TX-1:0] `TM_MULTI_TYPE_END
localparam type egress_services_t = egress_service_t [N_TX-1:0] `TM_MULTI_TYPE_END
localparam type cell_returns_t = cell_return_t [N_TX:0] `TM_MULTI_TYPE_END
localparam type descriptor_returns_t = descriptor_return_t [N_TX:0] `TM_MULTI_TYPE_END
localparam type edge_batch_t = struct packed {
    logic present;
    tm_multi_fixed::epoch_t epoch;
    ingress_services_t ingress_service;
    admissions_t admission;
    cell_write_event_t cell_write;
    publication_t publication;
    dispatches_t dispatch;
    egress_services_t egress_service;
    read_issue_t read_issue;
    read_response_event_t read_response;
    abort_marks_t abort_mark;
    cleanup_t cleanup;
    cell_returns_t cell_return;
    descriptor_returns_t descriptor_return;
}
`ifndef TM_MULTI_ANSI_TYPES
;
`endif
`undef TM_MULTI_TYPE_END
