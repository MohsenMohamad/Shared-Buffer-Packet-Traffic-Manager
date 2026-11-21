package tm_multi_fixed;
    localparam int PRIMARY = 0;
    localparam int SMALL = 1;
    localparam int MIN_FRAME_BYTES = 60;
    localparam int CLASS_COUNT = 4;
    localparam int RX_CAPTURE_DEPTH = 2;
    localparam int RX_STAGING_CELLS = 4;
    localparam int RX_DISPOSITION_DEPTH = 8;
    localparam int TX_PREFETCH_CELLS = 6;
    localparam int TX_FRAME_SLOTS = 2;
    localparam int BIND_REMAINING_BEATS = 16;
    localparam int MIN_QUANTUM = 64;
    localparam int MAX_QUANTUM = 4096;
    localparam int MAX_ALPHA = 4096;
    localparam int ALPHA_FRACTION_BITS = 8;
    localparam int RATE_FRACTION_BITS = 16;
    localparam logic [31:0] MAX_RATE = 32'h0008_0000;

    typedef enum logic [2:0] {
        COMMITTED = 3'd0, BAD_ROUTE = 3'd1, BAD_LENGTH = 3'd2,
        QUEUE_LIMIT = 3'd3, NO_DESCRIPTOR = 3'd4, NO_CELLS = 3'd5,
        FRAME_ERROR = 3'd6
    } disposition_code_t;

    typedef enum logic [1:0] {
        PURE_DRR = 2'd0, PACKET_RR = 2'd1, STRICT_DRR = 2'd2
    } schedule_mode_t;

    typedef enum logic [1:0] {
        GRANT = 2'd0, REJECT = 2'd1, WAIT_PENDING = 2'd2
    } admission_result_t;

    typedef logic [63:0] epoch_t;
    typedef logic [63:0] frame_sequence_t;
    typedef logic [15:0] opaque_tag_t;

    typedef struct packed {
        logic [63:0] data;
        logic [7:0] keep;
        logic last;
    } stream_beat_t;

    typedef struct packed {
        logic [15:0] length;
        logic [7:0] destination;
        logic [7:0] traffic_class;
        opaque_tag_t tag_value;
        logic [1:0] original_ecn;
    } ingress_metadata_t;

    typedef struct packed {
        logic valid;
        stream_beat_t beat;
        ingress_metadata_t metadata;
    } ingress_t;

    typedef struct packed {
        logic valid;
        disposition_code_t code;
        logic [15:0] length;
        logic [7:0] destination;
        logic [7:0] traffic_class;
        opaque_tag_t tag_value;
    } disposition_t;
endpackage
