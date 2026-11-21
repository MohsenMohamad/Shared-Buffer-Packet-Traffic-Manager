package tm_multi_csr;
    localparam logic [1:0] AXI_OKAY = 2'b00;
    localparam logic [1:0] AXI_SLVERR = 2'b10;
    localparam logic [1:0] AXI_DECERR = 2'b11;
    localparam int unsigned INVALID_ADDRESS = 32'hffff_ffff;
    localparam int unsigned ABI_VERSION = 1;

    localparam int unsigned VERSION = 'h0000;
    localparam int unsigned RUN = 'h0004;
    localparam int unsigned STATUS = 'h0008;
    localparam int unsigned ADMISSION = 'h000c;
    localparam int unsigned SNAPSHOT = 'h0010;
    localparam int unsigned LIVE_UNRESERVED = 'h0014;
    localparam int unsigned LIVE_PHYSICAL_FREE = 'h0018;
    localparam int unsigned LIVE_FREE_DESC = 'h001c;
    localparam int unsigned SNAP_UNRESERVED = 'h0020;
    localparam int unsigned SNAP_PHYSICAL_FREE = 'h0024;
    localparam int unsigned SNAP_FREE_DESC = 'h0028;

    localparam logic [31:0] RUN_ENABLE = 32'h1;
    localparam logic [31:0] STATUS_IDLE = 32'h1;
    localparam logic [31:0] STATUS_INITIALIZED = 32'h2;
    localparam logic [31:0] STATUS_SNAPSHOT_VALID = 32'h4;
    localparam logic [31:0] ADMISSION_WAIT = 32'h1;
    localparam logic [31:0] ADMISSION_DYNAMIC = 32'h2;
    localparam logic [31:0] SNAPSHOT_TRIGGER = 32'h1;
    localparam logic [31:0] ENABLE = 32'h1;

    localparam int unsigned QUEUE_BASE = 'h1000;
    localparam int unsigned QUEUE_STRIDE = 'h100;
    localparam int unsigned Q_LIMIT = 'h00;
    localparam int unsigned Q_MINIMUM = 'h04;
    localparam int unsigned Q_ALPHA = 'h08;
    localparam int unsigned Q_QUANTUM = 'h0c;
    localparam int unsigned Q_BUCKET_ENABLE = 'h10;
    localparam int unsigned Q_BUCKET_RATE = 'h14;
    localparam int unsigned Q_BUCKET_CAPACITY = 'h18;
    localparam int unsigned Q_ECN_ENABLE = 'h1c;
    localparam int unsigned Q_ECN_THRESHOLD = 'h20;
    localparam int unsigned Q_LIVE_H = 'h24;
    localparam int unsigned Q_LIVE_DEPTH = 'h28;
    localparam int unsigned Q_LIVE_H_HIGH = 'h2c;
    localparam int unsigned Q_LIVE_DEPTH_HIGH = 'h30;
    localparam int unsigned Q_SNAP_H = 'h34;
    localparam int unsigned Q_SNAP_DEPTH = 'h38;
    localparam int unsigned Q_SNAP_H_HIGH = 'h3c;
    localparam int unsigned Q_SNAP_DEPTH_HIGH = 'h40;
    localparam int unsigned Q_COUNTER = 'h48;
    localparam int unsigned Q_ADMITTED = 0;
    localparam int unsigned Q_PUBLISHED = 1;
    localparam int unsigned Q_BAD_LENGTH = 2;
    localparam int unsigned Q_QUEUE_LIMIT = 3;
    localparam int unsigned Q_NO_DESCRIPTOR = 4;
    localparam int unsigned Q_NO_CELLS = 5;
    localparam int unsigned Q_FRAME_ERROR = 6;
    localparam int unsigned Q_DISPATCHED = 7;
    localparam int unsigned Q_RETIRED_FRAMES = 8;
    localparam int unsigned Q_RETIRED_BYTES = 9;
    localparam int unsigned Q_MARK_REQUESTS = 10;
    localparam int unsigned Q_COUNTER_COUNT = 11;

    localparam int unsigned EGRESS_BASE = 'h2000;
    localparam int unsigned EGRESS_STRIDE = 'h100;
    localparam int unsigned E_MODE = 'h00;
    localparam int unsigned E_STRICT_CLASS = 'h04;
    localparam int unsigned E_BUCKET_ENABLE = 'h08;
    localparam int unsigned E_BUCKET_RATE = 'h0c;
    localparam int unsigned E_BUCKET_CAPACITY = 'h10;
    localparam int unsigned E_COUNTER = 'h18;
    localparam int unsigned E_BEATS = 0;
    localparam int unsigned E_BYTES = 1;
    localparam int unsigned E_FRAMES = 2;
    localparam int unsigned E_STALL = 3;
    localparam int unsigned E_STARVED = 4;
    localparam int unsigned E_COUNTER_COUNT = 5;

    localparam int unsigned INGRESS_BASE = 'h3000;
    localparam int unsigned INGRESS_STRIDE = 'h400;
    localparam int unsigned INGRESS_BUCKET_STRIDE = 'h80;
    localparam int unsigned UNCLASSIFIED = 4;
    localparam int unsigned I_BEATS = 0;
    localparam int unsigned I_BYTES = 1;
    localparam int unsigned I_LAST = 2;
    localparam int unsigned I_ADMITTED = 3;
    localparam int unsigned I_PUBLISHED = 4;
    localparam int unsigned I_BAD_ROUTE = 5;
    localparam int unsigned I_BAD_LENGTH = 6;
    localparam int unsigned I_QUEUE_LIMIT = 7;
    localparam int unsigned I_NO_DESCRIPTOR = 8;
    localparam int unsigned I_NO_CELLS = 9;
    localparam int unsigned I_FRAME_ERROR = 10;
    localparam int unsigned I_COUNTER_COUNT = 11;
    localparam int unsigned COUNTER_STRIDE = 8;
    localparam int unsigned COUNTER_LOW = 0;
    localparam int unsigned COUNTER_HIGH = 4;

    typedef enum logic [2:0] {
        UNMAPPED, CONSTANT_RO, LIVE_RO, SNAPSHOT_RO, RUN_RW, POLICY_RW, TRIGGER_WO
    } access_t;

    typedef struct packed {
        access_t access_kind;
        logic misaligned;
        logic counter_high;
        logic [31:0] write_mask;
        logic [31:0] reset_value;
        logic [31:0] minimum;
        logic [31:0] maximum;
    } register_info_t;

    function automatic int unsigned queue_address(
        int unsigned n_tx, int unsigned egress, int unsigned class_id, int unsigned offset
    );
        if (egress >= n_tx || class_id >= 4 || offset >= QUEUE_STRIDE)
            return INVALID_ADDRESS;
        return QUEUE_BASE + QUEUE_STRIDE * (4 * egress + class_id) + offset;
    endfunction

    function automatic int unsigned egress_address(
        int unsigned n_tx, int unsigned egress, int unsigned offset
    );
        if (egress >= n_tx || offset >= EGRESS_STRIDE)
            return INVALID_ADDRESS;
        return EGRESS_BASE + EGRESS_STRIDE * egress + offset;
    endfunction

    function automatic int unsigned ingress_address(
        int unsigned n_rx, int unsigned ingress, int unsigned bucket, int unsigned offset
    );
        if (ingress >= n_rx || bucket > UNCLASSIFIED || offset >= INGRESS_BUCKET_STRIDE)
            return INVALID_ADDRESS;
        return INGRESS_BASE + INGRESS_STRIDE * ingress + INGRESS_BUCKET_STRIDE * bucket + offset;
    endfunction

    function automatic register_info_t register_word(
        access_t kind, logic [31:0] mask = 0, logic [31:0] default_value = 0,
        logic [31:0] min_value = 0, logic [31:0] max_value = 0
    );
        return '{kind, 1'b0, 1'b0, mask, default_value, min_value, max_value};
    endfunction

    function automatic register_info_t counter_word(int unsigned offset);
        register_info_t info;
        info = register_word(SNAPSHOT_RO);
        info.counter_high = offset[2];
        return info;
    endfunction

    function automatic register_info_t queue_word(
        int unsigned offset, int unsigned cell_count, int unsigned frame_max
    );
        case (offset)
            Q_LIMIT: return register_word(POLICY_RW, 32'h7ff, cell_count, 0, cell_count);
            Q_MINIMUM: return register_word(POLICY_RW, 32'h7ff, 0, 0, cell_count);
            Q_ALPHA: return register_word(POLICY_RW, 32'h1fff, 0, 0, tm_multi_fixed::MAX_ALPHA);
            Q_QUANTUM: return register_word(POLICY_RW, 32'h1fff, frame_max,
                                           tm_multi_fixed::MIN_QUANTUM, tm_multi_fixed::MAX_QUANTUM);
            Q_BUCKET_ENABLE, Q_ECN_ENABLE: return register_word(POLICY_RW, ENABLE, 0, 0, 1);
            Q_BUCKET_RATE: return register_word(POLICY_RW, 32'hf_ffff,
                                                tm_multi_fixed::MAX_RATE, 0, tm_multi_fixed::MAX_RATE);
            Q_BUCKET_CAPACITY: return register_word(POLICY_RW, 32'hffff, frame_max, 0, 65535);
            Q_ECN_THRESHOLD: return register_word(POLICY_RW, 32'h7ff, 1, 1, cell_count);
            Q_LIVE_H, Q_LIVE_DEPTH, Q_LIVE_H_HIGH, Q_LIVE_DEPTH_HIGH: return register_word(LIVE_RO);
            Q_SNAP_H, Q_SNAP_DEPTH, Q_SNAP_H_HIGH, Q_SNAP_DEPTH_HIGH: return register_word(SNAPSHOT_RO);
            default: begin
                if (offset >= Q_COUNTER && offset < Q_COUNTER + COUNTER_STRIDE * Q_COUNTER_COUNT)
                    return counter_word(offset - Q_COUNTER);
                return register_word(UNMAPPED);
            end
        endcase
    endfunction

    function automatic register_info_t egress_word(int unsigned offset, int unsigned frame_max);
        case (offset)
            E_MODE: return register_word(POLICY_RW, 32'h3, 0, 0, 2);
            E_STRICT_CLASS: return register_word(POLICY_RW, 32'h3, 0, 0, 3);
            E_BUCKET_ENABLE: return register_word(POLICY_RW, ENABLE, 0, 0, 1);
            E_BUCKET_RATE: return register_word(POLICY_RW, 32'hf_ffff,
                                                tm_multi_fixed::MAX_RATE, 0, tm_multi_fixed::MAX_RATE);
            E_BUCKET_CAPACITY: return register_word(POLICY_RW, 32'hffff, frame_max, 0, 65535);
            default: begin
                if (offset >= E_COUNTER && offset < E_COUNTER + COUNTER_STRIDE * E_COUNTER_COUNT)
                    return counter_word(offset - E_COUNTER);
                return register_word(UNMAPPED);
            end
        endcase
    endfunction

    function automatic register_info_t decode(
        int unsigned address, int unsigned n_rx, int unsigned n_tx,
        int unsigned cell_count, int unsigned frame_max
    );
        int unsigned aligned_address, offset;
        register_info_t info;
        aligned_address = address & 32'hffff_fffc;
        case (aligned_address)
            VERSION: info = register_word(CONSTANT_RO, 0, ABI_VERSION);
            RUN: info = register_word(RUN_RW, RUN_ENABLE, 0, 0, 1);
            STATUS, LIVE_UNRESERVED, LIVE_PHYSICAL_FREE, LIVE_FREE_DESC: info = register_word(LIVE_RO);
            ADMISSION: info = register_word(POLICY_RW, ADMISSION_WAIT | ADMISSION_DYNAMIC, 0, 0, 3);
            SNAPSHOT: info = register_word(TRIGGER_WO, SNAPSHOT_TRIGGER, 0, 0, 1);
            SNAP_UNRESERVED, SNAP_PHYSICAL_FREE, SNAP_FREE_DESC: info = register_word(SNAPSHOT_RO);
            default: begin
                info = register_word(UNMAPPED);
                if (aligned_address >= QUEUE_BASE &&
                    aligned_address < QUEUE_BASE + QUEUE_STRIDE * 4 * n_tx)
                    info = queue_word((aligned_address - QUEUE_BASE) % QUEUE_STRIDE,
                                      cell_count, frame_max);
                else if (aligned_address >= EGRESS_BASE &&
                         aligned_address < EGRESS_BASE + EGRESS_STRIDE * n_tx)
                    info = egress_word((aligned_address - EGRESS_BASE) % EGRESS_STRIDE, frame_max);
                else if (aligned_address >= INGRESS_BASE &&
                         aligned_address < INGRESS_BASE + INGRESS_STRIDE * n_rx) begin
                    offset = (aligned_address - INGRESS_BASE) % INGRESS_STRIDE;
                    if (offset / INGRESS_BUCKET_STRIDE <= UNCLASSIFIED &&
                        offset % INGRESS_BUCKET_STRIDE < COUNTER_STRIDE * I_COUNTER_COUNT)
                        info = counter_word(offset % INGRESS_BUCKET_STRIDE);
                end
            end
        endcase
        info.misaligned = info.access_kind != UNMAPPED && address[1:0] != 0;
        return info;
    endfunction

    function automatic logic [31:0] snapshot_counter_word(logic [63:0] count, logic high_word);
        return high_word ? count[63:32] : count[31:0];
    endfunction
endpackage
