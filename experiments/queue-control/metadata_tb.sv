module metadata_tb #(
    parameter int P = 4, N_CELL = 1024, N_DESC = 256
);
    localparam int Q = P * 4, QB = $clog2(Q), B = $clog2(P);
    localparam int C = $clog2(N_CELL), D = $clog2(N_DESC);
    localparam int W = C + 5 + B + 64 + 16 + 2 + 1 + 16;
    logic clk = 0, rst_n = 1;

    logic publish;
    logic [QB-1:0] publish_q;
    logic [D-1:0] publish_desc;
    logic [W-1:0] publish_info;
    logic [P-1:0] bind_window;
    logic [Q-1:0][15:0] queue_credit_bytes;
    logic [P-1:0][15:0] port_credit_bytes;
    typedef struct packed {
        logic [Q-1:0] active;
        logic [P-1:0] bound;
        logic [P-1:0][1:0] bound_class;
        logic [P-1:0][D-1:0] bound_desc;
        logic [P-1:0][W-1:0] bound_info;
        logic error_flag;
    } queue_result_t;
    queue_result_t queue_result[2];

    for (genvar version = 0; version < 2; version++) begin : head_variant
        queue_head #(.P(P), .N_CELL(N_CELL), .N_DESC(N_DESC), .CACHED(version)) dut (
            .clk, .rst_n, .publish, .publish_q, .publish_desc, .publish_info,
            .bind_window, .queue_credit_bytes, .port_credit_bytes,
            .active(queue_result[version].active), .bound(queue_result[version].bound),
            .bound_class(queue_result[version].bound_class),
            .bound_desc(queue_result[version].bound_desc),
            .bound_info(queue_result[version].bound_info),
            .invariant_error(queue_result[version].error_flag)
        );
    end

    logic [P-1:0] staged_valid, staged_final, previous_valid;
    logic [P-1:0][C-1:0] previous_cell;
    logic [P-1:0][D-1:0] staged_desc;
    logic [P-1:0] read_eligible, read_more;
    logic [P-1:0][C-1:0] read_cell;
    logic [P-1:0][D-1:0] read_desc;
    logic [P-1:0] abort_valid, abort_has_cell, abort_more;
    logic [P-1:0][C-1:0] abort_cell;
    logic [P-1:0][D-1:0] abort_desc;
    logic [P-1:0] tx_return;
    logic [P-1:0][C-1:0] tx_return_cell;
    logic [P-1:0][D-1:0] tx_return_desc;
    logic write_valid, final_write, issue_valid, cleanup_valid, cleanup_done;
    logic [B-1:0] write_port, issue_port, cleanup_port;
    logic [C-1:0] write_addr, payload_read_addr, tx_successor, abort_successor;
    logic [D-1:0] write_owner;
    logic cell_error;

    cell_control #(.P(P), .N_CELL(N_CELL), .N_DESC(N_DESC)) cell_dut (
        .clk, .rst_n, .staged_valid, .staged_final, .previous_valid, .previous_cell, .staged_desc,
        .read_eligible, .read_more, .read_cell, .read_desc,
        .abort_valid, .abort_has_cell, .abort_more, .abort_cell, .abort_desc,
        .tx_return, .tx_return_cell, .tx_return_desc,
        .write_valid, .final_write, .issue_valid, .cleanup_valid, .cleanup_done,
        .write_port, .issue_port, .cleanup_port, .write_addr, .payload_read_addr,
        .tx_successor, .abort_successor, .write_owner, .invariant_error(cell_error)
    );

    task automatic tick;
        #5;
        clk = 1;
        #1;
        if (queue_result[0] !== queue_result[1] || queue_result[0].error_flag)
            $fatal(1, "Head/cache/bitmap diverged at %0t", $time);
        if (cell_error)
            $fatal(1, "Legal physical-cell ownership raised an error at %0t", $time);
        #4;
        clk = 0;
    endtask

    function automatic logic [W-1:0] info(input int id);
        return (W'(1) << (W - 1 - id)) | W'(60 + id);
    endfunction

    task automatic append_head(input int q, input int id);
        publish = 1;
        publish_q = QB'(q);
        publish_desc = D'(id);
        publish_info = info(id);
    endtask

    task automatic expect_bound(input int port, input int id);
        if (!queue_result[0].bound[port] || queue_result[0].bound_desc[port] != D'(id)
            || queue_result[0].bound_info[port] != info(id))
            $fatal(1, "Incorrect bound record on egress %0d, expected descriptor %0d", port, id);
    endtask

    task automatic queue_overlap;
        append_head(0, 0);
        bind_window = '1;
        tick();
        if (queue_result[0].bound != '0) $fatal(1, "Empty queue dispatched its same-edge publication");
        bind_window = '0;
        append_head(0, 1);
        tick();
        for (int p = 1; p < P; p++) begin
            append_head(4*p, p+1);
            tick();
        end
        append_head(0, P+1);
        bind_window = '1;
        tick();
        expect_bound(0, 0);
        for (int p = 1; p < P; p++) expect_bound(p, p+1);
        if (queue_result[0].active != Q'(1)) $fatal(1, "Invalid active bitmap after all egresses pop");
        publish = 0;
        tick();
        expect_bound(0, 1);
        append_head(0, P+2);
        tick();
        expect_bound(0, P+1);
        if (queue_result[0].active != Q'(1)) $fatal(1, "Singleton replacement lost active bit");
        publish = 0;
        tick();
        expect_bound(0, P+2);
        if (queue_result[0].active != '0) $fatal(1, "Last pop did not clear active bit");
        bind_window = '0;
    endtask

    task automatic physical_write(input int port, input int owner, input int address,
                                  input bit append, input int tail, input bit final_cell);
        staged_valid = P'(1) << port;
        previous_valid = append ? staged_valid : '0;
        staged_final = final_cell ? staged_valid : '0;
        previous_cell[port] = C'(tail);
        staged_desc[port] = D'(owner);
        tick();
        if (!write_valid || write_port != B'(port) || write_addr != C'(address)
            || write_owner != D'(owner) || final_write != final_cell)
            $fatal(1, "Wrong allocation or write consumer, expected address %0d", address);
    endtask

    task automatic link_overlap;
        physical_write(0, 0, 0, 0, 0, 0);
        physical_write(0, 0, 1, 1, 0, 1);
        physical_write(1, 1, 2, 0, 0, 0);
        physical_write(1, 1, 3, 1, 2, 0);
        physical_write(0, 2, 4, 0, 0, 1);
        read_eligible[0] = 1;
        read_more[0] = 1;
        abort_valid[1] = 1;
        abort_has_cell[1] = 1;
        abort_more[1] = 1;
        abort_cell[1] = 2;
        abort_desc[1] = 1;
        tx_return[1] = 1;
        tx_return_cell[1] = 4;
        tx_return_desc[1] = 2;
        physical_write(0, 3, 5, 0, 0, 1);
        if (!issue_valid || issue_port != 0 || payload_read_addr != 0 || tx_successor != 1
            || !cleanup_valid || cleanup_port != 1 || cleanup_done || abort_successor != 3)
            $fatal(1, "Independent TX and cleanup link consumers must capture old successors");
        read_eligible = '0;
        abort_valid = '0;
        tx_return = '0;
        physical_write(1, 4, 2, 0, 0, 1);
    endtask

    initial begin
        rst_n = 0;
        queue_credit_bytes = '1;
        port_credit_bytes = '1;
        tick();
        tick();
        rst_n = 1;
        queue_overlap();
        link_overlap();
        $display("PASS %0dx%0d old heads, same-edge replacement and concurrent link consumers", P, P);
        $finish;
    end
endmodule
