// Each elaboration proves one component cone with arbitrary top-level traffic.
module pool_safety_lemmas #(
    parameter int LEMMA = 0,
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
    input logic [N_TX-1:0] tx_present, tx_final,
    input cell_id_t [N_TX-1:0] tx_cell,
    input desc_id_t [N_TX-1:0] tx_desc,
    input qid_t [N_TX-1:0] tx_qid,
    input logic cleanup_present, cleanup_has_cell, cleanup_done,
    input cell_id_t cleanup_cell,
    input desc_id_t cleanup_desc,
    input qid_t cleanup_qid,
    input cell_count_t cleanup_released,

    // Old caller state, grouped into the write owner, final cleanup owner
    // and remaining owners. Grouped owners are disjoint by the caller contract.
    input desc_id_t write_owner,
    input cell_count_t write_credit, write_materialized,
    input cell_count_t cleanup_credit, cleanup_materialized,
    input cell_count_t other_credit, other_materialized
);
    logic ready, write_accept;
    logic [N_RX-1:0] rank_valid;
    desc_id_t [N_RX-1:0] rank_id, grant_desc;
    cell_id_t write_id;
    cell_count_t free_cells, unreserved, reserved_free;
    desc_count_t free_desc;
    cell_count_t [N_Q-1:0] held;
    tm_resource_pools #(.PROFILE(PROFILE)) dut (.*);

    logic history = 0;
    logic active, cleanup_returns_cell, cleanup_retires;
    logic [N_TX:0] cell_returns, desc_returns;
    cell_id_t [N_TX:0] returned_cells;
    desc_id_t [N_TX:0] returned_descs;
    assign active = rst_n && ready;
    assign cleanup_returns_cell = cleanup_present && cleanup_has_cell;
    assign cleanup_retires = cleanup_present && cleanup_done;
    assign cell_returns = {cleanup_returns_cell, tx_present};
    assign desc_returns = {cleanup_retires, tx_present & tx_final};
    assign returned_cells = {cleanup_cell, tx_cell};
    assign returned_descs = {cleanup_desc, tx_desc};

    always @(posedge clk) begin
        history <= 1;
        if (!history)
            c_initial_reset: assume(!rst_n);
    end

    // Include invalid encoded operands and every lane before checking bounds.
    localparam int SUM_W = 1 + $clog2((N_Q + N_RX + N_TX + 4) * (2**CELL_COUNT_W - 1) + 1);
    typedef logic signed [SUM_W-1:0] math_t;
    math_t reserved_now, returned_credit, tx_count, cleanup_amount;
    always_comb begin
        tx_count = math_t'($countones(tx_present));
        cleanup_amount = cleanup_retires ? math_t'(cleanup_released) : '0;
        returned_credit = tx_count + cleanup_amount;
        reserved_now = '0;
        for (int lane = 0; lane < N_RX; lane++)
            if (reserve_commit[lane])
                reserved_now += math_t'(reserve_cells[lane]);
    end

    if (LEMMA == 0) begin : selection
        for (genvar rank = 0; rank < N_RX; rank++) begin : ranks
            always @(posedge clk) begin
                a_valid: assert(rank_valid[rank] == ($countones(dut.descriptors.free_bits) > rank));
                if (rank_valid[rank]) begin
                    a_pre_free: assert(dut.descriptors.free_bits[rank_id[rank]]);
                    a_order: assert($countones(dut.descriptors.free_bits &
                        ((N_DESC'(1) << rank_id[rank]) - N_DESC'(1))) == rank);
                end
            end
            for (genvar prior = 0; prior < rank; prior++) begin : distinct
                always @(posedge clk)
                    if (rank_valid[rank] && rank_valid[prior])
                        a_distinct: assert(rank_id[rank] != rank_id[prior]);
            end
        end

        for (genvar lane = 0; lane < N_RX; lane++) begin : projection
            // The maximum number of preceding commits is N_RX-1.
            rx_id_t earlier;
            always_comb begin
                earlier = '0;
                for (int prior = 0; prior < lane; prior++)
                    earlier += rx_id_t'(reserve_commit[prior]);
            end
            always @(posedge clk)
                if (!reserve_commit[lane])
                    a_hole: assert(grant_desc[lane] == '0);
                else begin
                    a_project: assert(grant_desc[lane] == rank_id[earlier]);
                    if ($countones(reserve_commit) <= $countones(dut.descriptors.free_bits))
                        a_allocatable: assert(rank_valid[earlier] &&
                                              dut.descriptors.free_bits[grant_desc[lane]]);
                end
        end

        always @(posedge clk) begin
            if (|dut.cells.free_bits) begin
                a_cell_pre_free: assert(dut.cells.free_bits[write_id]);
                a_first_cell: assert((dut.cells.free_bits &
                    ((N_CELL'(1) << write_id) - N_CELL'(1))) == '0);
            end
            a_write_gate: assert(write_accept ==
                (ready && write_offer && free_cells != unreserved && (|dut.cells.free_bits)));
        end
    end

    if (LEMMA == 1 || LEMMA == 2) begin : bitmap
        localparam bit IS_CELL = LEMMA == 1;
        localparam int CAPACITY = IS_CELL ? N_CELL : N_DESC;
        localparam int ID_W = $clog2(CAPACITY);
        localparam int SELECT_LANES = IS_CELL ? 1 : N_RX;
        logic [N_TX:0] returns;
        logic [N_TX:0][ID_W-1:0] return_id;
        logic [SELECT_LANES-1:0] claims;
        logic [SELECT_LANES-1:0][ID_W-1:0] claim_id;
        logic [CAPACITY-1:0] free_bits, owned, owned_next;
        math_t count, expected_count;

        if (IS_CELL) begin : cell_path
            assign {returns, return_id} = {cell_returns, returned_cells};
            assign {claims, claim_id} = {write_accept, write_id};
            assign free_bits = dut.cells.free_bits;
            assign count = math_t'(free_cells);
        end else begin : desc_path
            assign {returns, return_id} = {desc_returns, returned_descs};
            assign {claims, claim_id} = {reserve_commit, grant_desc};
            assign free_bits = dut.descriptors.free_bits;
            assign count = math_t'(free_desc);
            always @(posedge clk)
                if (active)
                    c_old_slots: assume($countones(reserve_commit) <= CAPACITY - $countones(owned));
        end

        always_comb begin
            owned_next = owned;
            for (int lane = 0; lane < SELECT_LANES; lane++)
                if (claims[lane])
                    owned_next[claim_id[lane]] = 1;
            for (int lane = 0; lane <= N_TX; lane++)
                if (returns[lane])
                    owned_next[return_id[lane]] = 0;
            expected_count = count - math_t'($countones(claims)) + math_t'($countones(returns));
        end

        for (genvar lane = 0; lane <= N_TX; lane++) begin : legal_return
            always @(posedge clk)
                if (active && returns[lane])
                    c_old_owner: assume(owned[return_id[lane]]);
            for (genvar prior = 0; prior < lane; prior++) begin : distinct
                always @(posedge clk)
                    if (active && returns[lane] && returns[prior])
                        c_unique_owner: assume(return_id[lane] != return_id[prior]);
            end
        end

        always @(posedge clk) begin
            if (!rst_n)
                owned <= '0;
            else if (ready)
                owned <= owned_next;
            if (history && rst_n) begin
                a_partition: assert(free_bits == ~owned);
                a_population: assert(count == math_t'($countones(free_bits)));
                a_capacity: assert(count + math_t'($countones(owned)) == math_t'(CAPACITY));
                if ($past(active))
                    a_count_delta: assert(count == $past(expected_count));
                if (!$past(rst_n))
                    a_reset_free: assert((&free_bits) && owned == '0 && count == math_t'(CAPACITY));
            end
        end
    end

    if (LEMMA == 3 || LEMMA == 4) begin : credit
        math_t [N_Q-1:0] added, returned, next_held;
        math_t next_unreserved, total;
        always_comb begin
            added = '0;
            returned = '0;
            next_held = '0;
            total = math_t'(unreserved);
            next_unreserved = math_t'(unreserved) + returned_credit - reserved_now;
            for (int queue_index = 0; queue_index < N_Q; queue_index++) begin
                for (int lane = 0; lane < N_RX; lane++)
                    if (reserve_commit[lane] && reserve_qid[lane] == qid_t'(queue_index))
                        added[queue_index] += math_t'(reserve_cells[lane]);
                for (int lane = 0; lane < N_TX; lane++)
                    if (tx_present[lane] && tx_qid[lane] == qid_t'(queue_index))
                        returned[queue_index] += math_t'(1);
                if (cleanup_retires && cleanup_qid == qid_t'(queue_index))
                    returned[queue_index] += cleanup_amount;
                next_held[queue_index] = math_t'(held[queue_index]) +
                                         added[queue_index] - returned[queue_index];
                total += math_t'(held[queue_index]);
            end
        end

        always @(posedge clk)
            if (active)
                c_old_reservation_budget: assume(reserved_now <= math_t'(unreserved));

        for (genvar queue_index = 0; queue_index < N_Q; queue_index++) begin : queues
            always @(posedge clk)
                if (active)
                    c_old_queue_credit: assume(returned[queue_index] <= math_t'(held[queue_index]));
        end

        if (LEMMA == 3) begin : deltas
            always @(posedge clk) begin
                if (active)
                    a_wide_unreserved: assert(math_t'(dut.accounting.unreserved_next) == next_unreserved);
                if (history && rst_n && $past(active))
                    a_stored_unreserved: assert(unreserved == cell_count_t'($past(next_unreserved)));
            end
            for (genvar queue_index = 0; queue_index < N_Q; queue_index++) begin : queues
                always @(posedge clk) begin
                    if (active)
                        a_wide_held: assert(math_t'(dut.accounting.g_held[queue_index].held_next) ==
                                            next_held[queue_index]);
                    if (history && rst_n && $past(active))
                        a_stored_held: assert(held[queue_index] == cell_count_t'($past(next_held[queue_index])));
                end
            end
        end else begin : conservation
            always @(posedge clk)
                if (history && rst_n) begin
                    a_total: assert(total == math_t'(N_CELL));
                    a_unreserved_bound: assert(math_t'(unreserved) <= math_t'(N_CELL));
                end
            for (genvar queue_index = 0; queue_index < N_Q; queue_index++) begin : queues
                always @(posedge clk)
                    if (history && rst_n)
                        a_held_bound: assert(math_t'(held[queue_index]) <= math_t'(N_CELL));
            end
        end
    end

    if (LEMMA == 5) begin : reserved
        math_t old_reserved, next_reserved;
        assign old_reserved = math_t'(free_cells) - math_t'(unreserved);
        assign next_reserved = old_reserved + reserved_now - math_t'(write_offer) +
                               math_t'(cleanup_returns_cell) - cleanup_amount;

        always @(posedge clk)
            if (active) begin
                c_old_reservation_budget: assume(reserved_now <= math_t'(unreserved));
                // These two premises are discharged by the caller lemma.
                c_staged_write: assume(!write_offer || old_reserved > 0);
                c_joint_spend: assume(math_t'(write_offer) + cleanup_amount <=
                                      old_reserved + math_t'(cleanup_returns_cell));
                a_staged_write: assert(write_accept == write_offer);
            end

        // Import the proved cell population and return contract. The latter
        // applies to each physical return independently of credit release.
        always @(posedge clk)
            if (active)
                c_cell_count: assume(math_t'(free_cells) == math_t'($countones(dut.cells.free_bits)));
        for (genvar lane = 0; lane <= N_TX; lane++) begin : legal_return
            always @(posedge clk)
                if (active && cell_returns[lane])
                    c_old_owner: assume(!dut.cells.free_bits[returned_cells[lane]]);
            for (genvar prior = 0; prior < lane; prior++) begin : distinct
                always @(posedge clk)
                    if (active && cell_returns[lane] && cell_returns[prior])
                        c_unique_owner: assume(returned_cells[lane] != returned_cells[prior]);
            end
        end

        always @(posedge clk)
            if (history && rst_n) begin
                a_reserved_range: assert(unreserved <= free_cells);
                a_partition: assert(math_t'(free_cells) ==
                                    math_t'(unreserved) + math_t'(reserved_free));
                if ($past(active))
                    a_reserved_delta: assert(math_t'(reserved_free) == $past(next_reserved));
            end
    end

    if (LEMMA == 6) begin : reset_and_lanes
        always @(posedge clk) begin
            if (history && rst_n) begin
                a_ready: assert(ready == $past(rst_n));
                if (!$past(rst_n))
                    a_reset: assert((&dut.cells.free_bits) && (&dut.descriptors.free_bits) &&
                        free_cells == cell_count_t'(N_CELL) && free_desc == desc_count_t'(N_DESC) &&
                        unreserved == cell_count_t'(N_CELL) && reserved_free == '0 && held == '0);
            end
            a_cell_routing: assert(dut.cells.return_present == cell_returns &&
                                   dut.cells.return_cell == returned_cells);
            a_desc_routing: assert(dut.descriptors.return_present == desc_returns &&
                                   dut.descriptors.return_desc == returned_descs);
            a_credit_routing: assert(dut.accounting.release_present == {cleanup_retires, tx_present} &&
                                     dut.accounting.release_qid == {cleanup_qid, tx_qid});
            a_cleanup_amount: assert(dut.accounting.release_cells[N_TX] == cleanup_released);
        end
        for (genvar lane = 0; lane < N_TX; lane++) begin : unit_tx
            always @(posedge clk)
                a_credit_per_cell: assert(dut.accounting.release_cells[lane] == cell_count_t'(1));
        end
    end

    if (LEMMA == 7) begin : caller
        math_t all_credit, all_materialized, old_reserved;
        always_comb begin
            all_credit = math_t'(other_credit);
            all_materialized = math_t'(other_materialized);
            if (write_offer) begin
                all_credit += math_t'(write_credit);
                all_materialized += math_t'(write_materialized);
            end
            if (cleanup_retires) begin
                all_credit += math_t'(cleanup_credit);
                all_materialized += math_t'(cleanup_materialized);
            end
        end
        assign old_reserved = math_t'(free_cells) - math_t'(unreserved);

        always @(posedge clk)
            if (active) begin
                // The caller partitions held credit and live physical cells
                // among the serviced owners and all remaining live frames.
                c_credit_partition: assume(all_credit + math_t'(unreserved) == math_t'(N_CELL));
                c_cell_partition: assume(all_materialized + math_t'(free_cells) == math_t'(N_CELL));
                c_other_frame_credit: assume(other_materialized <= other_credit);
                if (write_offer)
                    c_old_stage: assume(write_materialized < write_credit);
                if (cleanup_present && write_offer)
                    c_distinct_frames: assume(write_owner != cleanup_desc);
                if (cleanup_retires)
                    c_final_cleanup: assume(cleanup_released == cleanup_credit &&
                        cleanup_credit != 0 && cleanup_materialized == cell_count_t'(cleanup_returns_cell));
                else
                    c_no_early_release: assume(cleanup_released == 0);

                a_old_stage: assert(!write_offer || old_reserved > 0);
                a_joint_spend: assert(math_t'(write_offer) + cleanup_amount <=
                                      old_reserved + math_t'(cleanup_returns_cell));
            end
    end
endmodule
