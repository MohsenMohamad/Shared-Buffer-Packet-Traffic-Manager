// The symbolic ports represent current-epoch caller actions. The caller
// ledger supplies legality from old ownership and never assumes a DUT count.
module pool_candidate_formal #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (
    input logic clk, rst_n,
    input logic [N_RX-1:0] reserve_commit,
    input cell_count_t [N_RX-1:0] reserve_cells,
    input qid_t [N_RX-1:0] reserve_qid,
    input logic write_offer,
    input desc_id_t write_owner,
    input logic [N_TX-1:0] tx_present, tx_final,
    input cell_id_t [N_TX-1:0] tx_cell,
    input qid_t [N_TX-1:0] tx_qid,
    input desc_id_t [N_TX-1:0] tx_desc,
    input logic cleanup_present, cleanup_has_cell, cleanup_done,
    input cell_id_t cleanup_cell,
    input qid_t cleanup_qid,
    input desc_id_t cleanup_desc,
    input cell_count_t cleanup_released,
    input cell_id_t witness_cell,
    input desc_id_t witness_desc
);
    logic ready, write_accept;
    logic [N_RX-1:0] rank_valid;
    desc_id_t [N_RX-1:0] rank_id, grant_desc;
    cell_id_t write_id;
    cell_count_t free_cells, unreserved, reserved_free;
    desc_count_t free_desc;
    cell_count_t [N_Q-1:0] held;

    tm_resource_pools #(.PROFILE(PROFILE)) dut (.*);

    logic [N_TX:0] cell_events, desc_events, credit_events;
    cell_id_t [N_TX:0] cell_ids;
    desc_id_t [N_TX:0] desc_ids;
    qid_t [N_TX:0] credit_queues;
    cell_count_t [N_TX:0] credit_amounts;

    assign cell_events = {cleanup_present && cleanup_has_cell, tx_present};
    assign desc_events = {cleanup_present && cleanup_done, tx_present & tx_final};
    assign credit_events = {desc_events[N_TX], tx_present};
    assign cell_ids = {cleanup_cell, tx_cell};
    assign desc_ids = {cleanup_desc, tx_desc};
    assign credit_queues = {cleanup_qid, tx_qid};
    assign credit_amounts[N_TX] = cleanup_released;
    for (genvar lane = 0; lane < N_TX; ++lane)
        assign credit_amounts[lane] = cell_count_t'(1);

    localparam int FRAME_CELLS = MAX_FRAME_BYTES / 64;
    localparam int FRAME_W = $clog2(FRAME_CELLS + 1);
    typedef logic [FRAME_W-1:0] frame_count_t;
    logic past_valid = 0;
    logic was_reset = 0;
    logic caller_ready = 0;
    always_ff @(posedge clk)
        caller_ready <= rst_n;
    logic [N_DESC-1:0] live_desc;
    logic [N_CELL-1:0] live_cell;
    qid_t [N_DESC-1:0] owner_queue;
    desc_id_t [N_CELL-1:0] cell_owner;
    frame_count_t [N_DESC-1:0] credit, written;
    logic [N_DESC-1:0] aborting;
    cell_count_t caller_u;
    logic [N_TX:0] cell_owner_matches, desc_owner_matches;
    logic write_owner_matches, cleanup_owner_matches;
    int prefix_u, next_u;

