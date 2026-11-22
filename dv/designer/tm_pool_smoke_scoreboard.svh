    class pool_frame;
        int ingress, count, birth, abort_edge = -1;
        qid_t qid;
        desc_t descriptor;
        logic [15:0] tag;
        int tx_ready, retired;
        cell_t assigned[$];
    endclass

    class pool_scoreboard extends uvm_subscriber #(pool_edge_t);
        `uvm_component_utils(pool_scoreboard)

        pool_frame owners[int];
        int cell_owner[cell_t], desc_owner[desc_t];
        int ingress_ready[PORTS], tx_ready[PORTS], tx_owner[PORTS];
        int next_token = 1;
        int edge_index;
        sample_t state;
        result_t result;
        int hits[bin_t];
        int active_edges, grants, writes, retirements, completions;
        int previous_free_desc = -1;
        int returned_descriptor = -1;
        int trace_out, trace_in;
        int trace_edges;

        covergroup edge_bins with function sample(bin_t kind);
            observed: coverpoint kind;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            edge_bins = new;
        endfunction

        function void hit(bin_t kind);
            if (!hits.exists(kind)) hits[kind] = 0;
            ++hits[kind];
            edge_bins.sample(kind);
        endfunction

        function int observed(bin_t kind);
            return hits.exists(kind) ? hits[kind] : 0;
        endfunction

        function void need(bin_t kind);
            require(observed(kind) != 0, {"missing coverage ", kind.name()});
        endfunction

        function void expect_fault(string expected, string actual);
            require(actual == expected, $sformatf("expected %s, observed %s", expected, actual));
            $display("EXPECTED %s", actual);
        endfunction

        function bit ingress_available(int ingress, batch_t pending = '0);
            int staged = 0;
            if (edge_index < ingress_ready[ingress]) return 0;
            foreach (owners[token]) begin
                pool_frame frame = owners[token];
                if (frame.ingress != ingress) continue;
                if (frame.abort_edge >= 0 || pending.abort_marks[ingress] == token) return 0;
                staged += frame.count - frame.assigned.size();
            end
            return staged < 4;
        endfunction

        function bit can_write(int token, batch_t pending = '0);
            pool_frame frame = owners[token];
            if (frame.abort_edge >= 0 || pending.abort_marks[frame.ingress] == token ||
                frame.assigned.size() == frame.count ||
                edge_index < frame.birth + 8 * (frame.assigned.size() + 1))
                return 0;
            foreach (owners[older]) begin
                pool_frame first = owners[older];
                if (older >= token) break;
                if (first.ingress == frame.ingress && first.abort_edge < 0 &&
                    pending.abort_marks[first.ingress] != older && first.assigned.size() < first.count)
                    return 0;
            end
            return 1;
        endfunction

        function bit can_retire(int token, int lane);
            pool_frame frame = owners[token];
            return frame.abort_edge < 0 && int'(frame.qid) / 4 == lane &&
                   frame.assigned.size() == frame.count && edge_index >= frame.tx_ready &&
                   edge_index >= tx_ready[lane] && (tx_owner[lane] == 0 || tx_owner[lane] == token);
        endfunction

        function retire_t retirement(int token);
            pool_frame frame = owners[token];
            return '{token, frame.assigned[frame.retired], frame.descriptor, frame.retired + 1 == frame.count};
        endfunction

        function cleanup_t reclaim(int token);
            pool_frame frame = owners[token];
            int size = frame.assigned.size();
            return '{token, size != 0 ? frame.assigned[size - 1] : '0,
                     size <= 1 ? count_t'(frame.count) : '0, size != 0, size <= 1};
        endfunction

        function string old_cell_error(cell_t address);
            return cell_owner.exists(address) ? "old_free_cell" : "";
        endfunction

        function string caller_return_error(batch_t batch);
            bit [CELLS-1:0] returned_cells = '0;
            bit [DESCRIPTORS-1:0] returned_descriptors = '0;
            for (int lane = 0; lane < PORTS; ++lane) begin
                retire_t tx = batch.tx[lane];
                if (tx.token == 0) continue;
                if (!cell_owner.exists(tx.address) || cell_owner[tx.address] != tx.token)
                    return "current_owner";
                if (returned_cells[tx.address]) return "duplicate_cell";
                returned_cells[tx.address] = 1;
                if (!can_retire(tx.token, lane) || tx.address != retirement(tx.token).address)
                    return "legal_tx_retirement";
                if (tx.last != retirement(tx.token).last) return "real_final_retirement";
                if (tx.last) begin
                    if (!desc_owner.exists(tx.descriptor) || desc_owner[tx.descriptor] != tx.token)
                        return "current_descriptor_owner";
                    if (returned_descriptors[tx.descriptor]) return "duplicate_descriptor";
                    returned_descriptors[tx.descriptor] = 1;
                end
            end
            if (batch.cleanup.token != 0) begin
                int token = batch.cleanup.token;
                if (batch.cleanup.has_cell) begin
                    cell_t address = batch.cleanup.address;
                    if (!cell_owner.exists(address) || cell_owner[address] != token) return "current_owner";
                    if (returned_cells[address]) return "duplicate_cell";
                end
                if (!owners.exists(token)) return "current_owner";
                if (owners[token].abort_edge < 0 || edge_index <= owners[token].abort_edge)
                    return "legal_cleanup_edge";
                if (batch.cleanup != reclaim(token)) return "cleanup_delta";
                if (batch.cleanup.done && returned_descriptors[owners[token].descriptor])
                    return "duplicate_descriptor";
            end
            return "";
        endfunction

        function counts_t expected_counts();
            counts_t expected = EMPTY;
            int unsigned credits = CELLS;
            int unsigned queue_credits[QUEUES] = '{default:0};
            foreach (owners[token]) begin
                pool_frame frame = owners[token];
                int live_credit = frame.count - frame.retired;
                queue_credits[frame.qid] += live_credit;
                credits -= live_credit;
            end
            foreach (queue_credits[q]) expected.h[q] = count_t'(queue_credits[q]);
            require(credits <= CELLS && CELLS - cell_owner.num() >= credits,
                    "model_credit_conservation");
            expected.f = count_t'(CELLS - cell_owner.num());
            expected.d = desc_count_t'(DESCRIPTORS - desc_owner.num());
            expected.u = count_t'(credits);
            expected.r = expected.f - expected.u;
            return expected;
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
                require(0, $sformatf("edge %0d %s %s", edge_index, timing_point, detector));
            end
        endfunction

        function void check_ranks(sample_t pre);
            bit [DESCRIPTORS-1:0] seen = '0;
            for (int rank = 0; rank < PORTS; ++rank) begin
                require(pre.rank_valid[rank] == (rank < int'(pre.counts.d)), "rank_availability");
                if (pre.rank_valid[rank]) begin
                    desc_t id = pre.rank_id[rank];
                    require(!desc_owner.exists(id) && !seen[id], "distinct_old_free_rank");
                    seen[id] = 1;
                end
            end
        endfunction

        function void release_owner(int token);
            desc_owner.delete(owners[token].descriptor);
            owners.delete(token);
        endfunction

        function void reset_edge(pool_edge_t tr);
            counts_t abandoned = expected_counts();
            require(!tr.pre.ready && !tr.pre.write_accept, "reset_or_init_gating");
            require(tr.post.ready == tr.reset_n && !tr.pre.write_accept, "ready_at_released_edge");
            if (abandoned != EMPTY) begin
                if (abandoned.f == 0 && abandoned.d == 0) hit(RESET_FULL);
                else hit(RESET_MIXED);
                print_counts("reset pre", abandoned);
                print_counts("reset post", tr.post.counts);
            end
            owners.delete();
            cell_owner.delete();
            desc_owner.delete();
            ingress_ready = '{default:0};
            tx_owner = '{default:0};
            tx_ready = '{default:0};
            previous_free_desc = -1;
            compare_counts(tr.post.counts, EMPTY, "reset");
        endfunction

        function void check_inputs(pool_edge_t tr);
            batch_t batch = tr.intent;
            mask_t offered = '0;
            string detector = caller_return_error(batch);
            require(detector == "", detector);
            require(tr.pins.write_offer == (batch.write_token != 0 || batch.blocked_write), "write_offer");
            require(tr.pins.cleanup_present == (batch.cleanup.token != 0), "cleanup_presence");
            if (tr.pins.cleanup_present) begin
                pool_frame frame = owners[batch.cleanup.token];
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
                    require(!offered[req.ingress] && ingress_available(req.ingress), "ingress_eligibility");
                    offered[req.ingress] = 1;
                end
                if (tr.pins.commit[lane])
                    require(req.present && req.cells == tr.pins.cells[lane] &&
                            req.qid == tr.pins.qid[lane], "committed_request_binding");
                require(tr.pins.tx_present[lane] == (tx.token != 0), "tx_presence");
                if (tr.pins.tx_present[lane]) begin
                    require(tx.address == tr.pins.tx_cell[lane] && tx.last == tr.pins.tx_final[lane] &&
                            tr.pins.tx_qid[lane] == owners[tx.token].qid, "tx_binding");
                    if (tx.last) require(tx.descriptor == tr.pins.tx_desc[lane], "tx_descriptor_binding");
                end
            end
        endfunction

        function void apply_reservations(pool_edge_t tr);
            int rank = 0;
            int credit = int'(tr.pre.counts.u);
            int retired_descriptor = returned_descriptor;
            for (int lane = 0; lane < PORTS; ++lane) begin
                pool_frame frame;
                desc_t id;
                int token;
                if (!tr.pins.commit[lane]) continue;
                id = tr.pre.grant_desc[lane];
                require(rank < int'(tr.pre.counts.d) && tr.pre.rank_valid[rank] &&
                        id == tr.pre.rank_id[rank] && !desc_owner.exists(id),
                        $sformatf("committed_rank_projection edge=%0d lane=%0d rank=%0d id=%0d",
                                  edge_index, lane, rank, id));
                require(tr.pins.cells[lane] != 0 && int'(tr.pins.cells[lane]) <= MAX_FRAME_CELLS &&
                        int'(tr.pins.cells[lane]) <= credit, "old_committed_credit");
                credit -= int'(tr.pins.cells[lane]);
                frame = new;
                frame.ingress = tr.intent.requests[lane].ingress;
                frame.tag = tr.intent.requests[lane].tag;
                frame.qid = tr.pins.qid[lane];
                frame.count = int'(tr.pins.cells[lane]);
                frame.descriptor = id;
                frame.birth = edge_index;
                if (tr.intent.requests[lane].first_abort) frame.abort_edge = edge_index;
                token = next_token++;
                result.tokens[lane] = token;
                desc_owner[id] = token;
                owners[token] = frame;
                ingress_ready[frame.ingress] = edge_index + 8 * frame.count;
                if (previous_free_desc == 0 && int'(id) == retired_descriptor) hit(D_REUSE);
                ++rank;
            end
        endfunction

        function void apply_write(pool_edge_t tr);
            int token = tr.intent.write_token;
            if (tr.intent.blocked_write) begin
                require(tr.pre.counts.f == 0 && !tr.pre.write_accept, "empty_cell_pool_rejected_write");
                hit(F0_BLOCK);
                $display("EXPECTED empty_cell_pool_rejected_write");
            end
            require(tr.pre.write_accept == (token != 0), "materialization_acceptance");
            if (tr.pre.write_accept) begin
                pool_frame frame = owners[token];
                require(old_cell_error(tr.pre.write_id) == "" && tr.pre.counts.r != 0 &&
                        can_write(token), "old_staged_reservation");
                result.address = int'(tr.pre.write_id);
                cell_owner[tr.pre.write_id] = token;
                frame.assigned.push_back(tr.pre.write_id);
                if (frame.assigned.size() == frame.count) frame.tx_ready = edge_index + 16;
                ++writes;
            end
        endfunction

        function void apply_returns(pool_edge_t tr);
            returned_descriptor = -1;
            for (int lane = 0; lane < PORTS; ++lane) begin
                int token = tr.intent.tx[lane].token;
                if (!tr.pins.tx_present[lane]) continue;
                cell_owner.delete(tr.pins.tx_cell[lane]);
                tx_ready[lane] = edge_index + 8;
                if (tr.pins.tx_final[lane]) begin
                    tx_owner[lane] = 0;
                    returned_descriptor = int'(tr.pins.tx_desc[lane]);
                    release_owner(token);
                end else begin
                    tx_owner[lane] = token;
                    ++owners[token].retired;
                end
            end
            if (tr.pins.cleanup_present) begin
                int token = tr.intent.cleanup.token;
                pool_frame frame = owners[token];
                if (tr.pins.cleanup_has_cell) begin
                    cell_owner.delete(tr.pins.cleanup_cell);
                    void'(frame.assigned.pop_back());
                end
                if (tr.pins.cleanup_done) begin
                    if (ingress_ready[frame.ingress] < edge_index + 1)
                        ingress_ready[frame.ingress] = edge_index + 1;
                    release_owner(token);
                    ++completions;
                end
            end
        endfunction

        function void sample_coverage(pool_edge_t tr);
            int committed = $countones(tr.pins.commit);
            int tx = $countones(tr.pins.tx_present);
            int finished = $countones(tr.pins.tx_present & tr.pins.tx_final);
            bit completed_cleanup = tr.pins.cleanup_present && tr.pins.cleanup_done;
            int returned = tx + int'(tr.pins.cleanup_present && tr.pins.cleanup_has_cell);
            bit denied = 0;
            bit absent = 0;
            if (tr.pre.counts.d == 0 && finished != 0 && committed == 0) hit(D0_RETURN);
            if (tr.pre.counts.d == 1 && finished != 0 && committed == 1) hit(D1_RETURN);
            if (tr.pre.counts.d == 2 && finished != 0 && committed == 2) hit(D2_RETURN);
            if (tr.pre.counts.u == 0 && (tx != 0 || completed_cleanup)) hit(U0_RETURN);
            if (tr.pre.counts.f == 1 && tr.pre.counts.r == 1 && tr.pre.write_accept && tx != 0)
                hit(F1_EXCHANGE);
            if (committed == PORTS && tr.pre.write_accept && tx == PORTS) hit(ALL_GRANTS);
            if (returned == PORTS + 1 && finished == PORTS && completed_cleanup) hit(ALL_RETURNS);
            if (tx == 1 && tr.pins.tx_present[PORTS - 1]) hit(HIGH_TX);
            if (tx != 0 && tx < PORTS) hit(SPARSE_TX);
            if (tx + int'(tr.pins.cleanup_present) > 1) hit(PARALLEL_RETURNS);
            if (committed != 0 && (tx != 0 || tr.pins.cleanup_present)) hit(GRANT_RETURN);
            if (tr.pins.cleanup_present && !tr.pins.cleanup_done) hit(PARTIAL_CLEANUP);
            if (completed_cleanup && !tr.pins.cleanup_has_cell) hit(ZERO_CLEANUP);
            for (int lane = 0; lane < PORTS; ++lane) begin
                if (tr.pins.commit[lane]) begin
                    if (denied) hit(DENIED_HOLE);
                    if (absent) hit(ABSENT_HOLE);
                end else if (tr.intent.requests[lane].present) denied = 1;
                else absent = 1;
            end
            if (committed != 0 || tr.pre.write_accept || tx != 0 || tr.pins.cleanup_present)
                ++active_edges;
            grants += committed;
            retirements += tx;
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
            require(tr.index == edge_index, "missing_or_duplicate_sample");
            result = '{tokens:'0, address:-1};
            if (!tr.reset_n || !tr.pre.ready) begin
                reset_edge(tr);
            end else begin
                compare_counts(tr.pre.counts, expected_counts(), "pre");
                require(tr.pre.rank_valid == state.rank_valid && tr.pre.rank_id == state.rank_id,
                        "old_ranks_ignore_commit_and_returns");
                check_ranks(tr.pre);
                for (int lane = 0; lane < PORTS; ++lane) begin
                    int token = tr.intent.abort_marks[lane];
                    if (token != 0) begin
                        require(owners.exists(token) && owners[token].ingress == lane &&
                                owners[token].abort_edge < 0 &&
                                owners[token].assigned.size() < owners[token].count, "legal_abort_mark");
                        owners[token].abort_edge = edge_index;
                    end
                end
                check_inputs(tr);
                // Write eligibility uses the old owner state. Commit is applied after the
                // write check, and releases are applied after all old-free ID checks.
                apply_write(tr);
                apply_reservations(tr);
                apply_returns(tr);
                sample_coverage(tr);
                compare_counts(tr.post.counts, expected_counts(), "post");
                previous_free_desc = int'(tr.pre.counts.d);
            end
            state = tr.post;
            record_trace(tr);
            ++edge_index;
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
            require(owners.num() == 0 && desc_owner.num() == 0 && cell_owner.num() == 0,
                    "owner_drain");
            compare_counts(state.counts, EMPTY, "drain");
            hit(PERFECT_DRAIN);
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
            $display("TOTAL edge=%0d active=%0d grants=%0d write=%0d tx=%0d cleanup=%0d",
                     edge_index, active_edges, grants, writes, retirements, completions);
            for (bin_t kind = kind.first(); ; kind = kind.next()) begin
                $display("COVERAGE %s %0d", kind.name(), observed(kind));
                if (kind == kind.last()) break;
            end
        endfunction
    endclass
