    // Fixture IDs are symbolic. Retirements use only addresses returned by
    // earlier DUT edges. The caller supplies the frame metadata and phases.
    class pool_candidate_caller;
        virtual pool_candidate_bus pins;
        desc_id_t descriptors[desc_id_t];
        cell_id_t cells[cell_id_t];
        owner_t descriptor_owners[desc_id_t];
        owner_t cell_owners[cell_id_t];
        int remaining_cells[desc_id_t];
        admission_t lane_intent[N_RX];
        bit [N_RX-1:0] intended_commits;
        bit sparse;
        int guard;
        owner_t probed_owner;
        cell_id_t probed_cell;

        function bit suppress_probe(egress_service_t service, int origin, epoch_t epoch);
            if (origin < 2)
                return 0;
            probed_owner = service.owner;
            if (descriptors.exists(service.owner.desc) == 0 || cells.exists(service.address) == 0)
                `uvm_fatal("CALLER_PROBE", "Probe requires a currently owned physical address")
            probed_owner.desc = descriptors[service.owner.desc];
            probed_cell = cells[service.address];
            if (service.owner.frame.epoch != epoch) begin
                guard = 2;
                return 1;
            end
            if (service.frame_last && remaining_cells[probed_owner.desc] > 1) begin
                guard = 3;
                return 1;
            end
            return 0;
        endfunction

        function new(virtual pool_candidate_bus pins);
            this.pins = pins;
        endfunction

        function owner_t resolve_owner(owner_t symbolic);
            owner_t actual = symbolic;
            if (descriptors.exists(symbolic.desc) == 0)
                `uvm_fatal("CALLER_DESCRIPTOR", $sformatf("Unmapped symbolic owner %h", symbolic))
            actual.desc = descriptors[symbolic.desc];
            if (descriptor_owners[actual.desc] != actual)
                `uvm_fatal("CALLER_DESCRIPTOR", $sformatf("Stale or mismatched owner %h", symbolic))
            return actual;
        endfunction

        function cell_id_t resolve_cell(cell_id_t symbolic, owner_t actual);
            if (cells.exists(symbolic) == 0 || cell_owners[cells[symbolic]] != actual)
                `uvm_fatal("CALLER_CELL", $sformatf("Unmapped or mismatched cell %0d for %h", symbolic, actual))
            return cells[symbolic];
        endfunction

        task drive(pool_sample_t intent);
            edge_batch_t batch = intent.batch;
            int commits = 0;
            pins.rst_n = intent.reset_n;
            pins.reserve_commit = '0;
            pins.reserve_cells = '0;
            pins.reserve_qid = '0;
            pins.write_offer = batch.cell_write.present;
            pins.tx_present = '0;
            pins.tx_final = '0;
            pins.tx_desc = '1;
            pins.tx_cell = '1;
            pins.tx_qid = '1;
            pins.cleanup_present = batch.cleanup.present;
            pins.cleanup_has_cell = batch.cell_return[N_TX].present;
            pins.cleanup_done = batch.cleanup.done && batch.cleanup.present;
            pins.cleanup_cell = '1;
            pins.cleanup_desc = '1;
            pins.cleanup_qid = '1;
            pins.cleanup_released = batch.cleanup.present ? batch.cleanup.released : '0;
            intended_commits = '0;
            guard = 0;
            probed_owner = '0;
            probed_cell = '0;
            if (!intent.reset_n) begin
                descriptors.delete();
                cells.delete();
                descriptor_owners.delete();
                cell_owners.delete();
                remaining_cells.delete();
                return;
            end

            foreach (batch.admission[index])
                commits += int'(batch.admission[index].present && batch.admission[index].result == GRANT);
            for (int index = 0; index < commits; ++index) begin
                int lane = sparse && commits < N_RX && index == commits - 1 ? N_RX - 1 : index;
                lane_intent[lane] = batch.admission[index];
                intended_commits[lane] = 1;
                pins.reserve_cells[lane] = lane_intent[lane].requested;
                pins.reserve_qid[lane] = lane_intent[lane].qid;
            end
            pins.reserve_commit = intended_commits;

            for (int lane = 0; lane < N_TX; ++lane) begin
                egress_service_t service = batch.egress_service[lane];
                owner_t owner;
                if (!service.present || suppress_probe(service, int'(intent.origin), batch.epoch))
                    continue;
                owner = resolve_owner(service.owner);
                pins.tx_present[lane] = service.cell_last;
                pins.tx_final[lane] = service.frame_last;
                pins.tx_desc[lane] = owner.desc;
                pins.tx_cell[lane] = resolve_cell(service.address, owner);
                pins.tx_qid[lane] = owner.qid;
            end
            if (batch.cleanup.present) begin
                owner_t owner = resolve_owner(batch.cleanup.owner);
                pins.cleanup_desc = owner.desc;
                pins.cleanup_qid = owner.qid;
                if (pins.cleanup_has_cell)
                    pins.cleanup_cell = resolve_cell(batch.cell_return[N_TX].address, owner);
            end
        endtask

        function void observe_grants(pool_item item);
            int rank = 0;
            item.sample.batch.admission = '0;
            for (int lane = 0; lane < N_RX; ++lane) begin
                admission_t grant;
                owner_t owner;
                if (!pins.reserve_commit[lane])
                    continue;
                grant = lane_intent[lane];
                grant.present = 1;
                grant.desc = pins.grant_desc[lane];
                grant.requested = pins.reserve_cells[lane];
                grant.qid = pins.reserve_qid[lane];
                item.sample.batch.admission[rank++] = grant;
                owner = '{grant.frame, grant.qid, grant.desc, grant.metadata.tag_value};
                descriptors[lane_intent[lane].desc] = grant.desc;
                descriptor_owners[grant.desc] = owner;
                remaining_cells[grant.desc] = 0;
            end
        endfunction

        function void observe_returns(pool_item item);
            edge_batch_t batch = item.intent.batch;
            // Use the tapped physical lanes. Payload on an inactive lane is irrelevant.
            item.sample.batch.cell_return = '0;
            item.sample.batch.descriptor_return = '0;
            for (int lane = 0; lane <= N_TX; ++lane) begin
                if (pins.cell_present[lane]) begin
                    cell_id_t address = pins.return_cell[lane];
                    item.sample.batch.cell_return[lane] = '{1'b1, cell_owners[address], address};
                end
                if (pins.desc_present[lane]) begin
                    desc_id_t id = pins.return_desc[lane];
                    item.sample.batch.descriptor_return[lane] = '{1'b1, descriptor_owners[id]};
                    item.sample.batch.descriptor_return[lane].owner.desc = id;
                end
            end
            item.sample.batch.cleanup = '0;
            if (batch.cleanup.present) begin
                item.expected_cleanup = batch.cleanup;
                item.expected_cleanup.owner = resolve_owner(batch.cleanup.owner);
                if (batch.cell_return[N_TX].present) begin
                    item.expected_cleanup_cell = 1;
                    item.expected_cleanup_addr = resolve_cell(batch.cell_return[N_TX].address,
                                                             item.expected_cleanup.owner);
                end
            end
            if (pins.cleanup_present) begin
                owner_t owner = item.expected_cleanup.owner;
                owner.desc = pins.cleanup_desc;
                owner.qid = pins.cleanup_qid;
                item.sample.batch.cleanup = '{1'b1, owner, pins.desc_present[N_TX],
                    pins.release_present[N_TX] ? pins.release_cells[N_TX] : cell_count_t'(0)};
            end

            for (int lane = 0; lane <= N_TX; ++lane) begin
                if (batch.cell_return[lane].present) begin
                    cells.delete(batch.cell_return[lane].address);
                    cell_owners.delete(item.sample.batch.cell_return[lane].address);
                    if (item.sample.batch.cell_return[lane].present)
                        --remaining_cells[item.sample.batch.cell_return[lane].owner.desc];
                end
                if (batch.descriptor_return[lane].present) begin
                    descriptors.delete(batch.descriptor_return[lane].owner.desc);
                    descriptor_owners.delete(item.sample.batch.descriptor_return[lane].owner.desc);
                    remaining_cells.delete(item.sample.batch.descriptor_return[lane].owner.desc);
                end
            end
        endfunction

        function void observe_pre(pool_item item);
            edge_batch_t batch = item.intent.batch;
            item.sample = '0;
            item.sample.edge_number = item.intent.edge_number;
            item.sample.origin = item.intent.origin;
            item.sample.reset_n = pins.rst_n;
            item.sample.initialized = pins.ready;
            item.sample.batch.epoch = batch.epoch;
            item.sample.batch.present = pins.rst_n;
            item.sample.batch.publication = batch.publication;
            item.sample.batch.dispatch = batch.dispatch;
            item.sample.batch.abort_mark = batch.abort_mark;
            item.sample.batch.egress_service = guard != 0 ? '0 : batch.egress_service;
            item.caller_guard = guard;
            item.probed_cell = probed_cell;
            item.probed_owner = probed_owner;
            item.inactive_payload = pins.tx_present == '0 && pins.tx_cell == '1 &&
                                    pins.tx_desc == '1 && pins.tx_qid == '1;
            item.rank_valid = pins.rank_valid;
            item.rank_id = pins.rank_id;
            item.projected_desc = pins.grant_desc;
            item.commits = pins.reserve_commit;
            item.intended_commits = intended_commits;
            item.release_present = pins.release_present;
            item.release_qid = pins.release_qid;
            item.release_cells = pins.release_cells;

            // Resolve prior owners before installing new grants/allocations.
            if (batch.publication.present) begin
                owner_t owner = resolve_owner(batch.publication.owner);
                item.sample.batch.publication.owner = owner;
                item.sample.batch.publication.head = resolve_cell(batch.publication.head, owner);
            end
            for (int lane = 0; lane < N_TX; ++lane) begin
                if (batch.dispatch[lane].present)
                    item.sample.batch.dispatch[lane].owner = resolve_owner(batch.dispatch[lane].owner);
                if (item.sample.batch.egress_service[lane].present) begin
                    owner_t owner = resolve_owner(batch.egress_service[lane].owner);
                    item.sample.batch.egress_service[lane].owner = owner;
                    item.sample.batch.egress_service[lane].address = resolve_cell(batch.egress_service[lane].address, owner);
                end
            end
            if (pins.write_accept) begin
                item.sample.batch.cell_write = batch.cell_write;
                item.sample.batch.cell_write.present = 1;
                if (batch.cell_write.present)
                    item.sample.batch.cell_write.owner = resolve_owner(batch.cell_write.owner);
                item.sample.batch.cell_write.address = pins.write_id;
            end
            observe_returns(item);
            observe_grants(item);
            if (pins.write_accept && batch.cell_write.present) begin
                cells[batch.cell_write.address] = pins.write_id;
                cell_owners[pins.write_id] = item.sample.batch.cell_write.owner;
                ++remaining_cells[item.sample.batch.cell_write.owner.desc];
            end
            for (int lane = 0; lane < N_RX; ++lane)
                if (batch.abort_mark[lane].present)
                    item.sample.batch.abort_mark[lane].owner = resolve_owner(batch.abort_mark[lane].owner);
        endfunction

        function void observe_post(pool_item item);
            item.post_ready = pins.ready;
            item.physical_cells = pins.cell_free;
            item.physical_desc = pins.desc_free;
            item.sample.counts.physical_free = int'(pins.free_cells);
            item.sample.counts.unreserved = int'(pins.unreserved);
            item.sample.counts.reserved_free = int'(pins.reserved_free);
            item.sample.counts.assigned = N_CELL - $countones(pins.cell_free);
            item.sample.counts.descriptor_free = int'(pins.free_desc);
            for (int q = 0; q < N_Q; ++q)
                item.sample.counts.queue_credit[q] = int'(pins.held[q]);
        endfunction
    endclass
