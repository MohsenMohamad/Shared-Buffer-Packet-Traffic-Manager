    class pool_smoke_test extends uvm_test;
        `uvm_component_utils(pool_smoke_test)
        virtual tm_pool_smoke_if bus;
        pool_driver driver;
        pool_monitor monitor;
        pool_scoreboard scoreboard;
        string scenario;
        int unsigned seed, random_state;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            require(uvm_config_db#(virtual tm_pool_smoke_if)::get(this, "", "bus", bus), "missing pool interface");
            driver = new("driver", this);
            monitor = new("monitor", this);
            scoreboard = new("scoreboard", this);
            driver.bus = bus;
            monitor.bus = bus;
        endfunction

        function void connect_phase(uvm_phase phase);
            monitor.completed_edge.connect(scoreboard.analysis_export);
        endfunction

        function int below(int limit);
            random_state ^= random_state << 13;
            random_state ^= random_state >> 17;
            random_state ^= random_state << 5;
            return int'(random_state % unsigned'(limit));
        endfunction

        function desc_t descriptor(int token);
            return scoreboard.owners[token].descriptor;
        endfunction

        function desc_t ranked_descriptor(int rank);
            require(scoreboard.state.rank_valid[rank], "available_descriptor_rank");
            return scoreboard.state.rank_id[rank];
        endfunction

        task prepare(batch_t batch, mask_t mask);
            qid_t [PORTS-1:0] tx_queues = '0;
            qid_t cleanup_queue = '0;
            desc_t cleanup_descriptor = '0;
            string detector = scoreboard.caller_return_error(batch);
            require(detector == "", detector);
            for (int lane = 0; lane < PORTS; ++lane)
                if (batch.tx[lane].token != 0) tx_queues[lane] = scoreboard.owners[batch.tx[lane].token].qid;
            if (batch.cleanup.token != 0) begin
                cleanup_queue = scoreboard.owners[batch.cleanup.token].qid;
                cleanup_descriptor = descriptor(batch.cleanup.token);
            end
            driver.prepare(batch, mask, tx_queues, cleanup_queue, cleanup_descriptor);
        endtask

        task step(input batch_t batch = '0, input int alpha = -1);
            int previous_index = scoreboard.edge_index;
            prepare(batch, driver.choose_commits(batch, alpha));
            driver.pulse();
            require(scoreboard.edge_index == previous_index + 1, "edge_was_not_scored");
        endtask

        task reset_pool();
            batch_t activity = '0;
            activity.requests[0] = request(0, 0, 1);
            activity.write_token = 1;
            activity.tx[PORTS-1] = '{token:1, address:'0, descriptor:'0, last:1};
            activity.cleanup = '{token:1, address:'0, released:count_t'(1), has_cell:1, done:1};
            driver.prepare(activity, mask_t'(1), '0, '0, '0, 0);
            bus.rst_n = 0;
            repeat (2) driver.pulse();
            bus.rst_n = 1;
            driver.pulse();
            require(scoreboard.state.ready, "initialization_sample_missing");
        endtask

        task idle(int edges);
            repeat (edges) step();
        endtask

        task reserve(int ingress, int qid, int count, output int token, input bit abort_first = 0);
            batch_t batch = '0;
            batch.requests[0] = request(ingress, qid, count, abort_first);
            step(batch);
            token = scoreboard.result.tokens[0];
            require(token != 0, "directed_reservation");
        endtask

        task materialize(int token, int count);
            repeat (count) begin
                batch_t batch = '0;
                while (!scoreboard.can_write(token)) step();
                batch.write_token = token;
                step(batch);
            end
        endtask

        task mark_abort(int token);
            batch_t batch = '0;
            batch.abort_marks[scoreboard.owners[token].ingress] = token;
            step(batch);
        endtask

        task drain();
            int first_edge = scoreboard.edge_index;
            while (scoreboard.owners.num() != 0) begin
                batch_t batch = '0;
                foreach (scoreboard.owners[token]) begin
                    pool_frame frame = scoreboard.owners[token];
                    int lane = int'(frame.qid) / 4;
                    if (frame.abort_edge >= 0 && frame.abort_edge < scoreboard.edge_index && batch.cleanup.token == 0)
                        batch.cleanup = scoreboard.reclaim(token);
                    if (batch.write_token == 0 && scoreboard.can_write(token)) batch.write_token = token;
                    if (batch.tx[lane].token == 0 && scoreboard.can_retire(token, lane))
                        batch.tx[lane] = scoreboard.retirement(token);
                end
                step(batch);
                require(scoreboard.edge_index - first_edge < 20000, "bounded_drain");
            end
            scoreboard.drained();
        endtask

        task fill_descriptors(output int tokens[DESCRIPTORS]);
            foreach (tokens[index]) begin
                reserve(0, 0, 1, tokens[index]);
                materialize(tokens[index], 1);
            end
            idle(16);
        endtask

        task descriptor_scarcity();
            int tokens[DESCRIPTORS];
            int reused;
            batch_t batch = '0;
            batch_t retry_request = '0;
            fill_descriptors(tokens);
            scoreboard.witness("D=0 pre", CELLS-DESCRIPTORS, CELLS-DESCRIPTORS, 0, 0);
            require(scoreboard.desc_owner.exists('0) &&
                    scoreboard.desc_owner.exists(desc_t'(DESCRIPTORS-1)), "descriptor_ID_extremes");
            batch.requests[0] = request(0, 0, 1);
            batch.tx[0] = scoreboard.retirement(tokens[0]);
            step(batch);
            require(scoreboard.result.tokens[0] == 0, "D0_return_bypass");
            scoreboard.witness("D=0 post", CELLS-DESCRIPTORS+1, CELLS-DESCRIPTORS+1, 1, 0);
            retry_request.requests[0] = request(0, 0, 1);
            step(retry_request);
            reused = scoreboard.result.tokens[0];
            require(reused != 0 && descriptor(reused) == batch.tx[0].descriptor, "D_next_edge_reuse");
            idle(15);

            batch = '0;
            batch.tx[0] = scoreboard.retirement(tokens[1]);
            step(batch);
            idle(7);
            batch.requests[0] = request(0, 0, 1);
            batch.requests[1] = request(1, 0, 1);
            batch.tx[0] = scoreboard.retirement(tokens[2]);
            scoreboard.witness("D=1 pre", CELLS-DESCRIPTORS+2, CELLS-DESCRIPTORS+1, 1, 1);
            step(batch);
            require(scoreboard.result.tokens[0] != 0 && scoreboard.result.tokens[1] == 0, "D1_one_rank");
            scoreboard.witness("D=1 post", CELLS-DESCRIPTORS+3, CELLS-DESCRIPTORS+1, 1, 2);
            idle(7);

            batch = '0;
            batch.tx[0] = scoreboard.retirement(tokens[3]);
            step(batch);
            idle(7);
            batch.tx[0] = scoreboard.retirement(tokens[4]);
            for (int lane = 0; lane < PORTS; ++lane) batch.requests[lane] = request(lane, 0, 1);
            scoreboard.witness("D=2 pre", CELLS-DESCRIPTORS+4, CELLS-DESCRIPTORS+2, 2, 2);
            step(batch);
            for (int lane = 0; lane < PORTS; ++lane)
                require((scoreboard.result.tokens[lane] != 0) == (lane < 2), "D2_two_ranks");
            scoreboard.witness("D=2 post", CELLS-DESCRIPTORS+5, CELLS-DESCRIPTORS+1, 1, 4);
            scoreboard.need(D0_RETURN);
            scoreboard.need(D1_RETURN);
            scoreboard.need(D2_RETURN);
            scoreboard.need(D_REUSE);
            drain();
        endtask

        task fill_cells(bit withhold_last, output int first, last);
            int remaining = CELLS;
            first = 0;
            while (remaining > 0) begin
                int length = remaining < MAX_FRAME_CELLS ? remaining : MAX_FRAME_CELLS;
                reserve(0, 0, length, last);
                if (first == 0) first = last;
                remaining -= length;
                materialize(last, length - int'(remaining == 0 && withhold_last));
            end
        endtask

        task cell_scarcity();
            localparam int UNUSED_DESC = DESCRIPTORS - (CELLS+MAX_FRAME_CELLS-1)/MAX_FRAME_CELLS;
            int first, last, last_free = -1;
            batch_t batch = '0;
            fill_cells(1, first, last);
            idle(24);
            scoreboard.witness("F=1 U=0 pre", 1, 0, UNUSED_DESC, 1);
            batch.write_token = last;
            batch.requests[0] = request(1, 0, 1);
            batch.tx[0] = scoreboard.retirement(first);
            scoreboard.expect_fault("old_free_cell", scoreboard.old_cell_error(batch.tx[0].address));
            for (int candidate = 0; candidate < CELLS; ++candidate)
                if (!scoreboard.cell_owner.exists(cell_t'(candidate))) last_free = candidate;
            step(batch);
            require(scoreboard.result.address == last_free && last_free != int'(batch.tx[0].address) &&
                    scoreboard.result.tokens[0] == 0, "last_old_cell_without_credit_bypass");
            scoreboard.witness("F=1 U=1 post", 1, 1, UNUSED_DESC, 0);

            batch = '0;
            batch.requests[0] = request(0, 0, 2);
            batch.requests[PORTS-1] = request(1, QUEUES-1, 1);
            step(batch);
            require(scoreboard.result.tokens[0] == 0 && scoreboard.result.tokens[PORTS-1] != 0,
                    "resource_hole_keeps_rank");
            scoreboard.witness("credit reused", 1, 0, UNUSED_DESC-1, 1);
            materialize(scoreboard.result.tokens[PORTS-1], 1);
            scoreboard.witness("F=0 full occupancy", 0, 0, UNUSED_DESC-1, 0);
            require(scoreboard.cell_owner.exists('0) &&
                    scoreboard.cell_owner.exists(cell_t'(CELLS-1)), "cell_ID_extremes");
            batch = '0;
            batch.blocked_write = 1;
            step(batch);
            scoreboard.need(U0_RETURN);
            scoreboard.need(F1_EXCHANGE);
            scoreboard.need(F0_BLOCK);
            drain();
        endtask

        task make_tx_cohort(output token_t [PORTS-1:0] tokens);
            batch_t batch = '0;
            for (int lane = 0; lane < PORTS; ++lane) batch.requests[lane] = request(lane, 4*lane, 1);
            step(batch);
            tokens = scoreboard.result.tokens;
            for (int lane = 0; lane < PORTS; ++lane) materialize(tokens[lane], 1);
            idle(16);
        endtask

        task peak();
            token_t [PORTS-1:0] tx;
            int staged, aborting, old_stage;
            batch_t batch = '0;
            counts_t wrong_delta;
            make_tx_cohort(tx);
            reserve(0, 0, 1, staged);
            idle(8);
            batch.write_token = staged;
            for (int lane = 0; lane < PORTS; ++lane) begin
                batch.requests[lane] = request(lane, lane < 2 ? 0 : 4*lane+1, 1);
                batch.tx[lane] = scoreboard.retirement(tx[lane]);
            end
            scoreboard.witness("peak grant pre", CELLS-PORTS, CELLS-PORTS-1, DESCRIPTORS-PORTS-1, 1);
            step(batch);
            for (int lane = 0; lane < PORTS; ++lane) require(scoreboard.result.tokens[lane] != 0, "peak_grants");
            scoreboard.witness("peak grant post", CELLS-1, CELLS-PORTS-1, DESCRIPTORS-PORTS-1, PORTS);
            wrong_delta = scoreboard.state.counts;
            ++wrong_delta.h[0];
            scoreboard.expect_fault("merged_queue_delta", scoreboard.count_error(
                                    wrong_delta, scoreboard.expected_counts()));
            drain();

            make_tx_cohort(tx);
            reserve(PORTS-1, QUEUES-1, 2, aborting);
            materialize(aborting, 1);
            reserve(0, 0, 1, old_stage);
            mark_abort(aborting);
            idle(8);
            batch = '0;
            batch.write_token = old_stage;
            batch.cleanup = scoreboard.reclaim(aborting);
            for (int lane = 0; lane < PORTS; ++lane) begin
                batch.tx[lane] = scoreboard.retirement(tx[lane]);
                if (lane < PORTS-1) batch.requests[lane] = request(lane, 4*lane, 1);
            end
            require(!scoreboard.ingress_available(PORTS-1), "cleanup_ingress_ineligible");
            scoreboard.witness("peak return pre", CELLS-PORTS-1, CELLS-PORTS-3, DESCRIPTORS-PORTS-2, 2);
            step(batch);
            for (int lane = 0; lane < PORTS; ++lane)
                require((scoreboard.result.tokens[lane] != 0) == (lane < PORTS-1), "cleanup_parallel_ingresses");
            scoreboard.witness("peak return post", CELLS-1, CELLS-PORTS, DESCRIPTORS-PORTS, PORTS-1);
            require(scoreboard.ingress_available(PORTS-1), "cleanup_ingress_next_edge");
            drain();

            make_tx_cohort(tx);
            batch = '0;
            batch.tx[PORTS-1] = scoreboard.retirement(tx[PORTS-1]);
            scoreboard.witness("highest TX lane pre", CELLS-PORTS, CELLS-PORTS, DESCRIPTORS-PORTS, 0);
            step(batch);
            scoreboard.witness("highest TX lane post", CELLS-PORTS+1, CELLS-PORTS+1, DESCRIPTORS-PORTS+1, 0);
            scoreboard.need(ALL_GRANTS);
            scoreboard.need(ALL_RETURNS);
            scoreboard.need(HIGH_TX);
            drain();
        endtask

        task abort_and_stall();
            int aborting, malformed, retained;
            batch_t batch = '0, bad_residual;
            reserve(0, 0, 3, aborting);
            materialize(aborting, 2);
            mark_abort(aborting);
            batch.cleanup = scoreboard.reclaim(aborting);
            require(!batch.cleanup.done, "nonfinal_cleanup_trigger");
            scoreboard.witness("nonfinal cleanup pre", CELLS-2, CELLS-3, DESCRIPTORS-1, 1);
            step(batch);
            scoreboard.witness("nonfinal cleanup post", CELLS-1, CELLS-3, DESCRIPTORS-1, 2);
            batch.cleanup = scoreboard.reclaim(aborting);
            require(batch.cleanup.done && batch.cleanup.released == 3, "final_cleanup_trigger");
            bad_residual = batch;
            --bad_residual.cleanup.released;
            scoreboard.expect_fault("cleanup_delta", scoreboard.caller_return_error(bad_residual));
            step(batch);
            scoreboard.witness("final cleanup post", CELLS, CELLS, DESCRIPTORS, 0);

            while (!scoreboard.ingress_available(0)) idle(1);
            reserve(0, QUEUES-1, 3, malformed, 1);
            scoreboard.witness("reserve and abort", CELLS, CELLS-3, DESCRIPTORS-1, 3);
            batch.cleanup = scoreboard.reclaim(malformed);
            require(!batch.cleanup.has_cell && batch.cleanup.done, "zero_cell_cleanup_trigger");
            step(batch);
            scoreboard.witness("zero-cell cleanup post", CELLS, CELLS, DESCRIPTORS, 0);
            idle(24);

            reserve(0, 0, 1, retained);
            materialize(retained, 1);
            idle(16);
            scoreboard.witness("before stalled final", CELLS-1, CELLS-1, DESCRIPTORS-1, 0);
            idle(7);
            scoreboard.witness("after stalled final", CELLS-1, CELLS-1, DESCRIPTORS-1, 0);
            batch = '0;
            batch.tx[0] = scoreboard.retirement(retained);
            step(batch);
            scoreboard.need(PARTIAL_CLEANUP);
            scoreboard.need(ZERO_CLEANUP);
            drain();
        endtask

        task identity();
            int token, other, reused;
            batch_t legal = '0, forged, current_batch = '0, stale;
            reserve(0, 0, 1, token);
            reserve(1, 4, 1, other);
            require(scoreboard.owners[token].tag == scoreboard.owners[other].tag, "repeated_tags");
            materialize(token, 1);
            materialize(other, 1);
            idle(16);
            legal.tx[0] = scoreboard.retirement(token);
            legal.tx[1] = scoreboard.retirement(other);
            require(legal.tx[0].address == 0 && legal.tx[1].address != 0, "ID_zero_is_present");
            forged = legal;
            forged.tx[1].last = 0;
            scoreboard.expect_fault("real_final_retirement", scoreboard.caller_return_error(forged));
            step(legal);

            reserve(0, 0, 1, reused);
            materialize(reused, 1);
            idle(16);
            current_batch.tx[0] = scoreboard.retirement(reused);
            require(current_batch.tx[0].address == legal.tx[0].address && reused != token, "phys_id_reused");
            stale = current_batch;
            stale.tx[0] = legal.tx[0];
            scoreboard.expect_fault("current_owner", scoreboard.caller_return_error(stale));
            step(current_batch);
            drain();
        endtask

        task reset_owned();
            localparam int CELLS_PER_FRAME = CELLS / DESCRIPTORS;
            int token, aborting, staged, new_owner;
            cleanup_t stale;
            batch_t good = '0, bad = '0;
            repeat (DESCRIPTORS) begin
                reserve(0, 0, CELLS_PER_FRAME, token);
                materialize(token, CELLS_PER_FRAME);
            end
            scoreboard.witness("reset both pools fully owned", 0, 0, 0, 0);
            reset_pool();

            reserve(0, 0, 3, aborting);
            reserve(1, QUEUES-1, 2, staged);
            materialize(aborting, 1);
            materialize(staged, 1);
            mark_abort(aborting);
            scoreboard.witness("reset mixed", CELLS-2, CELLS-5, DESCRIPTORS-2, 3);
            stale = scoreboard.reclaim(aborting);
            reset_pool();

            reserve(0, 0, 1, new_owner);
            materialize(new_owner, 1);
            idle(16);
            good.tx[0] = scoreboard.retirement(new_owner);
            require(stale.address == good.tx[0].address, "reset_id_reuse");
            bad.cleanup = stale;
            scoreboard.expect_fault("current_owner", scoreboard.caller_return_error(bad));
            step(good);
            scoreboard.need(RESET_FULL);
            scoreboard.need(RESET_MIXED);
            drain();
        endtask

        task producer_boundary();
            localparam int ALPHA = 128;
            localparam int LONG_FRAME = (65+63)/64;
            localparam int SHORT_FRAME = (60+63)/64;
            int retiring, token, old_frames = 1;
            int remaining = CELLS-9;
            desc_t first_desc, second_desc;
            batch_t prefix = '0;
            reserve(1, 4, 1, retiring);
            materialize(retiring, 1);
            while (remaining > 0) begin
                int count = remaining < MAX_FRAME_CELLS ? remaining : MAX_FRAME_CELLS;
                reserve(0, 2, count, token);
                materialize(token, count);
                remaining -= count;
                ++old_frames;
            end
            idle(16);
            scoreboard.witness("producer pre", 8, 8, DESCRIPTORS-old_frames, 0);
            require(scoreboard.state.counts.h[0] == 0 && scoreboard.state.counts.h[1] == 0,
                    "producer_empty_targets");
            first_desc = ranked_descriptor(0);
            second_desc = ranked_descriptor(1);
            prefix.requests[0] = request(0, 0, LONG_FRAME);
            prefix.requests[1] = request(1, 0, LONG_FRAME);
            if (PORTS > 2) begin
                localparam int THIRD = PORTS-2;
                prefix.requests[THIRD] = request(THIRD, 1, SHORT_FRAME);
                prefix.tx[1] = scoreboard.retirement(retiring);
                step(prefix, ALPHA);
                require(scoreboard.result.tokens[0] != 0 && scoreboard.result.tokens[1] == 0 &&
                        scoreboard.result.tokens[THIRD] != 0 &&
                        descriptor(scoreboard.result.tokens[0]) == first_desc &&
                        descriptor(scoreboard.result.tokens[THIRD]) == second_desc, "producer_denial_skips_rank");
            end else begin
                step(prefix, ALPHA);
                require(scoreboard.result.tokens[0] != 0 && scoreboard.result.tokens[1] == 0 &&
                        descriptor(scoreboard.result.tokens[0]) == first_desc, "producer_threshold_denies_second");
                scoreboard.witness("producer first two", 8, 6, DESCRIPTORS-old_frames-1, 2);
                require(scoreboard.state.counts.h[0] == 2 && ranked_descriptor(0) == second_desc,
                        "producer_second_rank_retained");
                idle(16);
                prefix.requests[1] = request(1, 1, SHORT_FRAME);
                prefix.tx[1] = scoreboard.retirement(retiring);
                step(prefix, ALPHA);
                require(scoreboard.result.tokens[0] == 0 && scoreboard.result.tokens[1] != 0 &&
                        descriptor(scoreboard.result.tokens[1]) == second_desc, "producer_denial_skips_rank");
            end
            scoreboard.witness("producer post", 9, 6, DESCRIPTORS-old_frames-1, 3);
            require(scoreboard.state.counts.h[0] == 2 && scoreboard.state.counts.h[1] == 1 &&
                    scoreboard.state.counts.h[4] == 0, "producer_queue_deltas");
            drain();

            first_desc = ranked_descriptor(0);
            second_desc = ranked_descriptor(1);
            prefix = '0;
            if (PORTS > 2) prefix.requests[0] = request(0, 0, 1);
            prefix.requests[PORTS-1] = request(PORTS-1, 0, 1);
            step(prefix);
            require(scoreboard.result.tokens[PORTS-1] != 0 &&
                    descriptor(scoreboard.result.tokens[PORTS-1]) == (PORTS > 2 ? second_desc : first_desc),
                    "absent_lane_skips_rank");
            scoreboard.need(DENIED_HOLE);
            scoreboard.need(ABSENT_HOLE);
            drain();
        endtask

        task random_sequence();
            int first, last;
            int deadline, first_active;
            int old_completed;
            fill_cells(0, first, last);
            deadline = scoreboard.edge_index + 25000;
            first_active = scoreboard.active_edges;
            old_completed = scoreboard.completions;
            while (scoreboard.active_edges - first_active < 1024) begin
                int index = scoreboard.edge_index;
                int phase_index = (index / 160) % 4;
                batch_t batch = '0;
                int cursor, write_candidates = 0, cleanup_candidates = 0;
                foreach (scoreboard.owners[token]) begin
                    pool_frame frame = scoreboard.owners[token];
                    int assigned_cells = frame.assigned.size();
                    if (frame.abort_edge < 0 && assigned_cells > 0 && assigned_cells < frame.count &&
                        index < frame.birth + 8 * frame.count && below(80) == 0)
                        batch.abort_marks[frame.ingress] = token;
                end
                cursor = below(PORTS);
                for (int lane = 0; lane < PORTS; ++lane) begin
                    int ingress = (cursor + lane) % PORTS;
                    if (scoreboard.ingress_available(ingress, batch) && below(4) != 0) begin
                        // Preserve the historical generator's order of draws explicitly.
                        bit abort_first = below(10) == 0;
                        int count = 1 + below(MAX_FRAME_CELLS);
                        int qid = below(QUEUES);
                        batch.requests[lane] = request(ingress, qid, count, abort_first);
                    end
                end
                foreach (scoreboard.owners[token]) begin
                    pool_frame frame = scoreboard.owners[token];
                    int lane = int'(frame.qid) / 4;
                    if (scoreboard.can_write(token, batch)) begin
                        ++write_candidates;
                        if (below(write_candidates) == 0) batch.write_token = token;
                    end
                    if (frame.abort_edge >= 0 && frame.abort_edge < index) begin
                        ++cleanup_candidates;
                        if (below(cleanup_candidates) == 0 && phase_index != 0)
                            batch.cleanup = scoreboard.reclaim(token);
                    end
                    if (batch.tx[lane].token == 0 && scoreboard.can_retire(token, lane) &&
                        phase_index != 0 && below(4) < phase_index)
                        batch.tx[lane] = scoreboard.retirement(token);
                end
                step(batch);
                require(scoreboard.edge_index < deadline, "active_sequence_bound");
            end
            require(scoreboard.active_edges - first_active == 1024 &&
                    scoreboard.completions > old_completed, "random_active_or_completion");
            scoreboard.need(SPARSE_TX);
            scoreboard.need(PARTIAL_CLEANUP);
            scoreboard.need(PARALLEL_RETURNS);
            scoreboard.need(GRANT_RETURN);
            scoreboard.need(U0_RETURN);
            $display("RANDOM_ACTIVE %0d", scoreboard.active_edges - first_active);
            $display("RANDOM_TRIGGERS sparse=%0d cleanup=%0d partial=%0d overlap=%0d simultaneous=%0d u_pressure=%0d",
                scoreboard.observed(SPARSE_TX), scoreboard.completions, scoreboard.observed(PARTIAL_CLEANUP),
                scoreboard.observed(GRANT_RETURN), scoreboard.observed(PARALLEL_RETURNS),
                scoreboard.observed(U0_RETURN));
            scoreboard.print_counts("random pre-drain", scoreboard.state.counts);
            drain();
        endtask

        task make_return_neighbor(output batch_t batch);
            int tx, aborting;
            reserve(0, 0, 1, tx);
            reserve(1, 4, 2, aborting);
            materialize(tx, 1);
            materialize(aborting, 1);
            mark_abort(aborting);
            idle(16);
            batch = '0;
            batch.tx[0] = scoreboard.retirement(tx);
            batch.cleanup = scoreboard.reclaim(aborting);
        endtask

        task make_scarcity_neighbor(bit descriptor_limit, output batch_t batch);
            int retiring;
            if (descriptor_limit) begin
                int tokens[DESCRIPTORS];
                fill_descriptors(tokens);
                retiring = tokens[0];
            end else begin
                int last;
                fill_cells(0, retiring, last);
                idle(24);
            end
            batch = '0;
            batch.requests[0] = request(descriptor_limit ? 0 : 1, 0, 1);
            batch.tx[0] = scoreboard.retirement(retiring);
        endtask

        task rtl_negative();
            batch_t batch = '0;
            if (scenario inside {"rtl-overcommit-d", "rtl-overcommit-u"}) begin
                bit descriptor_limit = scenario == "rtl-overcommit-d";
                make_scarcity_neighbor(descriptor_limit, batch);
                step(batch);
                require(scoreboard.result.tokens[0] == 0, "legal_neighbor_denies_overcommit");
                drain();
                make_scarcity_neighbor(descriptor_limit, batch);
                require(driver.choose_commits(batch, -1) == '0, "producer_denies_invalid_commit");
                prepare(batch, mask_t'(1));
            end else if (scenario inside {"rtl-zero-count", "rtl-oversize-count"}) begin
                int neighbor;
                reserve(0, 0, 1, neighbor);
                materialize(neighbor, 1);
                drain();
                batch.requests[0] = request(0, 0, scenario == "rtl-zero-count" ? 0 : MAX_FRAME_CELLS+1);
                require(driver.choose_commits(batch, -1) == '0, "producer_denies_invalid_count");
                prepare(batch, mask_t'(1));
            end else begin
                make_return_neighbor(batch);
                step(batch);
                drain();
                make_return_neighbor(batch);
                prepare(batch, '0);
                case (scenario)
                    "rtl-duplicate-cell": bus.pins.cleanup_cell = batch.tx[0].address;
                    "rtl-duplicate-descriptor": bus.pins.cleanup_desc = batch.tx[0].descriptor;
                    "rtl-free-cell": begin
                        for (int id = 0; id < CELLS; ++id) begin
                            if (scoreboard.cell_owner.exists(cell_t'(id))) continue;
                            bus.pins.cleanup_cell = cell_t'(id);
                            break;
                        end
                    end
                    "rtl-free-descriptor": begin
                        for (int id = 0; id < DESCRIPTORS; ++id) begin
                            if (scoreboard.desc_owner.exists(desc_t'(id))) continue;
                            bus.pins.cleanup_desc = desc_t'(id);
                            break;
                        end
                    end
                    default: require(0, "unknown RTL fault case");
                endcase
            end
            $display("RTL_NEIGHBOR %s passed", scenario);
            $display("RTL_PROBE %s edge=%0d", scenario, scoreboard.edge_index);
            driver.pulse();
            require(0, "rtl_assertion_did_not_fire");
        endtask

        task run_phase(uvm_phase phase);
            string trace_path;
            phase.raise_objection(this);
            require($value$plusargs("case=%s", scenario) && $value$plusargs("seed=%d", seed) && seed != 0,
                    "missing scenario or seed");
            random_state = seed;
            driver.noise = seed ^ 32'hc49f18ad;
            if ($value$plusargs("trace_out=%s", trace_path)) begin
                scoreboard.trace_out = $fopen(trace_path, "w");
                require(scoreboard.trace_out != 0, "open replay output");
            end
            if ($value$plusargs("trace_in=%s", trace_path)) begin
                scoreboard.trace_in = $fopen(trace_path, "r");
                require(scoreboard.trace_in != 0, "open replay input");
            end
            reset_pool();
            case (scenario)
                "descriptor": descriptor_scarcity();
                "cell": cell_scarcity();
                "peak": peak();
                "abort": abort_and_stall();
                "identity": identity();
                "reset": reset_owned();
                "producer": producer_boundary();
                "random": random_sequence();
                default: rtl_negative();
            endcase
            drain();
            scoreboard.need(PERFECT_DRAIN);
            scoreboard.finish_trace();
            scoreboard.summary();
            $display("POOL_UVM_COMPLETE");
            phase.drop_objection(this);
        endtask
    endclass

    // RTL $fatal terminates the probe process. A second UVM invocation scores
    // that transcript so the host runner only transports a simulator verdict.
    class pool_fault_review extends uvm_test;
        `uvm_component_utils(pool_fault_review)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function string expected_detector(string scenario);
            case (scenario)
                "rtl-duplicate-cell": return "cell_return_distinct";
                "rtl-free-cell": return "cell_return_allocated";
                "rtl-duplicate-descriptor": return "descriptor_return_distinct";
                "rtl-free-descriptor": return "descriptor_return_allocated";
                "rtl-overcommit-d": return "old_descriptor_credit";
                "rtl-overcommit-u": return "old_credit";
                "rtl-zero-count", "rtl-oversize-count": return "reservation_count";
                default: return "";
            endcase
        endfunction

        function int find_text(string line, string needle);
            for (int offset = 0; offset <= line.len() - needle.len(); ++offset)
                if (line.substr(offset, offset + needle.len() - 1) == needle) return offset;
            return -1;
        endfunction

        function void review_log(string path, string scenario, string expected,
                                 ref bit neighbor, ref bit armed, ref int detections);
            int fd = $fopen(path, "r");
            string line;
            require(fd != 0, {"missing fault transcript ", path});
            while ($fgets(line, fd) != 0) begin
                int banner = find_text(line, "Assertion failed in ");
                if (find_text(line, {"RTL_NEIGHBOR ", scenario, " passed"}) == 0) neighbor = 1;
                if (find_text(line, {"RTL_PROBE ", scenario, " edge="}) == 0) armed = neighbor;
                if (banner >= 0) begin
                    string observed;
                    int label_offset = find_text(line, ": POOL_ASSERT ");
                    require(armed && label_offset > banner && find_text(line, ".dut.") >= 0,
                            {"unexpected assertion ", line});
                    require($sscanf(line.substr(label_offset + 14, line.len()-1), "%s", observed) == 1 &&
                            observed == expected, {"wrong RTL detector ", line});
                    ++detections;
                end
            end
            $fclose(fd);
        endfunction

        task run_phase(uvm_phase phase);
            string scenario, expected, stdout_path, stderr_path;
            int exit_code, detections = 0;
            bit neighbor = 0, armed = 0;
            phase.raise_objection(this);
            require($value$plusargs("case=%s", scenario) &&
                    $value$plusargs("fault_exit=%d", exit_code) && exit_code != 0 &&
                    $value$plusargs("fault_stdout=%s", stdout_path) &&
                    $value$plusargs("fault_stderr=%s", stderr_path), "missing probe execution");
            expected = expected_detector(scenario);
            require(expected != "", "unknown probe detector");
            review_log(stdout_path, scenario, expected, neighbor, armed, detections);
            review_log(stderr_path, scenario, expected, neighbor, armed, detections);
            require(neighbor && armed && detections == 1, "expected exactly one named RTL fault");
            $display("RTL_DETECTION %s legal_neighbor=1 exit=%0d", expected, exit_code);
            $display("POOL_UVM_COMPLETE");
            phase.drop_objection(this);
        endtask
    endclass
