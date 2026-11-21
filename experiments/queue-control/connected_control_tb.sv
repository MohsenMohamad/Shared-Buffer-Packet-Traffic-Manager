module connected_control_tb #(
    parameter int P = 4, N_CELL = 1024, N_DESC = 256, MAX_BYTES = 1536, L = 1
);
    localparam int Q = 4 * P, B = $clog2(P), QB = $clog2(Q);
    localparam int C = $clog2(N_CELL), D = $clog2(N_DESC), K = $clog2(N_CELL+1);
    localparam int W = C + 5 + B + 64 + 16 + 2 + 1 + 16;

    logic clk = 0, rst_n = 1, run_enable, token_start, dynamic_mode, wait_mode;
    logic [63:0] epoch = 0;
    logic [P-1:0] header_valid, first_last, staged_cell, abort_late, sink_ready;
    logic [P-1:0][7:0] first_keep, route, raw_class;
    logic [P-1:0][15:0] length, header_tag;
    logic [P-1:0][63:0] header_sequence;
    logic [P-1:0][1:0] header_ecn;
    logic [Q-1:0][K-1:0] minimum, limit, ecn_threshold;
    logic [Q-1:0] ecn_enable, queue_bucket_enable;
    logic [Q-1:0][12:0] alpha, quantum;
    logic [Q-1:0][15:0] queue_capacity;
    logic [Q-1:0][19:0] queue_rate;
    logic [P-1:0] port_bucket_enable;
    logic [P-1:0][15:0] port_capacity;
    logic [P-1:0][19:0] port_rate;
    logic [P-1:0][1:0] scheduler_mode, strict_class;
    logic response_valid, response_accepted;
    logic [63:0] response_epoch;
    logic [B-1:0] response_port, issue_port;
    logic [2:0] response_slot, issue_slot;
    logic [C-1:0] response_address, issue_address, write_address;
    logic [D-1:0] response_desc, issue_desc, published_desc;
    logic [P-1:0] rx_grant, rx_reject, rx_wait, rx_abort, bound, tx_valid, tx_last;
    logic [P-1:0][2:0] rx_reason, occupied;
    logic [P-1:0][D-1:0] rx_desc, bound_desc;
    logic [P-1:0][1:0] bound_class;
    logic [P-1:0][W-1:0] bound_info;
    logic [K-1:0] credit;
    logic [Q-1:0][K-1:0] held;
    logic [Q-1:0] active;
    logic write_event, publish_event, issue_event, cleanup_event, invariant_error;
    logic [P:0] cell_returns, desc_returns;
    logic [P:0][C-1:0] returned_cell;
    logic [P:0][D-1:0] returned_desc;

    connected_control #(.P(P), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_BYTES(MAX_BYTES)) dut (.*);

    typedef struct packed {
        logic valid;
        logic [63:0] epoch_id;
        logic [B-1:0] port_id;
        logic [2:0] slot;
        logic [C-1:0] address;
        logic [D-1:0] owner;
    } response_t;
    response_t beat_pipeline [L];
    response_t stale;
    int edge_count = 0;
    logic inject_stale;
    logic sampled_issue, sampled_write, sampled_publish, sampled_cleanup, sampled_response;
    logic [B-1:0] sampled_issue_port;
    logic [C-1:0] sampled_write_address;
    logic [D-1:0] sampled_publication;
    logic [P:0] sampled_cells, sampled_descs;
    logic [P:0][C-1:0] sampled_cell_ids;
    logic [P:0][D-1:0] sampled_desc_ids;
    logic [P-1:0] sampled_transfer;

    task automatic tick;
        response_t reply;
        reply = inject_stale ? stale : beat_pipeline[L-1];
        {response_valid, response_epoch, response_port, response_slot, response_address, response_desc} = reply;
        #4;
        sampled_issue = issue_event;
        sampled_issue_port = issue_port;
        sampled_write = write_event;
        sampled_write_address = write_address;
        sampled_publish = publish_event;
        sampled_publication = published_desc;
        sampled_cleanup = cleanup_event;
        sampled_response = response_accepted;
        sampled_cells = cell_returns;
        sampled_descs = desc_returns;
        sampled_cell_ids = returned_cell;
        sampled_desc_ids = returned_desc;
        sampled_transfer = tx_valid & sink_ready;
        assert (response_accepted == (reply.valid && rst_n && run_enable && reply.epoch_id == epoch))
            else $fatal(1, "response ownership at edge %0d", edge_count);
        for (int d = L-1; d > 0; d--) beat_pipeline[d] = beat_pipeline[d-1];
        beat_pipeline[0] = {issue_event, epoch, issue_port, issue_slot, issue_address, issue_desc};
        clk = 1;
        #1;
        assert (!invariant_error) else $fatal(1, "fixture invariant at edge %0d", edge_count);
        clk = 0;
        edge_count++;
    endtask

    task automatic reset_fixture(input bit dynamic_policy = 0, wait_policy = 0, strict = 0,
                                 input int shaping = 0);
        run_enable = 0;
        token_start = 0;
        rst_n = 0;
        epoch++;
        header_valid = '0;
        first_last = '0;
        staged_cell = '0;
        abort_late = '0;
        sink_ready = '0;
        first_keep = '1;
        route = '0;
        raw_class = '0;
        length = '0;
        header_tag = '0;
        header_sequence = '0;
        header_ecn = '0;
        minimum = '0;
        limit = {Q{K'(N_CELL)}};
        ecn_threshold = '0;
        ecn_enable = '0;
        queue_bucket_enable = '0;
        alpha = {Q{13'd4096}};
        quantum = {Q{13'(MAX_BYTES)}};
        queue_capacity = {Q{16'(MAX_BYTES)}};
        queue_rate = '0;
        port_bucket_enable = '0;
        port_capacity = {P{16'(MAX_BYTES)}};
        port_rate = '0;
        queue_bucket_enable[0] = shaping[0];
        port_bucket_enable[0] = shaping[1];
        queue_rate[0] = 20'h04000;
        port_rate[0] = 20'h04000;
        scheduler_mode = {P{2'd1}};
        if (strict) scheduler_mode[0] = 2'd2;
        strict_class = '0;
        dynamic_mode = dynamic_policy;
        wait_mode = wait_policy;
        inject_stale = 0;
        tick();
        tick();
        assert (credit == K'(N_CELL) && occupied == '0 && active == '0);
        rst_n = 1;
        run_enable = 1;
        token_start = 1;
        tick();
        token_start = 0;
    endtask

    task automatic await_first;
        for (int i = 0; i < 20 && !tx_valid[0]; i++) tick();
        assert (tx_valid[0]) else $fatal(1, "first beat trigger absent");
    endtask

    task automatic header(input int ingress, queue_id, bytes);
        header_valid[ingress] = 1;
        route[ingress] = 8'(queue_id / 4);
        raw_class[ingress] = 8'(queue_id % 4);
        length[ingress] = 16'(bytes);
        header_sequence[ingress]++;
        header_tag[ingress] = 16'(queue_id + 50);
    endtask

    task automatic reserve_and_write(input int ingress, queue_id, bytes);
        header(ingress, queue_id, bytes);
        tick();
        assert (rx_grant == (P'(1) << ingress)) else $fatal(1, "reserve q=%0d bytes=%0d U=%0d", queue_id, bytes, credit);
        header_valid = '0;
        staged_cell[ingress] = 1;
        for (int cell_index = 0; cell_index < (bytes+63)/64; cell_index++) begin
            tick();
            assert (sampled_write);
        end
        staged_cell = '0;
    endtask

    task automatic await_final(input logic [P-1:0] ports);
        for (int i = 0; i < 100 && (tx_last & ports) != ports; i++) begin
            sink_ready = ports & ~tx_last;
            tick();
        end
        sink_ready = '0;
        assert ((tx_last & ports) == ports) else $fatal(1, "final beat trigger absent");
    endtask

    task automatic handoff_and_reset;
        int write_edge, publish_edge, bind_edge, issue_edge, response_edge;
        reset_fixture();
        reserve_and_write(0, 0, 60);
        write_edge = edge_count - 1;
        sink_ready = '1;
        tick();
        assert (sampled_publish && sampled_publication == D'(0) && bound == '0);
        publish_edge = edge_count - 1;
        tick();
        assert (bound == P'(1) && bound_desc[0] == D'(0) && !sampled_issue);
        bind_edge = edge_count - 1;
        tick();
        assert (sampled_issue && sampled_issue_port == '0 && !sampled_transfer[0]);
        issue_edge = edge_count - 1;
        stale = beat_pipeline[0];
        repeat (L) begin
            tick();
            assert (!sampled_transfer[0]);
        end
        assert (sampled_response && tx_valid[0]);
        response_edge = edge_count - 1;
        tick();
        assert (sampled_transfer == P'(1));
        $display("handoff write=%0d publish=%0d bind=%0d issue=%0d response=%0d transfer=%0d",
                 write_edge, publish_edge, bind_edge, issue_edge, response_edge, edge_count-1);
        await_final(P'(1));
        sink_ready = '1;
        tick();
        assert (sampled_cells == (P+1)'(1) && sampled_descs == (P+1)'(1) && credit == K'(N_CELL));

        reset_fixture();
        reserve_and_write(0, 0, 60);
        repeat (3) tick();
        assert (sampled_issue && occupied[0] == 1);
        stale = beat_pipeline[0];
        reset_fixture();
        reserve_and_write(0, 0, 60);
        repeat (3) tick();
        assert (sampled_issue && occupied[0] == 1 && beat_pipeline[0].address == stale.address);
        // Present the old response while the recycled slot is pending.
        inject_stale = 1;
        if (L == 1) begin
            // Keep the legal response due on the next tick after the stale probe.
            response_valid = 1;
            {response_epoch, response_port, response_slot, response_address, response_desc} =
                {stale.epoch_id, stale.port_id, stale.slot, stale.address, stale.owner};
            #1;
            assert (!response_accepted && !tx_valid[0]);
        end else begin
            tick();
            assert (!sampled_response && !tx_valid[0] && occupied[0] == 1);
        end
        inject_stale = 0;
        tick();
        assert (sampled_response && tx_valid[0]);
        $display("reset pending issue, recycled cell %0d, discarded epoch %0d, new epoch %0d",
                 stale.address, stale.epoch_id, epoch);
    endtask

    task automatic scarcity(input bit hold);
        reset_fixture(0, hold);
        for (int i = 0; i < N_DESC-1; i++) reserve_and_write(0, 0, 60);
        await_final(P'(1));
        for (int p = 0; p < P; p++) header(p, 4*p+1, 60);
        sink_ready = P'(1);
        tick();
        assert (sampled_descs == (P+1)'(1) && sampled_desc_ids[0] == '0);
        assert (rx_grant == P'(2) && rx_desc[1] == D'(N_DESC-1));
        assert (rx_wait == (hold ? ~P'(2) : '0) && rx_reject == (hold ? '0 : ~P'(2)));
        for (int p = 0; p < P; p++) if (p != 1) assert (rx_reason[p] == 3'd4);
        $display("scarcity wait=%0d edge=%0d grant=%b last_old_id=%0d return=%0d", hold,
                 edge_count-1, rx_grant, rx_desc[1], sampled_desc_ids[0]);
        header_valid[1] = 0;
        sink_ready = '0;
        if (hold) begin
            tick();
            assert ($onehot(rx_grant));
            for (int p = 0; p < P; p++) if (rx_grant[p]) assert (rx_desc[p] == '0);
        end
    endtask

    task automatic alpha_threshold(input int before_credit, input bit hold);
        int remaining, count, qid, frame_index;
        reset_fixture(1, hold);
        alpha[7] = 13'd64;
        remaining = N_CELL - before_credit;
        frame_index = 0;
        while (remaining > 0) begin
            count = remaining > MAX_BYTES/64 ? MAX_BYTES/64 : remaining;
            qid = frame_index % (Q-1);
            if (qid >= 7) qid++;
            reserve_and_write(0, qid, 64*count);
            remaining -= count;
            frame_index++;
        end
        assert (credit == K'(before_credit) && held[7] == 0);
        header(1, 7, 65);
        tick();
        if (before_credit == 10) begin
            assert (rx_grant == P'(2) && credit == K'(8) && held[7] == K'(2));
        end else begin
            assert (rx_grant == '0 && rx_reason[1] == 3'd3 && rx_wait[1] == hold &&
                    rx_reject[1] == !hold && credit == K'(9) && held[7] == '0);
        end
        $display("alpha old_U=%0d wait=%0d edge=%0d grant=%b reject=%b pending=%b",
                 before_credit, hold, edge_count-1, rx_grant, rx_reject, rx_wait);
    endtask

    task automatic returns(input bit hold_one);
        reset_fixture();
        for (int p = 0; p < P; p++) header(p, 4*p, 60);
        tick();
        assert (&rx_grant);
        header_valid = '0;
        staged_cell = '1;
        repeat (P) tick();
        staged_cell = '0;
        await_final('1);
        header(0, 1, 65);
        tick();
        assert (rx_grant == P'(1));
        header_valid = '0;
        staged_cell = P'(1);
        abort_late = P'(1);
        tick();
        assert (sampled_write && sampled_write_address == C'(P) && sampled_descs == '0);
        staged_cell = '0;
        abort_late = '0;
        sink_ready = hold_one ? ~P'(1) : '1;
        tick();
        assert (sampled_cleanup && sampled_cells == (hold_one ? ~((P+1)'(1)) : '1) &&
                sampled_descs == sampled_cells);
        for (int i = 0; i <= P; i++)
            if (sampled_cells[i]) assert (sampled_cell_ids[i] == C'(i) && sampled_desc_ids[i] == D'(i));
        assert (credit == K'(N_CELL-int'(hold_one)));
        $display("reachable returns hold_one=%0d edge=%0d lanes=%b merged_U=%0d",
                 hold_one, edge_count-1, sampled_cells, credit);
        if (hold_one) begin
            sink_ready = P'(1);
            tick();
            assert (sampled_descs == (P+1)'(1) && credit == K'(N_CELL));
        end
    endtask

    task automatic malformed_and_release;
        reset_fixture();
        reserve_and_write(0, 0, 60);
        await_final(P'(1));
        header(1, 4, 65);
        first_keep[1] = 8'h7f;
        sink_ready = P'(1);
        tick();
        assert (sampled_descs == (P+1)'(1) && rx_grant == P'(2) && rx_abort == P'(2) &&
                credit == K'(N_CELL-2) && held[0] == 0 && held[4] == K'(2));
        header_valid = '0;
        sink_ready = '0;
        tick();
        assert (sampled_cleanup && sampled_descs[P] && !sampled_cells[P] && !sampled_write &&
                credit == K'(N_CELL) && held[4] == 0);
        $display("malformed first service shares release, zero-cell cleanup edge=%0d", edge_count-1);
    endtask

    task automatic cached_collision(input int depth);
        reset_fixture();
        reserve_and_write(0, 0, 192);
        await_first();
        for (int i = 0; i < depth; i++) reserve_and_write(1, 1, 60+i);
        header(1, 1, 63);
        tick();
        assert (rx_grant == P'(2) && rx_desc[1] == D'(depth+1));
        header_valid = '0;
        sink_ready = P'(1);
        repeat (7) begin
            tick();
            assert (sampled_transfer == P'(1) && bound == 0);
        end
        staged_cell = P'(2);
        tick();
        assert (sampled_transfer == P'(1) && sampled_write && bound == 0);
        sink_ready = '0;
        staged_cell = '0;
        tick();
        assert (sampled_publish && sampled_publication == D'(depth+1));
        assert (bound == (depth == 0 ? '0 : P'(1)));
        if (depth > 0) assert (bound_desc[0] == D'(1) && bound_info[0][15:0] == 16'd60);
        assert (active[1] && dut.heads.head[1] == D'(depth == 2 ? 2 : depth+1) &&
                dut.heads.cached[1][15:0] == (depth == 2 ? 16'd61 : 16'd63));
        if (depth == 0) begin
            tick();
            assert (bound == P'(1) && bound_desc[0] == D'(1));
        end
        $display("cached collision old_depth=%0d edge=%0d next_head=%0d",
                 depth, edge_count-1, dut.heads.head[1]);
    endtask

    task automatic strict_collision(input bit publish_on_bind);
        reset_fixture(0, 0, 1);
        reserve_and_write(0, 0, 192);
        await_first();
        reserve_and_write(1, 1, 60);
        header(1, 0, 61);
        tick();
        assert (rx_grant == P'(2) && rx_desc[1] == D'(2));
        header_valid = '0;
        sink_ready = P'(1);
        repeat (6) begin
            tick();
            assert (sampled_transfer == P'(1) && bound == 0);
        end
        staged_cell = publish_on_bind ? '0 : P'(2);
        tick();
        assert (sampled_transfer == P'(1) && bound == 0);
        staged_cell = publish_on_bind ? P'(2) : '0;
        tick();
        assert (sampled_transfer == P'(1) && bound == 0 && sampled_publish == !publish_on_bind);
        sink_ready = '0;
        staged_cell = '0;
        tick();
        assert (sampled_publish == publish_on_bind && bound == P'(1) &&
                bound_desc[0] == D'(publish_on_bind ? 1 : 2));
        tick();
        assert (bound == 0 && dut.frame_desc[0][1] == D'(publish_on_bind ? 1 : 2));
        $display("strict publish_on_bind=%0d bound=%0d edge=%0d",
                 publish_on_bind, dut.frame_desc[0][1], edge_count-2);
    endtask

    task automatic full_credit;
        reset_fixture();
        reserve_and_write(0, 0, P == 4 ? 513 : 129);
        await_first();
        if (P == 2) reserve_and_write(1, 1, 192);
        sink_ready = P'(1);
        repeat (7) begin
            tick();
            assert (sampled_transfer == P'(1) && !sampled_cells[0]);
        end
        sink_ready = '0;
        reserve_and_write(1, 4, 60);
        for (int i = 0; i < 30 && !bound[1]; i++) tick();
        assert (occupied[0] == 6 && bound[1] && tx_valid[0]);
        sink_ready = P'(1);
        tick();
        assert (sampled_cells[0] && !sampled_descs[0] && sampled_issue &&
                sampled_issue_port == B'(1) && occupied[0] == 5);
        $display("full old credit=6 retire+other issue edge=%0d merged_credit=%0d", edge_count-1, occupied[0]);
        tick();
        if (P == 4) assert (sampled_issue && sampled_issue_port == '0);
    endtask

    function automatic logic [31:0] limiting_balance(input int shaping);
        return shaping[0] ? dut.heads.registered_tokens.queue_state[0].balance
                          : dut.heads.registered_tokens.port_state[0].balance;
    endfunction

    task automatic token_neighbor(input int shaping);
        localparam logic [31:0] BELOW = 32'h0040_c000;
        localparam logic [31:0] EXACT = 32'h0041_0000;
        reset_fixture(0, 0, 1, shaping);
        reserve_and_write(0, 0, MAX_BYTES);
        await_first();
        reserve_and_write(1, 0, 65);
        sink_ready = P'(1);
        repeat ((MAX_BYTES+7)/8-16) begin
            tick();
            assert (sampled_transfer == P'(1) && bound == 0);
        end
        sink_ready = '0;
        for (int i = 0; i < 260 && limiting_balance(shaping) < BELOW; i++) begin
            tick();
            assert (bound == 0);
        end
        assert (limiting_balance(shaping) == BELOW && active[0]);
        tick();
        assert (bound == 0 && limiting_balance(shaping) == EXACT && active[0]);
        tick();
        assert (bound == P'(1) && bound_desc[0] == D'(1) && limiting_balance(shaping) == 32'h4000);
        tick();
        assert (bound == 0 && limiting_balance(shaping) == 32'h8000);
        $display("reachable token threshold enabled=%0d edge=%0d pre=64.75 next=65 debit=65",
                 shaping, edge_count-3);
    endtask

    initial begin
        handoff_and_reset();
        scarcity(0);
        scarcity(1);
        alpha_threshold(10, 0);
        alpha_threshold(9, 0);
        alpha_threshold(9, 1);
        returns(0);
        returns(1);
        malformed_and_release();
        cached_collision(0);
        cached_collision(1);
        cached_collision(2);
        strict_collision(0);
        strict_collision(1);
        full_credit();
        for (int enabled_buckets = 1; enabled_buckets <= 3; enabled_buckets++) token_neighbor(enabled_buckets);
        $display("PASS connected control P=%0d L=%0d", P, L);
        $finish;
    end
endmodule