`ifdef POOL_ABSTRACT_CALLER
    cell_count_t [N_Q-1:0] caller_held;
    logic [N_Q-1:0][31:0] held_after_add, returning_credit;
    int caller_free, caller_reserved;

    assign caller_free = N_CELL - $countones(live_cell);
    assign caller_reserved = caller_free - int'(caller_u);
    assign write_owner_matches = caller_reserved > 0;
    assign cleanup_owner_matches = live_desc[cleanup_desc];

    for (genvar lane = 0; lane <= N_TX; ++lane) begin : abstract_owners
        assign desc_owner_matches[lane] = live_desc[desc_ids[lane]];
        assign cell_owner_matches[lane] = live_cell[cell_ids[lane]] && desc_owner_matches[lane];
    end

    always_comb begin
        held_after_add = '0;
        returning_credit = '0;
        for (int q = 0; q < N_Q; ++q) begin
            held_after_add[q] = int'(caller_held[q]);
            for (int lane = 0; lane < N_RX; ++lane)
                if (reserve_commit[lane] && int'(reserve_qid[lane]) == q)
                    held_after_add[q] = held_after_add[q] + int'(reserve_cells[lane]);
            for (int lane = 0; lane <= N_TX; ++lane)
                if (credit_events[lane] && int'(credit_queues[lane]) == q)
                    returning_credit[q] = returning_credit[q] + int'(credit_amounts[lane]);
        end
    end

    // This abstraction allows every schedule satisfying the local aggregate
    // preconditions. Descriptor/queue/epoch linkage is exercised by the
    // separate ledger and must be established at the real caller boundary.
    always_ff @(posedge clk) begin
        if (!rst_n || !caller_ready) begin
            live_desc <= '0;
            live_cell <= '0;
            caller_u <= cell_count_t'(N_CELL);
            caller_held <= '0;
        end else begin
            assume(prefix_u >= 0 && $countones(reserve_commit) <= N_DESC - $countones(live_desc));
            assume(!write_offer || write_owner_matches);
            if (write_accept)
                live_cell[write_id] <= 1;
            for (int lane = 0; lane < N_RX; ++lane) begin
                if (reserve_commit[lane]) begin
                    assume(reserve_cells[lane] != 0 && int'(reserve_cells[lane]) <= FRAME_CELLS);
                    live_desc[grant_desc[lane]] <= 1;
                end
            end
            for (int lane = 0; lane <= N_TX; ++lane) begin
                if (cell_events[lane]) begin
                    assume(cell_owner_matches[lane]);
                    live_cell[cell_ids[lane]] <= 0;
                end
                if (desc_events[lane]) begin
                    assume(desc_owner_matches[lane]);
                    live_desc[desc_ids[lane]] <= 0;
                end
            end
            for (int lane = 0; lane < N_TX; ++lane)
                if (tx_present[lane])
                    assume(int'(tx_qid[lane]) / N_CLASS == lane);
            if (cleanup_present) begin
                assume(cleanup_owner_matches && (cleanup_has_cell || cleanup_done));
                if (cleanup_done)
                    assume(cleanup_released != 0 &&
                           int'(cleanup_released) + int'(write_offer) <= caller_reserved + int'(cleanup_has_cell));
            end
            if (!desc_events[N_TX])
                assume(cleanup_released == 0);
            for (int q = 0; q < N_Q; ++q) begin
                assume(returning_credit[q] <= int'(caller_held[q]));
                caller_held[q] <= cell_count_t'(held_after_add[q] - returning_credit[q]);
            end
            caller_u <= cell_count_t'(next_u);
        end
    end
`endif

    always_comb begin
        prefix_u = int'(caller_u);
        for (int lane = 0; lane < N_RX; ++lane)
            if (reserve_commit[lane])
                prefix_u -= int'(reserve_cells[lane]);
        next_u = prefix_u + $countones(tx_present);
        if (desc_events[N_TX])
            next_u += int'(cleanup_released);
    end

