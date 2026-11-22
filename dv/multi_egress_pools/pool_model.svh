    typedef enum {FREE_DESC, RECEIVING_FRAME, PUBLISHED_FRAME, BOUND_FRAME,
                  ABORTED_FRAME} ownership_phase;

    typedef struct packed {
        owner_t owner;
        ownership_phase phase;
        int phase_edge;
        int length;
        int credit;
        int materialized;
        int writes;
        int retired;
    } descriptor_state_t;

    typedef struct packed {
        bit assigned;
        owner_t owner;
        int index;
    } cell_state_t;

    // Resource expectations come from accepted edge events and the pool
    // conservation equations. Observed counters never update model state.
    class pool_model;
        descriptor_state_t descriptors[N_DESC];
        cell_state_t cells[N_CELL];
        frame_sequence_t last_sequence[N_RX];
        bit [N_RX-1:0] seen_ingress;
        bit seen_epochs[epoch_t];
        epoch_t epoch;
        bit running;
        int reset_edges;
        bit publication_due;
        owner_t publication_owner;

        function void clear_ownership();
            descriptors = '{default:'0};
            cells = '{default:'0};
            seen_ingress = '0;
            publication_due = 0;
        endfunction

        function string measure(output pool_counts_t counts);
            int unreserved = N_CELL;
            int reserved = 0;
            int materialized = 0;
            counts = '0;
            counts.descriptor_free = N_DESC;
            foreach (descriptors[id]) begin
                descriptor_state_t frame = descriptors[id];
                if (frame.phase == FREE_DESC)
                    continue;
                if (frame.credit < frame.materialized || frame.materialized < 0)
                    return "CONSERVATION";
                --counts.descriptor_free;
                counts.queue_credit[frame.owner.qid] += frame.credit;
                unreserved -= frame.credit;
                reserved += frame.credit - frame.materialized;
                materialized += frame.materialized;
            end
            foreach (cells[address]) begin
                if (cells[address].assigned) begin
                    descriptor_state_t frame = descriptors[cells[address].owner.desc];
                    if (frame.phase == FREE_DESC || frame.owner != cells[address].owner)
                        return "CELL_OWNER";
                    ++counts.assigned;
                end
            end
            counts.physical_free = N_CELL - counts.assigned;
            if (unreserved < 0 || materialized != int'(counts.assigned) ||
                unreserved + reserved != int'(counts.physical_free))
                return "CONSERVATION";
            counts.unreserved = unreserved;
            counts.reserved_free = reserved;
            return "";
        endfunction

        function string check_owner(owner_t owner, ownership_phase stage, string detector,
                                    int before_edge);
            descriptor_state_t frame = descriptors[owner.desc];
            if (owner.frame.epoch != epoch)
                return "STALE_OWNER";
            if (frame.phase != stage || frame.owner != owner || frame.phase_edge >= before_edge)
                return detector;
            return "";
        endfunction

        function string check_returns(edge_batch_t batch);
            bit [N_CELL-1:0] returned_cells = '0;
            bit [N_DESC-1:0] returned_desc = '0;
            for (int lane = 0; lane <= N_TX; ++lane) begin
                cell_return_t returned = batch.cell_return[lane];
                if (!returned.present)
                    continue;
                if (returned.owner.frame.epoch != epoch)
                    return "STALE_OWNER";
                if (returned_cells[returned.address])
                    return "DUPLICATE_CELL_RETURN";
                if (!cells[returned.address].assigned || cells[returned.address].owner != returned.owner)
                    return "CELL_OWNER";
                returned_cells[returned.address] = 1;
            end
            for (int lane = 0; lane <= N_TX; ++lane) begin
                descriptor_return_t returned = batch.descriptor_return[lane];
                desc_id_t id = returned.owner.desc;
                if (!returned.present)
                    continue;
                if (returned.owner.frame.epoch != epoch)
                    return "STALE_OWNER";
                if (returned_desc[id])
                    return "DUPLICATE_DESC_RETURN";
                if (descriptors[id].phase == FREE_DESC || descriptors[id].owner != returned.owner)
                    return "DESC_OWNER";
                returned_desc[id] = 1;
            end
            return "";
        endfunction

        function string reserve(edge_batch_t batch, int prefix_credit, int edge_number);
            bit [N_RX-1:0] granted = '0;
            bit end_of_prefix = 0;
            for (int lane = 0; lane < N_RX; ++lane) begin
                admission_t admission = batch.admission[lane];
                rx_id_t ingress = admission.frame.source;
                desc_id_t id = admission.desc;
                int length = int'(admission.metadata.length);
                int budget = (length + 63) / 64;
                owner_t owner = '{admission.frame, admission.qid, id, admission.metadata.tag_value};

                if (!admission.present) begin
                    end_of_prefix = 1;
                    continue;
                end
                if (end_of_prefix)
                    return "ADMISSION_PREFIX";
                if (admission.result != GRANT)
                    continue;
                if (!admission.qid_valid || int'(admission.metadata.destination) >= N_TX ||
                    int'(admission.metadata.traffic_class) >= N_CLASS ||
                    int'(admission.qid) != int'(admission.metadata.destination) * N_CLASS +
                                           int'(admission.metadata.traffic_class))
                    return "GRANT_ROUTE";
                if (owner.frame.epoch != epoch)
                    return "STALE_OWNER";
                if (granted[ingress])
                    return "GRANT_INGRESS";
                if (batch.cleanup.present && batch.cleanup.done &&
                    ingress == batch.cleanup.owner.frame.source)
                    return "GRANT_CLEANUP_INGRESS";
                if (descriptors[id].phase != FREE_DESC)
                    return "DESC_PRE_FREE";
                if (length < MIN_FRAME_BYTES || length > MAX_FRAME_BYTES ||
                    int'(admission.requested) != budget)
                    return "GRANT_RESERVATION";
                if (budget > prefix_credit)
                    return "CREDIT_PREFIX";
                if (seen_ingress[ingress] && admission.frame.sequence_number <= last_sequence[ingress])
                    return "FRAME_IDENTITY";

                granted[ingress] = 1;
                seen_ingress[ingress] = 1;
                last_sequence[ingress] = admission.frame.sequence_number;
                prefix_credit -= budget;
                descriptors[id] = '{owner, RECEIVING_FRAME, edge_number, length, budget, 0, 0, 0};
            end
            return "";
        endfunction

        function string publish(publication_t publication, int edge_number);
            desc_id_t id = publication.owner.desc;
            cell_state_t head = cells[publication.head];
            string failure;
            if (publication.present != publication_due)
                return "NEXT_EDGE_PUBLICATION";
            if (!publication.present)
                return "";
            failure = check_owner(publication.owner, RECEIVING_FRAME, "PUBLICATION_OWNER", edge_number);
            if (failure != "")
                return failure;
            if (publication.owner != publication_owner ||
                int'(publication.cells) != descriptors[id].credit ||
                int'(publication.length) != descriptors[id].length ||
                !head.assigned || head.owner != publication.owner || head.index != 0)
                return "PUBLICATION_METADATA";
            publication_due = 0;
            descriptors[id].phase = PUBLISHED_FRAME;
            descriptors[id].phase_edge = edge_number;
            return "";
        endfunction

        function string dispatch(dispatch_t grant, int lane, int edge_number);
            desc_id_t id = grant.owner.desc;
            string failure;
            int bound = 0;
            if (!grant.present)
                return "";
            failure = check_owner(grant.owner, PUBLISHED_FRAME, "DISPATCH_PHASE", edge_number);
            if (failure != "")
                return failure;
            foreach (descriptors[index])
                if (descriptors[index].phase == BOUND_FRAME &&
                    int'(descriptors[index].owner.qid) / N_CLASS == lane)
                    ++bound;
            if (int'(grant.owner.qid) / N_CLASS != lane || int'(grant.length) != descriptors[id].length ||
                bound >= TX_FRAME_SLOTS)
                return "DISPATCH_LANE";
            descriptors[id].phase = BOUND_FRAME;
            descriptors[id].phase_edge = edge_number;
            return "";
        endfunction

        function string materialize(cell_write_event_t event_data, int old_free, int edge_number);
            desc_id_t id = event_data.owner.desc;
            descriptor_state_t frame = descriptors[id];
            string failure;
            if (!event_data.present)
                return "";
            if (old_free == 0)
                return "PHYSICAL_EXHAUSTION";
            if (cells[event_data.address].assigned)
                return "CELL_PRE_FREE";
            failure = check_owner(event_data.owner, RECEIVING_FRAME, "WRITE_OWNER", edge_number);
            if (failure != "")
                return failure;
            if (frame.credit <= frame.materialized)
                return "WRITE_CREDIT";
            if (int'(event_data.cell_index) != frame.writes ||
                event_data.final_cell != (frame.writes + 1 == frame.credit))
                return "WRITE_SEQUENCE";

            cells[event_data.address] = '{1'b1, event_data.owner, frame.writes};
            ++descriptors[id].writes;
            ++descriptors[id].materialized;
            if (event_data.final_cell) begin
                publication_due = 1;
                publication_owner = event_data.owner;
            end
            return "";
        endfunction

        function string mark_abort(abort_mark_t mark, int lane, int edge_number);
            desc_id_t id = mark.owner.desc;
            descriptor_state_t frame = descriptors[id];
            string failure;
            if (!mark.present)
                return "";
            failure = check_owner(mark.owner, RECEIVING_FRAME, "ABORT_PHASE", edge_number + 1);
            if (failure != "")
                return failure;
            if (int'(mark.owner.frame.source) != lane || int'(mark.reserved) != frame.credit ||
                frame.writes >= frame.credit)
                return "ABORT_RESERVATION";
            descriptors[id].phase = ABORTED_FRAME;
            descriptors[id].phase_edge = edge_number;
            return "";
        endfunction

        function void reclaim(cell_id_t address, desc_id_t id);
            cells[address] = '0;
            --descriptors[id].materialized;
        endfunction

        function string retire(edge_batch_t batch, int lane, int edge_number);
            egress_service_t beat_event = batch.egress_service[lane];
            cell_return_t cell_event = batch.cell_return[lane];
            descriptor_return_t desc_event = batch.descriptor_return[lane];
            desc_id_t id = beat_event.owner.desc;
            descriptor_state_t frame = descriptors[id];
            cell_state_t slot = cells[beat_event.address];
            string failure;

            if (!beat_event.present)
                return cell_event.present || desc_event.present ? "TX_ACCEPTANCE" : "";
            failure = check_owner(beat_event.owner, BOUND_FRAME, "TX_PHASE", edge_number);
            if (failure != "")
                return failure;
            if (int'(beat_event.owner.qid) / N_CLASS != lane || !slot.assigned || slot.owner != beat_event.owner)
                return "TX_OWNER";
            if (slot.index != frame.retired || (beat_event.frame_last && !beat_event.cell_last))
                return "TX_ORDER";
            if (cell_event.present != beat_event.cell_last ||
                (cell_event.present && (cell_event.owner != beat_event.owner ||
                                        cell_event.address != beat_event.address)))
                return "TX_CELL_EVENT";
            if (desc_event.present != beat_event.frame_last ||
                (desc_event.present && desc_event.owner != beat_event.owner))
                return "TX_DESC_EVENT";
            if (beat_event.cell_last) begin
                if (beat_event.frame_last != (frame.credit == 1))
                    return "TX_FINAL";
                reclaim(beat_event.address, id);
                --descriptors[id].credit;
                ++descriptors[id].retired;
            end
            if (beat_event.frame_last)
                descriptors[id] = '0;
            return "";
        endfunction

        function string cleanup(edge_batch_t batch, int edge_number);
            cleanup_t event_data = batch.cleanup;
            cell_return_t cell_event = batch.cell_return[N_TX];
            descriptor_return_t desc_event = batch.descriptor_return[N_TX];
            desc_id_t id = event_data.owner.desc;
            string failure;
            if (!event_data.present)
                return cell_event.present || desc_event.present ? "CLEANUP_SERVICE" : "";
            failure = check_owner(event_data.owner, ABORTED_FRAME, "CLEANUP_PHASE", edge_number);
            if (failure != "")
                return failure;
            if (cell_event.present) begin
                if (cell_event.owner != event_data.owner)
                    return "CLEANUP_OWNER";
                reclaim(cell_event.address, id);
            end else if (!event_data.done) begin
                return "EMPTY_CLEANUP_SERVICE";
            end
            if (event_data.done) begin
                if (descriptors[id].materialized != 0 || int'(event_data.released) != descriptors[id].credit)
                    return "CLEANUP_CREDIT";
                if (!desc_event.present || desc_event.owner != event_data.owner)
                    return "CLEANUP_DESC_EVENT";
                descriptors[id] = '0;
            end else if (event_data.released != 0 || desc_event.present) begin
                return "EARLY_CLEANUP_CREDIT";
            end
            return "";
        endfunction

        function string apply_batch(edge_batch_t batch, pool_counts_t before_counts, int edge_number);
            // Validate returns against old owners, then allocate from the old
            // free pools. The only same-edge owner transition allowed here is
            // reserve/write-prefix followed by abort marking.
            string failure = check_returns(batch);
            if (failure != "")
                return failure;
            failure = reserve(batch, int'(before_counts.unreserved), edge_number);
            if (failure != "")
                return failure;
            failure = publish(batch.publication, edge_number);
            if (failure != "")
                return failure;
            for (int lane = 0; lane < N_TX; ++lane) begin
                failure = dispatch(batch.dispatch[lane], lane, edge_number);
                if (failure != "")
                    return failure;
            end
            failure = materialize(batch.cell_write, int'(before_counts.physical_free), edge_number);
            if (failure != "")
                return failure;
            for (int lane = 0; lane < N_RX; ++lane) begin
                failure = mark_abort(batch.abort_mark[lane], lane, edge_number);
                if (failure != "")
                    return failure;
            end
            for (int lane = 0; lane < N_TX; ++lane) begin
                failure = retire(batch, lane, edge_number);
                if (failure != "")
                    return failure;
            end
            return cleanup(batch, edge_number);
        endfunction

        function string advance(pool_sample_t sample, pool_counts_t before_counts,
                                int edge_number, output pool_counts_t after_counts);
            edge_batch_t batch = sample.batch;
            string failure;
            after_counts = '0;
            if (!sample.reset_n) begin
                if (sample.initialized || batch.present || has_events(batch))
                    return "RESET_ACTIVITY";
                ++reset_edges;
                clear_ownership();
                running = 0;
            end else begin
                if (!batch.present)
                    return "EDGE_PRESENT";
                if (!running) begin
                    if (reset_edges < 2 || seen_epochs.exists(batch.epoch) != 0)
                        return "RESET_EPOCH";
                    if (sample.initialized)
                        return "INITIALIZE";
                    if (has_events(batch))
                        return "INITIALIZE_ACTIVITY";
                    seen_epochs[batch.epoch] = 1;
                    epoch = batch.epoch;
                    reset_edges = 0;
                    running = 1;
                end else begin
                    if (batch.epoch != epoch)
                        return "EDGE_EPOCH";
                    if (!sample.initialized)
                        return "INITIALIZE";
                    failure = apply_batch(batch, before_counts, edge_number);
                    if (failure != "")
                        return failure;
                end
            end
            failure = measure(after_counts);
            if (failure != "")
                return failure;
            `ifdef POOL_CANDIDATE
            if (sample.counts !== after_counts)
`else
            if (sample.counts !== (sample.reset_n ? after_counts : pool_counts_t'('0)))
`endif
                return "REPORTED_COUNTS";
            return "";
        endfunction

        function string drained();
            pool_counts_t counts, empty = '0;
            string failure = measure(counts);
            if (failure != "")
                return failure;
            if (counts.descriptor_free != N_DESC || counts.assigned != 0 || publication_due)
                return "DRAIN_OWNERSHIP";
            empty.physical_free = N_CELL;
            empty.unreserved = N_CELL;
            empty.descriptor_free = N_DESC;
            if (!running || counts != empty)
                return "DRAIN_COUNTS";
            return "";
        endfunction
    endclass
