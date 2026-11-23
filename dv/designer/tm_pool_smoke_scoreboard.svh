    class pool_scoreboard extends uvm_subscriber #(pool_edge_t);
        `uvm_component_utils(pool_scoreboard)

        pool_model model;
        pool_coverage coverage;
        sample_t state;
        result_t result;
        int previous_free_desc = -1;
        int returned_descriptor = -1;
        int trace_out, trace_in;
        int trace_edges;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            model = new;
            coverage = new;
        endfunction

        function void expect_fault(string expected, string actual);
            require(actual == expected, $sformatf("expected %s, observed %s", expected, actual));
            $display("EXPECTED %s", actual);
        endfunction

        function string count_error(counts_t actual, counts_t expected);
            if (actual.f != expected.f || actual.u != expected.u || actual.r != expected.r ||
                actual.d != expected.d) return "resource_conservation";
            if (actual.h != expected.h) return "merged_queue_delta";
            return "";
        endfunction

        function void compare_counts(counts_t actual, counts_t expected, string timing_point);
            string detector = count_error(actual, expected);
            if (detector != "") begin
                print_counts("observed", actual);
                print_counts("expected", expected);
                require(0, $sformatf("edge %0d %s %s", model.edge_index, timing_point, detector));
            end
        endfunction

        function void check_ranks(sample_t pre);
            bit [DESCRIPTORS-1:0] seen = '0;
            for (int rank = 0; rank < PORTS; ++rank) begin
                require(pre.rank_valid[rank] == (rank < int'(pre.counts.d)), "rank_availability");
                if (pre.rank_valid[rank]) begin
                    desc_t id = pre.rank_id[rank];
                    require(!model.desc_owner.exists(id) && !seen[id], "distinct_old_free_rank");
                    seen[id] = 1;
                end
            end
        endfunction

        function void reset_edge(pool_edge_t tr);
            counts_t abandoned = model.expected_counts();
            require(!tr.pre.ready && !tr.pre.write_accept, "reset_or_init_gating");
            require(tr.post.ready == tr.reset_n && !tr.pre.write_accept, "ready_at_released_edge");
            if (abandoned != EMPTY) begin
                if (abandoned.f == 0 && abandoned.d == 0) coverage.hit(RESET_FULL);
                else coverage.hit(RESET_MIXED);
                print_counts("reset pre", abandoned);
                print_counts("reset post", tr.post.counts);
            end
            model.clear();
            previous_free_desc = -1;
            compare_counts(tr.post.counts, EMPTY, "reset");
        endfunction

        function void check_inputs(pool_edge_t tr);
            batch_t batch = tr.intent;
            mask_t offered = '0;
            string detector = model.caller_return_error(batch);
            require(detector == "", detector);
            require(tr.pins.write_offer == (batch.write_token != 0 || batch.blocked_write), "write_offer");
            require(tr.pins.cleanup_present == (batch.cleanup.token != 0), "cleanup_presence");
            if (tr.pins.cleanup_present) begin
                pool_frame frame = model.owners[batch.cleanup.token];
                require(tr.pins.cleanup_has_cell == batch.cleanup.has_cell &&
                        tr.pins.cleanup_done == batch.cleanup.done, "cleanup_flags");
                if (batch.cleanup.has_cell)
                    require(tr.pins.cleanup_cell == batch.cleanup.address, "cleanup_cell_binding");
                if (batch.cleanup.done)
                    require(tr.pins.cleanup_desc == frame.descriptor && tr.pins.cleanup_qid == frame.qid &&
                            tr.pins.cleanup_released == batch.cleanup.released, "cleanup_binding");
            end
            for (int lane = 0; lane < PORTS; ++lane) begin
                request_t req = batch.requests[lane];
                retire_t tx = batch.tx[lane];
                if (req.present) begin
                    require(!offered[req.ingress] && model.ingress_available(req.ingress), "ingress_eligibility");
                    offered[req.ingress] = 1;
                end
                if (tr.pins.commit[lane])
                    require(req.present && req.cells == tr.pins.cells[lane] &&
                            req.qid == tr.pins.qid[lane], "committed_request_binding");
                require(tr.pins.tx_present[lane] == (tx.token != 0), "tx_presence");
                if (tr.pins.tx_present[lane]) begin
                    require(tx.address == tr.pins.tx_cell[lane] && tx.last == tr.pins.tx_final[lane] &&
                            tr.pins.tx_qid[lane] == model.owners[tx.token].qid, "tx_binding");
                    if (tx.last) require(tx.descriptor == tr.pins.tx_desc[lane], "tx_descriptor_binding");
                end
            end
        endfunction

        function void apply_reservations(pool_edge_t tr);
            int rank = 0;
            int credit = int'(tr.pre.counts.u);
            int retired_descriptor = returned_descriptor;
            for (int lane = 0; lane < PORTS; ++lane) begin
                desc_t id;
                if (!tr.pins.commit[lane]) continue;
                id = tr.pre.grant_desc[lane];
                require(rank < int'(tr.pre.counts.d) && tr.pre.rank_valid[rank] &&
                        id == tr.pre.rank_id[rank] && !model.desc_owner.exists(id),
                        $sformatf("committed_rank_projection edge=%0d lane=%0d rank=%0d id=%0d",
                                  model.edge_index, lane, rank, id));
                require(tr.pins.cells[lane] != 0 && int'(tr.pins.cells[lane]) <= MAX_FRAME_CELLS &&
                        int'(tr.pins.cells[lane]) <= credit, "old_committed_credit");
                credit -= int'(tr.pins.cells[lane]);
                result.tokens[lane] = model.reserve(tr.intent.requests[lane], id,
                                                    tr.pins.cells[lane], tr.pins.qid[lane]);
                if (previous_free_desc == 0 && int'(id) == retired_descriptor) coverage.hit(D_REUSE);
                ++rank;
            end
        endfunction

        function void apply_write(pool_edge_t tr);
            int token = tr.intent.write_token;
            if (tr.intent.blocked_write) begin
                require(tr.pre.counts.f == 0 && !tr.pre.write_accept, "empty_cell_pool_rejected_write");
                coverage.hit(F0_BLOCK);
                $display("EXPECTED empty_cell_pool_rejected_write");
            end
            require(tr.pre.write_accept == (token != 0), "materialization_acceptance");
            if (tr.pre.write_accept) begin
                require(model.old_cell_error(tr.pre.write_id) == "" && tr.pre.counts.r != 0 &&
                        model.can_write(token), "old_staged_reservation");
                result.address = int'(tr.pre.write_id);
                model.materialize(token, tr.pre.write_id);
            end
        endfunction

        function void apply_returns(pool_edge_t tr);
            returned_descriptor = -1;
            for (int lane = 0; lane < PORTS; ++lane) begin
                int token = tr.intent.tx[lane].token;
                if (!tr.pins.tx_present[lane]) continue;
                model.retire(token, lane, tr.pins.tx_cell[lane], tr.pins.tx_final[lane]);
                if (tr.pins.tx_final[lane]) returned_descriptor = int'(tr.pins.tx_desc[lane]);
            end
            if (tr.pins.cleanup_present)
                model.clean_up(tr.intent.cleanup.token, tr.pins.cleanup_has_cell,
                               tr.pins.cleanup_cell, tr.pins.cleanup_done);
        endfunction

        function void record_trace(pool_edge_t tr);
            if (trace_out != 0) $fdisplay(trace_out, "%h", tr);
            if (trace_in != 0) begin
                pool_edge_t reference_edge;
                int fields = $fscanf(trace_in, "%h", reference_edge);
                require(fields == 1 && tr === reference_edge,
                        $sformatf("replay edge mismatch at %0d", tr.index));
            end
            ++trace_edges;
        endfunction

        function void write(pool_edge_t tr);
            require(tr.index == model.edge_index, "missing_or_duplicate_sample");
            result = '{tokens:'0, address:-1};
            if (!tr.reset_n || !tr.pre.ready) begin
                reset_edge(tr);
            end else begin
                compare_counts(tr.pre.counts, model.expected_counts(), "pre");
                require(tr.pre.rank_valid == state.rank_valid && tr.pre.rank_id == state.rank_id,
                        "old_ranks_ignore_commit_and_returns");
                check_ranks(tr.pre);
                for (int lane = 0; lane < PORTS; ++lane) begin
                    int token = tr.intent.abort_marks[lane];
                    if (token != 0) begin
                        require(model.owners.exists(token) && model.owners[token].ingress == lane &&
                                model.owners[token].abort_edge < 0 &&
                                model.owners[token].assigned.size() < model.owners[token].count, "legal_abort_mark");
                        model.owners[token].abort_edge = model.edge_index;
                    end
                end
                check_inputs(tr);
                // Write eligibility uses the old owner state. Commit is applied after the
                // write check, and releases are applied after all old-free ID checks.
                apply_write(tr);
                apply_reservations(tr);
                apply_returns(tr);
                compare_counts(tr.post.counts, model.expected_counts(), "post");
                coverage.observe(tr);
                previous_free_desc = int'(tr.pre.counts.d);
            end
            state = tr.post;
            record_trace(tr);
            ++model.edge_index;
        endfunction

        function void print_counts(string label_text, counts_t counts);
            string held = "";
            for (int q = 0; q < QUEUES; ++q)
                held = {held, q == 0 ? "" : ",", $sformatf("%0d", counts.h[q])};
            $display("STATE %s F=%0d U=%0d R=%0d D=%0d H=%s",
                     label_text, counts.f, counts.u, counts.r, counts.d, held);
        endfunction

        function void witness(string name, int f, int u, int d, int r);
            counts_t x = state.counts;
            require(int'(x.f) == f && int'(x.u) == u && int'(x.d) == d && int'(x.r) == r, name);
            print_counts(name, x);
        endfunction

        function void drained();
            require(model.owners.num() == 0 && model.desc_owner.num() == 0 && model.cell_owner.num() == 0,
                    "owner_drain");
            compare_counts(state.counts, EMPTY, "drain");
            coverage.hit(PERFECT_DRAIN);
        endfunction

        function void finish_trace();
            if (trace_in != 0) begin
                string extra;
                require($fscanf(trace_in, "%s", extra) < 1 && $feof(trace_in), "replay_has_extra_edges");
                $fclose(trace_in);
                $display("REPLAY_MATCH edges=%0d", trace_edges);
            end
            if (trace_out != 0) $fclose(trace_out);
        endfunction

        function void summary();
            print_counts("drained", state.counts);
            coverage.summary(model.edge_index);
        endfunction
    endclass
