    class traffic_choice extends uvm_object;
        rand bit [N_RX-1:0] offer;
        rand bit [N_TX-1:0] ready;
        rand bit write_ready, cleanup_ready;
        rand int unsigned selection, abort_chance, reset_chance;

        constraint service_choices {
            abort_chance inside {[0:15]};
            reset_chance inside {[0:255]};
            selection < N_DESC;
        }
        `uvm_object_utils(traffic_choice)
        function new(string name = "traffic_choice");
            super.new(name);
        endfunction
    endclass

    typedef enum {VACANT, RECEIVING, PUBLISHING, QUEUED, BOUND, ABORTING} intent_phase;
    localparam int MAX_CELLS = MAX_FRAME_BYTES / 64;

    // Each entry is driver-owned intent. The independent oracle reconstructs
    // ownership from monitor output and cannot access these arrays.
    typedef struct packed {
        intent_phase phase;
        owner_t owner;
        int length;
        int budget;
        int written;
        int retired;
        int phase_edge;
        logic [MAX_CELLS-1:0][CELL_ID_W-1:0] addresses;
    } frame_intent_t;

    class pool_traffic_ledger extends uvm_object;
        frame_intent_t frames[N_DESC];
        bit allocated_cells[N_CELL];
        frame_sequence_t sequence_number[N_RX];
        int occupied[N_RX];
        int reserved[N_Q];
        int free_count, free_desc, credit, edge_number;
        int publication_id;
        epoch_t epoch;

        `uvm_object_utils(pool_traffic_ledger)
        function new(string name = "pool_traffic_ledger");
            super.new(name);
        endfunction

        function void restart(epoch_t next_epoch);
            frames = '{default:'0};
            allocated_cells = '{default:0};
            sequence_number = '{default:0};
            reserved = '{default:0};
            occupied = '{default:-1};
            free_count = N_CELL;
            free_desc = N_DESC;
            credit = N_CELL;
            publication_id = -1;
            edge_number = 0;
            epoch = next_epoch;
        endfunction

        function pool_counts_t counts();
            pool_counts_t result = '0;
            result.physical_free = free_count;
            result.unreserved = credit;
            result.reserved_free = free_count - credit;
            result.assigned = N_CELL - free_count;
            result.descriptor_free = free_desc;
            for (int q = 0; q < N_Q; ++q)
                result.queue_credit[q] = reserved[q];
            return result;
        endfunction

        function int select_phase(intent_phase phase, int start);
            int index;
            for (int i = 0; i < N_DESC; ++i) begin
                index = (i + start) % N_DESC;
                if (frames[index].phase == phase)
                    return index;
            end
            return -1;
        endfunction

        function int select_tx(intent_phase phase, int lane);
            int selected = -1;
            for (int i = 0; i < N_DESC; ++i) begin
                if (frames[i].phase == phase && int'(frames[i].owner.qid) / N_CLASS == lane &&
                    (selected < 0 || frames[i].phase_edge < frames[selected].phase_edge))
                    selected = i;
            end
            return selected;
        endfunction

        function void make_grants(ref edge_batch_t batch, input traffic_choice choice, int cleanup_id);
            int ingress, descriptor_id, grant_lane = 0;
            int budget, length, qid;
            for (int offset = 0; offset < N_RX; ++offset) begin
                ingress = (choice.selection + offset) % N_RX;
                if (!choice.offer[ingress] || occupied[ingress] >= 0 || credit == 0 || free_desc == 0)
                    continue;
                if (cleanup_id >= 0 && int'(frames[cleanup_id].owner.frame.source) == ingress)
                    continue;
                descriptor_id = select_phase(VACANT, int'($urandom_range(N_DESC - 1)));
                budget = credit < MAX_CELLS ? credit : MAX_CELLS;
                budget = int'($urandom_range(budget, 1));
                length = int'($urandom_range(budget * 64, budget == 1 ? MIN_FRAME_BYTES : 64 * (budget - 1) + 1));
                qid = int'($urandom_range(N_Q - 1));
                frames[descriptor_id].phase = RECEIVING;
                frames[descriptor_id].owner.frame = '{epoch, rx_id_t'(ingress), sequence_number[ingress]};
                frames[descriptor_id].owner.qid = qid_t'(qid);
                frames[descriptor_id].owner.desc = desc_id_t'(descriptor_id);
                frames[descriptor_id].owner.tag_value = opaque_tag_t'($urandom_range(3));
                frames[descriptor_id].length = length;
                frames[descriptor_id].budget = budget;
                frames[descriptor_id].phase_edge = edge_number;
                frames[descriptor_id].written = 0;
                frames[descriptor_id].retired = 0;
                occupied[ingress] = descriptor_id;
                ++sequence_number[ingress];
                --free_desc;
                credit -= budget;
                reserved[qid] += budget;
                batch.admission[grant_lane].present = 1;
                batch.admission[grant_lane].frame = frames[descriptor_id].owner.frame;
                batch.admission[grant_lane].metadata.length = 16'(length);
                batch.admission[grant_lane].metadata.destination = 8'(qid / N_CLASS);
                batch.admission[grant_lane].metadata.traffic_class = 8'(qid % N_CLASS);
                batch.admission[grant_lane].metadata.tag_value = frames[descriptor_id].owner.tag_value;
                batch.admission[grant_lane].result = GRANT;
                batch.admission[grant_lane].qid_valid = 1;
                batch.admission[grant_lane].qid = qid_t'(qid);
                batch.admission[grant_lane].requested = cell_count_t'(budget);
                batch.admission[grant_lane].desc = desc_id_t'(descriptor_id);
                ++grant_lane;
            end
        endfunction

        function void publish(ref edge_batch_t batch);
            int id = publication_id;
            if (id < 0)
                return;
            batch.publication = '{1, frames[id].owner, frames[id].addresses[0],
                                  cell_count_t'(frames[id].budget), 16'(frames[id].length), 2'b0, 1'b0};
            frames[id].phase = QUEUED;
            frames[id].phase_edge = edge_number;
            publication_id = -1;
        endfunction

        function void materialize(ref edge_batch_t batch, input int id);
            int start, address = -1;
            if (id < 0)
                return;
            start = int'($urandom_range(N_CELL - 1));
            for (int i = 0; i < N_CELL; ++i) begin
                if (!allocated_cells[(i + start) % N_CELL]) begin
                    address = (i + start) % N_CELL;
                    break;
                end
            end
            if (address < 0)
                `uvm_fatal("STIMULUS_LEDGER", "Writer had no reserved physical address")
            batch.cell_write = '{1, frames[id].owner, cell_count_t'(frames[id].written),
                                 cell_id_t'(address), frames[id].written + 1 == frames[id].budget};
            frames[id].addresses[frames[id].written] = cell_id_t'(address);
            ++frames[id].written;
            allocated_cells[address] = 1;
            --free_count;
            if (batch.cell_write.final_cell) begin
                frames[id].phase = PUBLISHING;
                publication_id = id;
                occupied[frames[id].owner.frame.source] = -1;
            end
        endfunction

        function void reclaim(ref edge_batch_t batch, input int id, int lane);
            cell_id_t address = frames[id].addresses[frames[id].retired];
            batch.cell_return[lane] = '{1, frames[id].owner, address};
            allocated_cells[address] = 0;
            ++frames[id].retired;
            ++free_count;
        endfunction

        function void release_credit(int id, int length);
            credit += length;
            reserved[frames[id].owner.qid] -= length;
        endfunction

        function void release_descriptor(ref edge_batch_t batch, input int id, int lane);
            batch.descriptor_return[lane] = '{1, frames[id].owner};
            frames[id].phase = VACANT;
            ++free_desc;
        endfunction

        function void cleanup(ref edge_batch_t batch, input int id);
            bit final_reclaim;
            if (id < 0)
                return;
            if (frames[id].retired < frames[id].written)
                reclaim(batch, id, N_TX);
            final_reclaim = frames[id].retired == frames[id].written;
            batch.cleanup = '{1, frames[id].owner, final_reclaim,
                              final_reclaim ? cell_count_t'(frames[id].budget) : '0};
            if (final_reclaim) begin
                release_credit(id, frames[id].budget);
                occupied[frames[id].owner.frame.source] = -1;
                release_descriptor(batch, id, N_TX);
            end
        endfunction

        function void transmit(ref edge_batch_t batch, input int id, int lane);
            bit last;
            if (id < 0)
                return;
            last = frames[id].retired + 1 == frames[id].written;
            batch.egress_service[lane] = '{1, frames[id].owner,
                                            frames[id].addresses[frames[id].retired], 1, last};
            reclaim(batch, id, lane);
            release_credit(id, 1);
            if (last)
                release_descriptor(batch, id, lane);
        endfunction

        function pool_sample_t step(traffic_choice choice, bit draining);
            pool_sample_t sample = '0;
            edge_batch_t batch = '0;
            int writer = -1, aborting = -1, cleanup_id = -1;
            int bound[N_TX], dispatch_ids[N_TX];
            ++edge_number;

            if (choice.write_ready || draining)
                writer = select_phase(RECEIVING, choice.selection);
            if (choice.abort_chance == 0 && !draining)
                aborting = select_phase(RECEIVING, (choice.selection + 1) % N_DESC);
            if (choice.cleanup_ready || draining)
                cleanup_id = select_phase(ABORTING, choice.selection);
            for (int lane = 0; lane < N_TX; ++lane) begin
                bound[lane] = select_tx(BOUND, lane);
                dispatch_ids[lane] = bound[lane] < 0 ? select_tx(QUEUED, lane) : -1;
            end

            batch.present = 1;
            batch.epoch = epoch;
            if (!draining)
                make_grants(batch, choice, cleanup_id);
            publish(batch);
            materialize(batch, writer);
            if (aborting >= 0 && frames[aborting].phase == RECEIVING) begin
                batch.abort_mark[frames[aborting].owner.frame.source] =
                    '{1, frames[aborting].owner, cell_count_t'(frames[aborting].budget)};
                frames[aborting].phase = ABORTING;
                frames[aborting].phase_edge = edge_number;
            end

            for (int lane = 0; lane < N_TX; ++lane) begin
                if (dispatch_ids[lane] >= 0) begin
                    int id = dispatch_ids[lane];
                    frames[id].phase = BOUND;
                    frames[id].phase_edge = edge_number;
                    batch.dispatch[lane] = '{1, frames[id].owner, 16'(frames[id].length)};
                end
                if (choice.ready[lane] || draining)
                    transmit(batch, bound[lane], lane);
            end
            cleanup(batch, cleanup_id);
            sample.origin = 1;
            sample.reset_n = 1;
            sample.initialized = 1;
            sample.batch = batch;
            sample.counts = counts();
            return sample;
        endfunction
    endclass
