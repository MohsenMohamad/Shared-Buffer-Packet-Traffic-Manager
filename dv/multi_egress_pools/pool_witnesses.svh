    typedef struct packed {
        int grants;
        bit [N_Q-1:0] queues;
        bit [N_TX:0] cell_mask;
        bit [N_TX:0] desc_mask;
        bit reused_cell;
        bit reused_desc;
        bit reset_with_abort;
        bit reset_id_reused;
        bit grant_and_abort;
        bit staged_abort;
        bit repeated_tag;
        bit first_ids;
`ifdef POOL_CANDIDATE
        bit sparse_grants;
        bit inactive_payload;
        int caller_guard;
`endif
    } edge_features_t;

    // The directed fixture declares where to look. This class derives what
    // happened from the checked edges and their observed history.
    class pool_witnesses;
        owner_t reset_owners[cell_id_t];
        owner_t tag_owners[qid_t][opaque_tag_t];
        bit [N_CELL-1:0] previous_cell_returns, earlier_cell_returns;
        bit [N_DESC-1:0] previous_desc_returns;
        pool_counts_t previous_pre;
        bit previous_dispatch;
        bit repeated_tag, saw_zero_desc, saw_zero_cell;

        function void before_reset(pool_model model);
            bit had_abort = 0;
            reset_owners.delete();
            foreach (model.descriptors[id])
                if (model.descriptors[id].phase == ABORTED_FRAME)
                    had_abort = 1;
            if (had_abort)
                foreach (model.cells[address])
                    if (model.cells[address].assigned)
                        reset_owners[cell_id_t'(address)] = model.cells[address].owner;
        endfunction

        function edge_features_t observe(edge_batch_t batch);
            edge_features_t observed = '0;
            observed.reset_with_abort = reset_owners.num() != 0;
            for (int lane = 0; lane < N_RX; ++lane) begin
                admission_t grant = batch.admission[lane];
                owner_t owner;
                if (!grant.present || grant.result != GRANT)
                    continue;
                owner = '{grant.frame, grant.qid, grant.desc, grant.metadata.tag_value};
                ++observed.grants;
                observed.queues[grant.qid] = 1;
                observed.reused_desc |= previous_desc_returns[grant.desc];
                if (grant.desc == 0)
                    saw_zero_desc = 1;
                for (int ingress = 0; ingress < N_RX; ++ingress)
                    if (batch.abort_mark[ingress].present && batch.abort_mark[ingress].owner == owner)
                        observed.grant_and_abort = 1;
                if (tag_owners.exists(owner.qid) != 0 && tag_owners[owner.qid].exists(owner.tag_value) != 0 &&
                    tag_owners[owner.qid][owner.tag_value].frame != owner.frame)
                    repeated_tag = 1;
                tag_owners[owner.qid][owner.tag_value] = owner;
            end
            if (batch.cell_write.present) begin
                observed.reused_cell = previous_cell_returns[batch.cell_write.address];
                if (batch.cell_write.address == 0)
                    saw_zero_cell = 1;
                for (int ingress = 0; ingress < N_RX; ++ingress)
                    if (batch.abort_mark[ingress].present &&
                        batch.abort_mark[ingress].owner == batch.cell_write.owner)
                        observed.staged_abort = 1;
            end
            for (int lane = 0; lane <= N_TX; ++lane) begin
                cell_return_t cell_event = batch.cell_return[lane];
                descriptor_return_t desc_event = batch.descriptor_return[lane];
                observed.cell_mask[lane] = cell_event.present;
                observed.desc_mask[lane] = desc_event.present;
                if (cell_event.present && reset_owners.exists(cell_event.address) != 0) begin
                    owner_t old_owner = reset_owners[cell_event.address];
                    observed.reset_id_reused |= old_owner.desc == cell_event.owner.desc &&
                        old_owner.tag_value == cell_event.owner.tag_value &&
                        old_owner.frame.epoch != cell_event.owner.frame.epoch;
                end
            end
            observed.repeated_tag = repeated_tag;
            observed.first_ids = saw_zero_desc && saw_zero_cell;
            return observed;
        endfunction

        function void remember(edge_batch_t batch, pool_counts_t pre);
            earlier_cell_returns = previous_cell_returns;
            previous_cell_returns = '0;
            previous_desc_returns = '0;
            previous_dispatch = 0;
            for (int lane = 0; lane <= N_TX; ++lane) begin
                if (batch.cell_return[lane].present)
                    previous_cell_returns[batch.cell_return[lane].address] = 1;
                if (batch.descriptor_return[lane].present)
                    previous_desc_returns[batch.descriptor_return[lane].owner.desc] = 1;
            end
            for (int lane = 0; lane < N_TX; ++lane)
                previous_dispatch |= batch.dispatch[lane].present;
            previous_pre = pre;
        endfunction

        function bit matches_witness(string name, edge_batch_t batch, edge_features_t obs,
                             pool_counts_t pre, pool_counts_t post);
            int desc_returns = $countones(obs.desc_mask);
            int cell_returns = $countones(obs.cell_mask);
            logic [N_TX:0] highest_lane = (N_TX+1)'(1) << (N_TX-1);
            logic [N_TX:0] sparse_lanes = highest_lane | ((N_TX+1)'(1) << N_TX);
            int returns, alloc, bucket, origin;
            bit high_desc = 0, high_cell = 0;
            if ($sscanf(name, "descriptor:%d:%d:%d:%d", returns, alloc, bucket, origin) == 4)
                return desc_returns == returns && obs.grants == alloc &&
                    occupancy_bucket(int'(pre.descriptor_free), N_DESC) == bucket &&
                    return_source(obs.desc_mask) == origin;
            if ($sscanf(name, "cell:%d:%d:%d:%d", returns, alloc, bucket, origin) == 4)
                return cell_returns == returns && int'(batch.cell_write.present) == alloc &&
                    occupancy_bucket(int'(pre.physical_free), N_CELL) == bucket &&
                    return_source(obs.cell_mask) == origin;

            case (name)
                "descriptor-empty-return": return pre.descriptor_free == 0 && obs.grants == 0 && desc_returns == 1;
                "descriptor-one-prefix": return pre.descriptor_free == 1 && obs.grants == 1 && desc_returns == 1;
                "descriptor-two-prefix": return pre.descriptor_free == 2 && obs.grants == 2 && desc_returns == 1;
                "descriptor-next-edge": return pre.descriptor_free == 1 && obs.grants == 1 && obs.reused_desc;
                "credit-next-edge": return previous_pre.unreserved == 0 && pre.unreserved == 1 && post.unreserved == 0;
                "cell-one-exchange": return pre.physical_free == 1 && post.physical_free == 1 &&
                    batch.cell_write.present && cell_returns == 1;
                "cell-next-edge": return pre.physical_free == 1 && batch.cell_write.present &&
                    earlier_cell_returns[batch.cell_write.address];
                "reserved-write-zero-U": return pre.unreserved == 0 && pre.reserved_free > 0 &&
                    batch.cell_write.present;
                "full-return": return desc_returns == N_TX+1 && cell_returns == N_TX+1;
                "highest-return": return obs.desc_mask == highest_lane && obs.cell_mask == highest_lane;
                "sparse-cleanup": return obs.desc_mask == sparse_lanes && obs.cell_mask == sparse_lanes;
                "full-grant-same-q", "full-grant-different-q": return obs.grants == N_RX &&
                    $countones(obs.queues) == (name == "full-grant-same-q" ? 1 : N_RX) &&
                    desc_returns == N_TX && cell_returns == N_TX && batch.cell_write.present;
                "grant-and-abort": return obs.grants == 1 && obs.grant_and_abort;
                "zero-cell-cleanup": return batch.cleanup.present && batch.cleanup.done && !obs.cell_mask[N_TX];
                "mark-with-staged-write": return batch.cell_write.present && obs.staged_abort;
                "nonfinal-abort-reclaim": return batch.cleanup.present && !batch.cleanup.done &&
                    post.physical_free == pre.physical_free + 1 && post.reserved_free == pre.reserved_free + 1 &&
                    post.unreserved == pre.unreserved && post.queue_credit == pre.queue_credit;
                "active-abort-reset": return !batch.present && pre.assigned > 0 && pre.reserved_free > 0 &&
                    obs.reset_with_abort;
                "epoch-reused-cell-desc-tag": return obs.reset_id_reused;
                "bound-without-final": return pre == post && desc_returns == 0 && previous_dispatch;
                "repeated-tag-shared-queue": return obs.repeated_tag;
                "zero-and-highest-IDs": begin
                    for (int lane = 0; lane <= N_TX; ++lane) begin
                        if (batch.descriptor_return[lane].present &&
                            int'(batch.descriptor_return[lane].owner.desc) == N_DESC-1)
                            high_desc = 1;
                        if (batch.cell_return[lane].present && int'(batch.cell_return[lane].address) == N_CELL-1)
                            high_cell = 1;
                    end
                    return obs.first_ids && high_desc && high_cell;
                end
`ifdef POOL_CANDIDATE
                "sparse-grants": return obs.sparse_grants && obs.grants == N_RX - 1;
                "live-cell-next-edge": return obs.reused_cell;
                "stale-epoch-input": return obs.caller_guard == 2 && pre == post;
                "forged-final-input": return obs.caller_guard == 3 && pre == post;
                "absent-fields": return obs.inactive_payload && pre == post && !has_events(batch);
`else
                "absent-fields": return batch != normalize(batch);
`endif
                "exact-drain": return post.physical_free == N_CELL && post.descriptor_free == N_DESC;
                default: return 0;
            endcase
        endfunction
    endclass