`ifndef POOL_ABSTRACT_CALLER
    assign write_owner_matches = live_desc[write_owner] && !aborting[write_owner] &&
                                 credit[write_owner] > written[write_owner];
    assign cleanup_owner_matches = live_desc[cleanup_desc] && owner_queue[cleanup_desc] == cleanup_qid;
    for (genvar lane = 0; lane <= N_TX; ++lane) begin : legal_return
        assign desc_owner_matches[lane] = live_desc[desc_ids[lane]] &&
                                          owner_queue[desc_ids[lane]] == credit_queues[lane];
        assign cell_owner_matches[lane] = live_cell[cell_ids[lane]] &&
                                          cell_owner[cell_ids[lane]] == desc_ids[lane] &&
                                          desc_owner_matches[lane];
    end
`endif

    for (genvar lane = 0; lane <= N_TX; ++lane) begin : distinct_returns
        for (genvar earlier = 0; earlier < lane; ++earlier) begin : distinct
            always @(posedge clk)
                if (rst_n && caller_ready) begin
                    assume(!cell_events[lane] || !cell_events[earlier] || cell_ids[lane] != cell_ids[earlier]);
                    // One retirement service per frame, including partial returns.
                    assume(!(cell_events[lane] || desc_events[lane]) ||
                           !(cell_events[earlier] || desc_events[earlier]) ||
                           desc_ids[lane] != desc_ids[earlier]);
                end
        end
    end

    always_ff @(posedge clk) begin
        past_valid <= 1;
        was_reset <= !rst_n;
        if (!past_valid)
            assume(!rst_n);
        if (past_valid && rst_n && was_reset)
            assume($past(was_reset));
        if (!rst_n || !caller_ready)
            assume(reserve_commit == '0 && !write_offer && tx_present == '0 && !cleanup_present);
    end

`ifndef POOL_ABSTRACT_CALLER
    // The frame ledger gives covers a live frame and actual selected cell
    // owner. It leaves stalls unconstrained in the ordinary runs.
    always_ff @(posedge clk) begin
        if (!rst_n || !caller_ready) begin
            live_desc <= '0;
            live_cell <= '0;
            owner_queue <= '0;
            cell_owner <= '0;
            credit <= '0;
            written <= '0;
            aborting <= '0;
            caller_u <= cell_count_t'(N_CELL);
        end else begin
            assume(prefix_u >= 0 && $countones(reserve_commit) <= N_DESC - $countones(live_desc));
            for (int lane = 0; lane < N_RX; ++lane) begin
                if (reserve_commit[lane]) begin
                    assume(reserve_cells[lane] != 0 && int'(reserve_cells[lane]) <= FRAME_CELLS);
                    live_desc[grant_desc[lane]] <= 1;
                    owner_queue[grant_desc[lane]] <= reserve_qid[lane];
                    credit[grant_desc[lane]] <= frame_count_t'(reserve_cells[lane]);
                    written[grant_desc[lane]] <= '0;
                    aborting[grant_desc[lane]] <= 0;
                end
            end
            if (write_offer)
                assume(write_owner_matches);
            if (write_accept) begin
                live_cell[write_id] <= 1;
                cell_owner[write_id] <= write_owner;
                written[write_owner] <= written[write_owner] + 1'b1;
            end
            for (int lane = 0; lane < N_TX; ++lane) begin
                if (tx_present[lane]) begin
                    assume(cell_owner_matches[lane] && !aborting[tx_desc[lane]]);
                    assume(credit[tx_desc[lane]] == written[tx_desc[lane]] && written[tx_desc[lane]] != 0);
                    assume(tx_final[lane] == (written[tx_desc[lane]] == 1));
                    assume(int'(tx_qid[lane]) / N_CLASS == lane);
                    live_cell[tx_cell[lane]] <= 0;
                    written[tx_desc[lane]] <= written[tx_desc[lane]] - 1'b1;
                    credit[tx_desc[lane]] <= credit[tx_desc[lane]] - 1'b1;
                    if (tx_final[lane])
                        live_desc[tx_desc[lane]] <= 0;
                end
            end
            if (cleanup_present) begin
                assume(cleanup_owner_matches && credit[cleanup_desc] > written[cleanup_desc]);
                assume(cleanup_has_cell == (written[cleanup_desc] != 0));
                assume(cleanup_done == (written[cleanup_desc] <= 1));
                assume(!write_offer || write_owner != cleanup_desc);
                aborting[cleanup_desc] <= 1;
                if (cleanup_has_cell) begin
                    assume(cell_owner_matches[N_TX]);
                    live_cell[cleanup_cell] <= 0;
                    written[cleanup_desc] <= written[cleanup_desc] - 1'b1;
                end
                if (cleanup_done) begin
                    assume(cleanup_released == cell_count_t'(credit[cleanup_desc]));
                    live_desc[cleanup_desc] <= 0;
                end
            end
            if (!desc_events[N_TX])
                assume(cleanup_released == 0);
            caller_u <= cell_count_t'(next_u);
        end
    end

`endif

