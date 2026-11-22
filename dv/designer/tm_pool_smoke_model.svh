    class pool_frame;
        int ingress, count, birth, abort_edge = -1;
        qid_t qid;
        desc_t descriptor;
        logic [15:0] tag;
        int tx_ready, retired;
        cell_t assigned[$];
    endclass

    class pool_model;
        pool_frame owners[int];
        int cell_owner[cell_t], desc_owner[desc_t];
        int ingress_ready[PORTS], tx_ready[PORTS], tx_owner[PORTS];
        int next_token = 1;
        int edge_index;

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

        function void release_owner(int token);
            desc_owner.delete(owners[token].descriptor);
            owners.delete(token);
        endfunction

        function void clear();
            owners.delete();
            cell_owner.delete();
            desc_owner.delete();
            ingress_ready = '{default:0};
            tx_owner = '{default:0};
            tx_ready = '{default:0};
        endfunction

        function int reserve(request_t req, desc_t id, count_t count, qid_t qid);
            pool_frame frame = new;
            int token = next_token++;
            frame.ingress = req.ingress;
            frame.tag = req.tag;
            frame.qid = qid;
            frame.count = int'(count);
            frame.descriptor = id;
            frame.birth = edge_index;
            if (req.first_abort) frame.abort_edge = edge_index;
            desc_owner[id] = token;
            owners[token] = frame;
            ingress_ready[frame.ingress] = edge_index + 8 * frame.count;
            return token;
        endfunction

        function void materialize(int token, cell_t id);
            pool_frame frame = owners[token];
            cell_owner[id] = token;
            frame.assigned.push_back(id);
            if (frame.assigned.size() == frame.count) frame.tx_ready = edge_index + 16;
        endfunction

        function void retire(int token, int lane, cell_t id, bit last);
            cell_owner.delete(id);
            tx_ready[lane] = edge_index + 8;
            if (last) begin
                tx_owner[lane] = 0;
                release_owner(token);
            end else begin
                tx_owner[lane] = token;
                ++owners[token].retired;
            end
        endfunction

        function void clean_up(int token, bit has_cell, cell_t id, bit done);
            pool_frame frame = owners[token];
            if (has_cell) begin
                cell_owner.delete(id);
                void'(frame.assigned.pop_back());
            end
            if (done) begin
                if (ingress_ready[frame.ingress] < edge_index + 1)
                    ingress_ready[frame.ingress] = edge_index + 1;
                release_owner(token);
            end
        endfunction
    endclass
