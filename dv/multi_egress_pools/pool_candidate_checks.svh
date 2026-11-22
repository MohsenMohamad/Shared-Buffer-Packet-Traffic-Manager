        // Check the actual rank and projection against old membership. The
        // contract permits any ordering of the distinct free IDs.
        function void check_candidate_pre(pool_item transaction, pool_counts_t pre);
            bit [N_DESC-1:0] used_ranks = '0;
            pool_sample_t sample = transaction.sample;
            int rank = 0;
            if (sample.reset_n != transaction.intent.reset_n ||
                sample.initialized != transaction.intent.initialized ||
                transaction.post_ready != sample.reset_n)
                divergence("POOL_READY", sample.edge_number);
            if (sample.batch.cell_write.present != transaction.intent.batch.cell_write.present)
                divergence("WRITE_ACCEPTANCE", sample.edge_number);
            if (transaction.commits != transaction.intended_commits)
                divergence("COMMITTED_LANES", sample.edge_number);
            if (!sample.initialized)
                return;

            for (int index = 0; index < N_RX; ++index) begin
                desc_id_t id = transaction.rank_id[index];
                if (transaction.rank_valid[index] != (index < int'(pre.descriptor_free)))
                    divergence("RANK_VALID", sample.edge_number, $sformatf("rank=%0d", index));
                if (transaction.rank_valid[index]) begin
                    if (model.descriptors[id].phase != FREE_DESC || used_ranks[id])
                        divergence("DESC_RANK_PRE_FREE", sample.edge_number,
                                   $sformatf("rank=%0d id=%0d", index, id));
                    used_ranks[id] = 1;
                end
                if (transaction.commits[index]) begin
                    if (!transaction.rank_valid[rank] ||
                        transaction.projected_desc[index] != transaction.rank_id[rank])
                        divergence("RANK_PROJECTION", sample.edge_number,
                                   $sformatf("lane=%0d rank=%0d id=%0d", index, rank,
                                             transaction.projected_desc[index]));
                    ++rank;
                end
            end
        endfunction

        function void check_candidate_post(pool_item transaction);
            pool_sample_t sample = transaction.sample;
            for (int address = 0; address < N_CELL; ++address)
                if (transaction.physical_cells[address] == model.cells[address].assigned)
                    divergence("CELL_BITMAP", sample.edge_number, $sformatf("id=%0d", address));
            for (int id = 0; id < N_DESC; ++id)
                if (transaction.physical_desc[id] != (model.descriptors[id].phase == FREE_DESC))
                    divergence("DESCRIPTOR_BITMAP", sample.edge_number, $sformatf("id=%0d", id));
            if (sample.batch.cleanup !== transaction.expected_cleanup ||
                sample.batch.cell_return[N_TX].present != transaction.expected_cleanup_cell ||
                (transaction.expected_cleanup_cell &&
                 sample.batch.cell_return[N_TX].address != transaction.expected_cleanup_addr))
                divergence("CLEANUP_ACCEPTANCE", sample.edge_number);
            for (int lane = 0; lane <= N_TX; ++lane) begin
                bit completes = lane < N_TX ? sample.batch.egress_service[lane].cell_last :
                                             transaction.expected_cleanup.done;
                qid_t queue_id = lane < N_TX ? sample.batch.egress_service[lane].owner.qid :
                                               transaction.expected_cleanup.owner.qid;
                cell_count_t credit = lane < N_TX ? cell_count_t'(1) : transaction.expected_cleanup.released;
                if (transaction.release_present[lane] != completes ||
                    (completes && (transaction.release_qid[lane] != queue_id ||
                                   transaction.release_cells[lane] != credit)))
                    divergence("CREDIT_LANE", sample.edge_number,
                               $sformatf("lane=%0d queue=%0d credit=%0d", lane, queue_id, credit));
            end
        endfunction
