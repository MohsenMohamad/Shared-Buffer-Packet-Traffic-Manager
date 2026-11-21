module admission_tb #(
    parameter int P = 4, N_CELL = 1024, N_DESC = 256, MAX_BYTES = 1536
);
    localparam int Q = 4 * P, K = $clog2(N_CELL+1), D = $clog2(N_DESC), QB = $clog2(Q);
    logic clk = 0, rst_n = 1;
    logic dynamic_mode, wait_mode;
    logic [P-1:0] header_valid, bad_first_beat;
    logic [P-1:0][7:0] route, raw_class;
    logic [P-1:0][15:0] length;
    logic [Q-1:0][K-1:0] minimum, limit;
    logic [Q-1:0][12:0] alpha;
    logic [P:0] desc_return, credit_release;
    logic [P:0][D-1:0] return_id;
    logic [P:0][QB-1:0] release_qid;
    logic [P:0][K-1:0] release_count;

    typedef struct packed {
        logic [P-1:0] grant, reject, pending, abort_frame;
        logic [P-1:0][2:0] reason;
        logic [P-1:0][D-1:0] desc;
        logic [P-1:0][QB-1:0] qid;
        logic [P-1:0][K-1:0] reserved;
        logic [K-1:0] credit;
        logic [Q-1:0][K-1:0] held;
        logic error_flag;
    } result_t;
    result_t result [4];
    bit [N_DESC-1:0] live;
    int owner_queue [N_DESC], owner_credit [N_DESC];

    for (genvar version = 0; version < 4; version++) begin : implementation
        admission #(.P(P), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_BYTES(MAX_BYTES),
                    .LOOKAHEAD(version)) dut (
            .clk, .rst_n, .dynamic_mode, .wait_mode, .header_valid, .bad_first_beat,
            .route, .raw_class, .length, .minimum, .limit, .alpha,
            .desc_return, .credit_release, .return_id, .release_qid, .release_count,
            .rx_grant(result[version].grant), .rx_reject(result[version].reject),
            .rx_wait(result[version].pending), .rx_abort(result[version].abort_frame),
            .rx_reason(result[version].reason), .rx_desc(result[version].desc),
            .rx_qid(result[version].qid), .rx_reserved(result[version].reserved),
            .credit(result[version].credit), .held(result[version].held),
            .invariant_error(result[version].error_flag)
        );
    end

    task automatic clock_edge;
        #5;
        clk = 1;
        #1;
        #4;
        clk = 0;
    endtask

    task automatic reconcile;
        int expected_held [Q], expected_credit;
        // Validate new owners before removing old ones. A coincident return
        // can neither legitimize a duplicate nor be used by this batch.
        for (int p = 0; p < P; p++) begin
            if (result[2].grant[p]) begin
                if (live[result[2].desc[p]])
                    $fatal(1, "grant used a live ID");
                live[result[2].desc[p]] = 1;
                owner_queue[result[2].desc[p]] = int'(result[2].qid[p]);
                owner_credit[result[2].desc[p]] = (int'(length[p]) + 63) / 64;
            end
        end
        for (int lane = 0; lane <= P; lane++) begin
            if (credit_release[lane]) begin
                if (!live[return_id[lane]] || owner_queue[return_id[lane]] != int'(release_qid[lane]))
                    $fatal(1, "release fixture does not match an owner");
                owner_credit[return_id[lane]] -= int'(release_count[lane]);
            end
            if (desc_return[lane]) begin
                if (!live[return_id[lane]] || owner_credit[return_id[lane]] != 0)
                    $fatal(1, "return fixture did not release its entire owner");
                live[return_id[lane]] = 0;
            end
        end
        expected_credit = N_CELL;
        foreach (expected_held[q]) expected_held[q] = 0;
        for (int id = 0; id < N_DESC; id++) begin
            if (live[id]) begin
                expected_held[owner_queue[id]] += owner_credit[id];
                expected_credit -= owner_credit[id];
            end
        end
        if (result[2].credit != K'(expected_credit))
            $fatal(1, "merged credit differs from ownership recount");
        for (int q = 0; q < Q; q++)
            if (result[2].held[q] != K'(expected_held[q]))
                $fatal(1, "merged queue credit differs from ownership recount for queue %0d", q);
    endtask

    task automatic tick;
        result_t sampled;
        logic [P-1:0] old_valid;
        logic [P:0] old_return, old_release;
        clock_edge();
        if (result[0] !== result[1] || result[0] !== result[2])
            $fatal(1, "Prefix divergence at %0t: serial=%h lookahead=%h factored=%h",
                   $time, result[0], result[1], result[2]);
        if (result[0].error_flag)
            $fatal(1, "Legal stimulus raised accounting error at %0t", $time);
        if (rst_n) reconcile();
        if (rst_n && |header_valid) begin
            if (|(result[3].grant | result[3].reject | result[3].pending | result[3].abort_frame))
                $fatal(1, "Staged result visible on sampling edge");
            sampled = result[0];
            old_valid = header_valid;
            old_return = desc_return;
            old_release = credit_release;
            header_valid = '0;
            desc_return = '0;
            credit_release = '0;
            clock_edge();
            if (result[3] !== sampled)
                $fatal(1, "Staged commit differs from sampled prefix at %0t: got=%h expected=%h",
                       $time, result[3], sampled);
            header_valid = old_valid;
            desc_return = old_return;
            credit_release = old_release;
            // The same-edge outputs would otherwise be overwritten by the
            // intervening idle edge. Directed checks use the sampled result.
            last = sampled;
        end else begin
            last = result[0];
            if (rst_n && (result[3].credit != last.credit || result[3].held != last.held))
                $fatal(1, "Staged resources diverged on an unsampled edge");
        end
    endtask

    result_t last;

    task automatic reset;
        rst_n = 0;
        live = '0;
        header_valid = '0;
        bad_first_beat = '0;
        route = '0;
        raw_class = '0;
        minimum = '0;
        alpha = '0;
        desc_return = '0;
        credit_release = '0;
        release_count = '0;
        release_qid = '0;
        return_id = '0;
        for (int q = 0; q < Q; q++) limit[q] = K'(N_CELL);
        for (int p = 0; p < P; p++) length[p] = 16'd60;
        tick();
        rst_n = 1;
    endtask

    task automatic old_credit(input logic hold_head);
        reset();
        dynamic_mode = 0;
        wait_mode = hold_head;
        for (int i = 0; i < N_DESC-1; i++) begin
            header_valid = 1;
            tick();
            if (last.grant != 1 || last.desc[0] != D'(i))
                $fatal(1, "Initial pool allocation differs at %0d", i);
        end
        header_valid = '1;
        desc_return[P-1] = 1;
        credit_release[P-1] = 1;
        release_count[P-1] = 1;
        tick();
        if (last.grant != P'(2) || last.pending != (hold_head ? ~P'(2) : '0)
                || last.reject != (hold_head ? '0 : ~P'(2))
                || last.desc[1] != D'(N_DESC-1))
            $fatal(1, "Only the rotated first header may receive the old last ID");
        header_valid = ~P'(2);
        desc_return = '0;
        credit_release = '0;
        tick();
        if (last.grant != (P'(1) << (2 % P)) || last.desc[2 % P] != 0)
            $fatal(1, "Returned ID was not reusable on the following edge");
    endtask

    task automatic alpha_boundary(input int target, input logic hold_head);
        int occupied, cells;
        reset();
        dynamic_mode = 1;
        wait_mode = hold_head;
        minimum[1] = K'(N_CELL - 10);
        alpha[1] = 13'd4096;
        alpha[0] = 13'd64;
        occupied = 0;
        while (occupied < N_CELL - target) begin
            cells = N_CELL - target - occupied;
            if (cells > MAX_BYTES / 64) cells = MAX_BYTES / 64;
            header_valid = 1;
            raw_class[0] = 1;
            length[0] = 16'(cells * 64);
            tick();
            if (last.grant != 1) $fatal(1, "Filler would not fit its minimum");
            occupied += cells;
        end
        if (last.credit != K'(target)) $fatal(1, "Unexpected pre-edge U");
        header_valid = '1;
        raw_class = '0;
        for (int p = 0; p < P; p++) length[p] = 16'd65;
        tick();
        if (target == 10) begin
            if (last.grant != P'(2) || last.held[0] != 2 || last.credit != 8)
                $fatal(1, "Threshold 2 allows only one same-queue prefix reservation");
        end else if (last.grant != 0 || last.held[0] != 0
                     || last.reject != (hold_head ? '0 : '1)
                     || last.pending != (hold_head ? '1 : '0)) begin
            $fatal(1, "Threshold 1 must reject or hold two-cell requests");
        end
    endtask

    task automatic mixed_edges(input logic use_dynamic, input logic hold_head);
        bit [N_DESC-1:0] live;
        logic [QB-1:0] qid [N_DESC];
        logic [K-1:0] remaining [N_DESC];
        int id;
        reset();
        live = '0;
        dynamic_mode = use_dynamic;
        wait_mode = hold_head;
        for (int q = 0; q < Q; q++) begin
            minimum[q] = K'(q % 3);
            limit[q] = K'(1 + ((q * 11) % N_CELL));
            alpha[q] = 13'(64 + q * 197);
        end
        for (int edge_no = 0; edge_no < 384; edge_no++) begin
            desc_return = '0;
            credit_release = '0;
            for (int p = 0; p < P; p++) begin
                if (last.pending[p]) continue;
                header_valid[p] = $urandom_range(0, 3) != 0;
                route[p] = 8'($urandom_range(0, P));
                raw_class[p] = 8'($urandom_range(0, 4));
                length[p] = 16'($urandom_range(57, MAX_BYTES+2));
                bad_first_beat[p] = $urandom_range(0, 31) == 0;
            end
            // One arbitrated cleanup releases a complete old reservation.
            id = int'($urandom_range(0, N_DESC-1));
            for (int i = 0; i < N_DESC && !live[id]; i++) id = (id + 1) % N_DESC;
            if (live[id]) begin
                desc_return[P] = 1;
                credit_release[P] = 1;
                return_id[P] = D'(id);
                release_qid[P] = qid[id];
                release_count[P] = remaining[id];
            end
            tick();
            for (int p = 0; p < P; p++) begin
                if (last.grant[p]) begin
                    if (live[last.desc[p]])
                        $fatal(1, "duplicate or same-edge return reuse");
                    live[last.desc[p]] = 1;
                    qid[last.desc[p]] = last.qid[p];
                    remaining[last.desc[p]] = last.reserved[p];
                end
            end
            if (desc_return[P]) live[id] = 0;
        end
    endtask

    initial begin
        old_credit(0);
        old_credit(1);
        alpha_boundary(10, 0);
        alpha_boundary(9, 0);
        alpha_boundary(9, 1);
        mixed_edges(0, 0);
        mixed_edges(0, 1);
        mixed_edges(1, 0);
        mixed_edges(1, 1);
        $display("PASS %0dx%0d serial/lookahead/factored and staged prefix, ownership, alpha and mixed edges", P, P);
        $finish;
    end
endmodule