`ifdef POOL_EXHAUSTION_COVER
    // Drive a legal, full-capacity setup for the deep small-profile cover.
    // Write IDs and owners stay symbolic and obey the ledger.
    localparam int CELLS_PER_FRAME = N_CELL / N_DESC;
    int unsigned fill_edge = 0;
    desc_id_t [N_DESC-1:0] fill_owners;
    cell_id_t first_cell;
    always_ff @(posedge clk) begin
        if (past_valid) begin
            // Start with exactly two sampled reset edges and then stay active.
            assume(rst_n == (!was_reset || $past(was_reset)));
        end
        if (rst_n && caller_ready) begin
            fill_edge <= fill_edge + 1;
            assume(!cleanup_present);
            assume(reserve_commit == ((fill_edge < N_DESC/N_RX) ? '1 : '0));
            if (fill_edge < N_DESC/N_RX)
                for (int lane = 0; lane < N_RX; ++lane) begin
                    assume(reserve_cells[lane] == cell_count_t'(CELLS_PER_FRAME));
                    assume(reserve_qid[lane] == qid_t'(lane * N_CLASS));
                    fill_owners[fill_edge*N_RX+lane] <= grant_desc[lane];
                end
            assume(write_offer == (fill_edge > 0 && fill_edge <= N_CELL));
            if (fill_edge > 0 && fill_edge <= N_CELL)
                assume(write_owner == fill_owners[(fill_edge-1)/CELLS_PER_FRAME]);
            if (fill_edge == 1 && write_accept)
                first_cell <= write_id;
            assume(tx_present == (fill_edge == N_CELL+1 ? N_TX'(1) : '0));
            if (tx_present[0]) begin
                assume(tx_desc[0] == fill_owners[0] && tx_cell[0] == first_cell);
                assume(tx_qid[0] == '0 && !tx_final[0]);
            end
            c_full_cell_exhaustion: cover(free_cells == 0 && |tx_present);
        end
    end
`endif

`ifdef POOL_PRIMARY_PREFIX_COVER
    // A full-width prefix followed by one materialization checks the primary
    // counter widths at the real 1,024-cell and 256-descriptor capacities.
    int unsigned capacity_edge = 0;
    desc_id_t first_owner;
    always_ff @(posedge clk) begin
        if (past_valid)
            assume(rst_n == (!was_reset || $past(was_reset)));
        if (rst_n && caller_ready) begin
            capacity_edge <= capacity_edge + 1;
            assume(tx_present == '0 && !cleanup_present);
            assume(reserve_commit == (capacity_edge == 0 ? '1 : '0));
            assume(write_offer == (capacity_edge == 1));
            if (capacity_edge == 0) begin
                first_owner <= grant_desc[0];
                for (int lane = 0; lane < N_RX; ++lane) begin
                    assume(reserve_cells[lane] == cell_count_t'(1));
                    assume(reserve_qid[lane] == qid_t'(lane * N_CLASS));
                end
            end
            if (capacity_edge == 1)
                assume(write_owner == first_owner);
            c_primary_capacity: cover(capacity_edge == 2 && free_cells == cell_count_t'(N_CELL-1) &&
                free_desc == desc_count_t'(N_DESC-N_RX) && unreserved == cell_count_t'(N_CELL-N_RX) &&
                reserved_free == cell_count_t'(N_RX-1));
        end
    end
`endif

    cell_count_t assigned;
    assign assigned = cell_count_t'(N_CELL - $countones(dut.cells.free_bits));
    multi_egress_pool_obligations #(.N_RX(N_RX), .N_TX(N_TX), .N_CELL(N_CELL), .N_DESC(N_DESC)) check_pool (
        .clk, .reset_n(rst_n), .initialized(ready), .witness_cell, .witness_desc,
        .cell_free(dut.cells.free_bits), .desc_free(dut.descriptors.free_bits),
        .f_count(free_cells), .u_count(unreserved), .r_count(reserved_free), .a_count(assigned),
        .d_count(free_desc), .h_count(held), .grant(reserve_commit), .grant_desc,
        .grant_queue(reserve_qid), .grant_cells(reserve_cells),
        .write_cell(write_accept), .write_addr(write_id),
        .release_cell(dut.cells.return_present), .release_desc(dut.descriptors.return_present),
        .release_addr(dut.cells.return_cell), .release_id(dut.descriptors.return_desc),
        .retire_queue(tx_qid), .cleanup_done(desc_events[N_TX]), .cleanup_queue(cleanup_qid),
        .cleanup_credit(cleanup_released), .write_owner_matches, .cleanup_owner_matches,
        .cell_owner_matches, .desc_owner_matches
    );

    always @(posedge clk) begin
        if (past_valid && rst_n && !$past(rst_n))
            a_first_release: assert(!ready);
        if (past_valid && rst_n && $past(rst_n)) begin
            a_ready: assert(ready);
            a_caller_membership: assert(dut.cells.free_bits == ~live_cell &&
                                        dut.descriptors.free_bits == ~live_desc);
            a_independent_credit: assert(caller_u == unreserved);
`ifdef POOL_ABSTRACT_CALLER
            a_independent_queues: assert(caller_held == held);
`endif
            a_staged_write: assert(write_accept == write_offer);
            a_return_lanes: assert(dut.cells.return_present == cell_events &&
                                  dut.descriptors.return_present == desc_events &&
                                  dut.accounting.release_present == credit_events);
            c_partial: cover(cleanup_present && !cleanup_done);
            c_final_with_cell: cover(cleanup_present && cleanup_done && cleanup_has_cell);
            c_high_and_cleanup: cover(cell_events[N_TX-1] && cell_events[N_TX] &&
                                      cell_ids[N_TX-1] != cell_ids[N_TX]);
        end
    end

    for (genvar lane = 0; lane < N_RX; ++lane) begin : admission_binding
        always @(posedge clk) begin
            int prior_commits;
            prior_commits = 0;
            for (int previous = 0; previous < lane; ++previous)
                prior_commits += int'(reserve_commit[previous]);
            if (rst_n && ready) begin
                a_rank_valid: assert(rank_valid[lane] == (lane < N_DESC - $countones(live_desc)));
                a_rank_membership: assert(!rank_valid[lane] || !live_desc[rank_id[lane]]);
                a_projection: assert(!reserve_commit[lane] ||
                                     (rank_valid[prior_commits] && grant_desc[lane] == rank_id[prior_commits]));
            end
        end
        for (genvar previous = 0; previous < lane; ++previous) begin : distinct
            always @(posedge clk)
                if (rst_n && ready && rank_valid[lane] && rank_valid[previous])
                    a_rank_distinct: assert(rank_id[lane] != rank_id[previous]);
        end
    end

    for (genvar lane = 0; lane <= N_TX; ++lane) begin : lane_binding
        always @(posedge clk)
            if (rst_n && ready) begin
                a_cells: assert(!cell_events[lane] || dut.cells.return_cell[lane] == cell_ids[lane]);
                a_descs: assert(!desc_events[lane] || dut.descriptors.return_desc[lane] == desc_ids[lane]);
                a_credit: assert(!credit_events[lane] ||
                    (dut.accounting.release_qid[lane] == credit_queues[lane] &&
                     dut.accounting.release_cells[lane] == credit_amounts[lane]));
            end
    end
endmodule
