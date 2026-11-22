package multi_egress_pool_bench;
    import tm_multi_fixed::*;
    import multi_egress_pool_types::*;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class pool_item extends uvm_sequence_item;
        pool_sample_t sample;
        `uvm_object_utils(pool_item)
        function new(string name = "pool_item");
            super.new(name);
        endfunction
    endclass

    class pool_driver extends uvm_driver #(pool_item);
        `uvm_component_utils(pool_driver)
        virtual multi_egress_pool_bus bus;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            bus.sample_valid = 0;
            forever begin
                seq_item_port.get_next_item(req);
                @(negedge bus.clk);
                bus.sample = req.sample;
                bus.sample_valid = 1;
                @(posedge bus.clk);
                #1;
                bus.sample_valid = 0;
                seq_item_port.item_done();
            end
        endtask
    endclass

    class pool_monitor extends uvm_monitor;
        `uvm_component_utils(pool_monitor)
        virtual multi_egress_pool_bus bus;
        uvm_analysis_port #(pool_item) accepted;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            accepted = new("accepted", this);
        endfunction

        task run_phase(uvm_phase phase);
            pool_item observed;
            forever begin
                @(posedge bus.clk);
                if (bus.sample_valid) begin
                    observed = pool_item::type_id::create("observed");
                    observed.sample = bus.sample;
                    accepted.write(observed);
                end
            end
        endtask
    endclass

    class pool_trace extends uvm_subscriber #(pool_item);
        `uvm_component_utils(pool_trace)
        int file_handle;
        int edges;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void write(pool_item transaction);
            pool_sample_t sample = transaction.sample;
            $fwrite(file_handle, "%0d %0d %0d %0d %0h %0d %0d %0d %0d %0d",
                    edges, sample.reset_n, sample.initialized, sample.origin, sample.batch,
                    sample.counts.physical_free, sample.counts.unreserved,
                    sample.counts.reserved_free, sample.counts.assigned, sample.counts.descriptor_free);
            for (int q = 0; q < N_Q; ++q)
                $fwrite(file_handle, " %0d", sample.counts.queue_credit[q]);
            $fwrite(file_handle, "\n");
            ++edges;
        endfunction
    endclass

    class episode_choice extends uvm_object;
        rand int unsigned index;
        rand int unsigned cell_shift, descriptor_shift;
        rand int unsigned ingress_shift, egress_shift, class_shift;
        rand int unsigned extra_wait;
        int unsigned episode_count;

        constraint profile {
            index < episode_count;
            cell_shift < N_CELL;
            descriptor_shift < N_DESC;
            ingress_shift < N_RX;
            egress_shift < N_TX;
            class_shift < N_CLASS;
            extra_wait inside {[0:2]};
        }
        `uvm_object_utils(episode_choice)
        function new(string name = "episode_choice");
            super.new(name);
        endfunction
    endclass

    `include "pool_random.svh"

    // The sequence composes legal state trajectories. The length table is a
    // stimulus ledger for compatible metadata, independent of monitor results.
    class pool_replay_sequence extends uvm_sequence #(pool_item);
        `uvm_object_utils(pool_replay_sequence)
        string input_path, template_dir;
        int activity_edges;
        int read_edges;
        int sent_edges;
        epoch_t epoch, epoch_delta;
        bit reset_active;
        logic [15:0] intent_length[N_DESC];
        bit intent_live[N_DESC];
        int intent_count;

        function new(string name = "pool_replay_sequence");
            super.new(name);
        endfunction

        function bit read_sample(int file_handle, output pool_sample_t sample);
            int reset_value, initialization, origin;
            int status;
            int unsigned credits, physical_free, unreserved, reserved_free, assigned, descriptor_free;
            edge_batch_t batch;
            sample = '0;
            status = $fscanf(file_handle, "%d %d %d %h %d %d %d %d %d",
                             reset_value, initialization, origin, batch,
                             physical_free, unreserved, reserved_free, assigned, descriptor_free);
            if (status == -1)
                return 0;
            if (status != 9)
                `uvm_fatal("TRACE_INPUT", $sformatf("Invalid pool row, scanned %0d fields", status))
            sample.reset_n = reset_value != 0;
            sample.initialized = initialization != 0;
            sample.origin = origin;
            sample.batch = batch;
            sample.counts.physical_free = physical_free;
            sample.counts.unreserved = unreserved;
            sample.counts.reserved_free = reserved_free;
            sample.counts.assigned = assigned;
            sample.counts.descriptor_free = descriptor_free;
            for (int q = 0; q < N_Q; ++q) begin
                if ($fscanf(file_handle, "%d", credits) != 1)
                    `uvm_fatal("TRACE_INPUT", "Missing queue count")
                sample.counts.queue_credit[q] = credits;
            end
            return 1;
        endfunction

        function qid_t queue_id(qid_t qid, episode_choice choice);
            int old_q = int'(qid);
            return qid_t'((((old_q / N_CLASS) + choice.egress_shift) % N_TX) * N_CLASS +
                          ((old_q % N_CLASS) + choice.class_shift) % N_CLASS);
        endfunction

        function frame_id_t identity(frame_id_t frame, episode_choice choice);
            frame.epoch += epoch_delta;
            frame.source = rx_id_t'((int'(frame.source) + choice.ingress_shift) % N_RX);
            return frame;
        endfunction

        function cell_id_t address(cell_id_t old_id, episode_choice choice);
            return cell_id_t'((int'(old_id) + choice.cell_shift) % N_CELL);
        endfunction

        function desc_id_t descriptor(desc_id_t old_id, episode_choice choice);
            return desc_id_t'((int'(old_id) + choice.descriptor_shift) % N_DESC);
        endfunction

        function owner_t owner_id(owner_t owner, episode_choice choice);
            owner.frame = identity(owner.frame, choice);
            owner.qid = queue_id(owner.qid, choice);
            owner.desc = descriptor(owner.desc, choice);
            return owner;
        endfunction

        function void translate_admissions(ref edge_batch_t batch, input episode_choice choice, bit randomized);
            int unsigned index, minimum, maximum;
            for (int lane = 0; lane < N_RX; ++lane) begin
                if (!batch.admission[lane].present)
                    continue;
                batch.admission[lane].frame = identity(batch.admission[lane].frame, choice);
                batch.admission[lane].qid = queue_id(batch.admission[lane].qid, choice);
                batch.admission[lane].desc = descriptor(batch.admission[lane].desc, choice);
                batch.admission[lane].metadata.destination = 8'(int'(batch.admission[lane].qid) / N_CLASS);
                batch.admission[lane].metadata.traffic_class = 8'(int'(batch.admission[lane].qid) % N_CLASS);
                if (randomized) begin
                    index = int'(batch.admission[lane].desc);
                    if (intent_live[index])
                        `uvm_fatal("STIMULUS_LEDGER", "Random intent selected an owned descriptor")
                    maximum = 64 * int'(batch.admission[lane].requested);
                    minimum = maximum == 64 ? MIN_FRAME_BYTES : maximum - 63;
                    intent_length[index] = 16'($urandom_range(maximum, minimum));
                    intent_live[index] = 1;
                    ++intent_count;
                    batch.admission[lane].metadata.length = intent_length[index];
                end
            end
        endfunction

        function void translate_receive(ref edge_batch_t batch, input episode_choice choice, bit randomized);
            abort_marks_t old_aborts = batch.abort_mark;
            int destination;
            batch.abort_mark = '0;
            if (batch.cell_write.present) begin
                batch.cell_write.owner = owner_id(batch.cell_write.owner, choice);
                batch.cell_write.address = address(batch.cell_write.address, choice);
            end
            if (batch.publication.present) begin
                batch.publication.owner = owner_id(batch.publication.owner, choice);
                batch.publication.head = address(batch.publication.head, choice);
                if (randomized)
                    batch.publication.length = intent_length[batch.publication.owner.desc];
            end
            for (int lane = 0; lane < N_RX; ++lane) begin
                if (old_aborts[lane].present) begin
                    destination = (lane + int'(choice.ingress_shift)) % N_RX;
                    batch.abort_mark[destination] = old_aborts[lane];
                    batch.abort_mark[destination].owner = owner_id(old_aborts[lane].owner, choice);
                end
            end
            if (batch.cleanup.present)
                batch.cleanup.owner = owner_id(batch.cleanup.owner, choice);
        endfunction

        function void translate_tx(ref edge_batch_t batch, input episode_choice choice, bit randomized);
            dispatches_t dispatches = batch.dispatch;
            egress_services_t services = batch.egress_service;
            int lane;
            batch.dispatch = '0;
            batch.egress_service = '0;
            for (int old_lane = 0; old_lane < N_TX; ++old_lane) begin
                lane = (old_lane + int'(choice.egress_shift)) % N_TX;
                if (dispatches[old_lane].present) begin
                    batch.dispatch[lane] = dispatches[old_lane];
                    batch.dispatch[lane].owner = owner_id(dispatches[old_lane].owner, choice);
                    if (randomized)
                        batch.dispatch[lane].length = intent_length[batch.dispatch[lane].owner.desc];
                end
                if (services[old_lane].present) begin
                    batch.egress_service[lane] = services[old_lane];
                    batch.egress_service[lane].owner = owner_id(services[old_lane].owner, choice);
                    batch.egress_service[lane].address = address(services[old_lane].address, choice);
                end
            end
        endfunction

        function void translate_returns(ref edge_batch_t batch, input episode_choice choice, bit randomized);
            cell_returns_t cells = batch.cell_return;
            descriptor_returns_t descriptors = batch.descriptor_return;
            int lane, index;
            batch.cell_return = '0;
            batch.descriptor_return = '0;
            for (int old_lane = 0; old_lane <= N_TX; ++old_lane) begin
                lane = old_lane == N_TX ? N_TX : (old_lane + int'(choice.egress_shift)) % N_TX;
                if (cells[old_lane].present) begin
                    batch.cell_return[lane].present = 1;
                    batch.cell_return[lane].owner = owner_id(cells[old_lane].owner, choice);
                    batch.cell_return[lane].address = address(cells[old_lane].address, choice);
                end else begin
                    batch.cell_return[lane].owner.tag_value = 16'($urandom);
                    batch.cell_return[lane].address = cell_id_t'($urandom);
                end
                if (descriptors[old_lane].present) begin
                    batch.descriptor_return[lane].present = 1;
                    batch.descriptor_return[lane].owner = owner_id(descriptors[old_lane].owner, choice);
                    if (randomized) begin
                        index = int'(batch.descriptor_return[lane].owner.desc);
                        if (!intent_live[index])
                            `uvm_fatal("STIMULUS_LEDGER", "Random intent returned an unowned descriptor")
                        intent_live[index] = 0;
                        --intent_count;
                    end
                end else begin
                    batch.descriptor_return[lane].owner.tag_value = 16'($urandom);
                    batch.descriptor_return[lane].owner.desc = desc_id_t'($urandom);
                end
            end
        endfunction

        function void translate(ref pool_sample_t sample, input episode_choice choice, bit randomized);
            pool_counts_t counts = sample.counts;
            edge_batch_t batch = sample.batch;
            if (!sample.reset_n && !reset_active) begin
                ++epoch;
                epoch_delta = epoch - sample.batch.epoch;
                intent_live = '{default:0};
                intent_count = 0;
            end
            reset_active = !sample.reset_n;
            batch.epoch += epoch_delta;
            sample.origin = randomized ? 1 : 0;
            translate_admissions(batch, choice, randomized);
            translate_receive(batch, choice, randomized);
            translate_tx(batch, choice, randomized);
            translate_returns(batch, choice, randomized);
            sample.batch = batch;
            for (int q = 0; q < N_Q; ++q)
                sample.counts.queue_credit[queue_id(qid_t'(q), choice)] = counts.queue_credit[q];
        endfunction

        task send_sample(pool_sample_t sample);
            pool_item item = pool_item::type_id::create("edge");
            start_item(item);
            item.sample = sample;
            finish_item(item);
            ++sent_edges;
            if (sample.reset_n && sample.initialized && activity(sample.batch))
                ++activity_edges;
        endtask

        task play(string path, episode_choice choice, bit randomized);
            pool_sample_t sample, prior;
            int file_handle = $fopen(path, "r");
            int seen = 0;
            if (file_handle == 0)
                `uvm_fatal("TRACE_INPUT", {"Cannot read ", path})
            prior = '0;
            while (read_sample(file_handle, sample)) begin
                // Delay selected abort grants with no publication or required
                // following-edge event. Counts and ownership remain constant.
                if (randomized && sample.batch.cleanup.present && !sample.batch.publication.present &&
                    !prior.batch.cell_write.final_cell && choice.extra_wait != 0) begin
                    pool_sample_t idle = prior;
                    idle.batch = '0;
                    idle.batch.present = 1;
                    idle.batch.epoch = epoch;
                    repeat (choice.extra_wait)
                        send_sample(idle);
                end
                translate(sample, choice, randomized);
                send_sample(sample);
                prior = sample;
                ++seen;
            end
            $fclose(file_handle);
            read_edges += seen;
            if (seen == 0)
                `uvm_fatal("TRACE_INPUT", "Empty pool input")
            if (randomized && intent_count != 0)
                `uvm_fatal("STIMULUS_LEDGER", "Random episode did not drain")
        endtask

        task restart_traffic(pool_traffic_ledger ledger);
            pool_sample_t sample = '0;
            ++epoch;
            ledger.restart(epoch);
            sample.origin = 1;
            sample.batch.epoch = epoch;
            repeat (2)
                send_sample(sample);
            sample.reset_n = 1;
            sample.batch.present = 1;
            sample.counts = ledger.counts();
            send_sample(sample);
        endtask

        task random_traffic();
            traffic_choice choice = traffic_choice::type_id::create("traffic");
            pool_traffic_ledger ledger = pool_traffic_ledger::type_id::create("ledger");
            int target = activity_edges + 2048;
            int attempts = 0;
            restart_traffic(ledger);
            while (activity_edges < target) begin
                if (choice.randomize() != 1)
                    `uvm_fatal("STIMULUS_RANDOM", "Traffic constraints unsatisfiable")
                if (choice.reset_chance == 0 && ledger.free_desc < N_DESC)
                    restart_traffic(ledger);
                send_sample(ledger.step(choice, 0));
                if (++attempts > 16384)
                    `uvm_fatal("STIMULUS_LEDGER", "Insufficient generated traffic")
            end
            attempts = 0;
            while (ledger.free_desc < N_DESC) begin
                send_sample(ledger.step(choice, 1));
                if (++attempts > 4 * N_CELL + 4 * N_DESC)
                    `uvm_fatal("STIMULUS_LEDGER", "Random traffic failed to drain")
            end
        endtask

        task body();
            episode_choice choice = episode_choice::type_id::create("choice");
            string names[$], remaining[$], name;
            int file_handle, slot;
            if (template_dir == "") begin
                play(input_path, choice, 0);
                return;
            end
            file_handle = $fopen({template_dir, "/templates.txt"}, "r");
            if (file_handle == 0)
                `uvm_fatal("TRACE_INPUT", "Missing constrained-random episode index")
            while ($fscanf(file_handle, "%s", name) == 1) begin
                names.push_back(name);
                if (!(name inside {remaining}))
                    remaining.push_back(name);
            end
            $fclose(file_handle);
            if (names.size() == 0)
                `uvm_fatal("TRACE_INPUT", "Empty episode index")
            while (remaining.size() != 0 || activity_edges < 2048) begin
                choice.episode_count = remaining.size() != 0 ? remaining.size() : names.size();
                if (choice.randomize() != 1)
                    `uvm_fatal("STIMULUS_RANDOM", "Episode constraints unsatisfiable")
                slot = int'(choice.index);
                if (remaining.size() != 0) begin
                    name = remaining[slot];
                    remaining.delete(slot);
                end else begin
                    name = names[slot];
                end
                play({template_dir, "/", name}, choice, 1);
            end
            random_traffic();
        endtask
    endclass

    // The offline scoreboard sends only checked samples to these covergroups.
    class pool_coverage extends uvm_object;
        `uvm_object_utils(pool_coverage)
        covergroup descriptor_cross with function sample(int returns, int grants, int old_free, int source);
            cp_returns: coverpoint returns { bins count[] = {[0:N_TX+1]}; }
            cp_grants: coverpoint grants { bins count[] = {[0:N_RX]}; }
            cp_old_free: coverpoint old_free { bins bucket[] = {[0:4]}; }
            cp_source: coverpoint source { bins origin[] = {[0:3]}; }
            combinations: cross cp_returns, cp_grants, cp_old_free, cp_source;
        endgroup
        covergroup cell_cross with function sample(int returns, int writes, int old_free, int source);
            cp_returns: coverpoint returns { bins count[] = {[0:N_TX+1]}; }
            cp_writes: coverpoint writes { bins count[] = {[0:1]}; }
            cp_old_free: coverpoint old_free { bins bucket[] = {[0:4]}; }
            cp_source: coverpoint source { bins origin[] = {[0:3]}; }
            combinations: cross cp_returns, cp_writes, cp_old_free, cp_source;
        endgroup

        function new(string name = "pool_coverage");
            super.new(name);
            descriptor_cross = new;
            cell_cross = new;
        endfunction

        task sample_file(string path);
            int handle = $fopen(path, "r");
            int gd, dr, df, ds, cw, cr, cf, cs;
            int seen, status;
            if (handle == 0)
                `uvm_fatal("POOL_COVERAGE", "Missing checked coverage samples")
            status = $fscanf(handle, "%d %d %d %d %d %d %d %d", dr, gd, df, ds, cr, cw, cf, cs);
            while (status == 8) begin
                descriptor_cross.sample(dr, gd, df, ds);
                cell_cross.sample(cr, cw, cf, cs);
                ++seen;
                status = $fscanf(handle, "%d %d %d %d %d %d %d %d", dr, gd, df, ds, cr, cw, cf, cs);
            end
            $fclose(handle);
            if (seen == 0 || status != -1)
                `uvm_fatal("POOL_COVERAGE", "Missing or invalid checked coverage sample")
            $display("POOL_COVERAGE_PASS samples=%0d", seen);
        endtask
    endclass

    class pool_test extends uvm_test;
        `uvm_component_utils(pool_test)
        pool_driver driver;
        uvm_sequencer #(pool_item) sequencer;
        pool_monitor monitor;
        pool_trace trace;
        string coverage_input;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            virtual multi_egress_pool_bus bus;
            if ($value$plusargs("COVER_ROWS=%s", coverage_input))
                return;
            if (!uvm_config_db#(virtual multi_egress_pool_bus)::get(this, "", "bus", bus))
                `uvm_fatal("POOL_CONFIG", "Missing passive observation interface")
            sequencer = new("sequencer", this);
            driver = pool_driver::type_id::create("driver", this);
            monitor = pool_monitor::type_id::create("monitor", this);
            trace = pool_trace::type_id::create("trace", this);
            driver.bus = bus;
            monitor.bus = bus;
        endfunction

        function void connect_phase(uvm_phase phase);
            if (coverage_input == "") begin
                driver.seq_item_port.connect(sequencer.seq_item_export);
                monitor.accepted.connect(trace.analysis_export);
            end
        endfunction

        task run_phase(uvm_phase phase);
            pool_replay_sequence sequence_item = pool_replay_sequence::type_id::create("campaign");
            pool_coverage coverage = pool_coverage::type_id::create("coverage");
            string trace_path;
            int seed;
            phase.raise_objection(this);
            if (coverage_input != "") begin
                coverage.sample_file(coverage_input);
            end else begin
                void'($value$plusargs("REPLAY=%s", sequence_item.input_path));
                void'($value$plusargs("TEMPLATES=%s", sequence_item.template_dir));
                if (!$value$plusargs("MONITOR_OUT=%s", trace_path))
                    `uvm_fatal("POOL_CONFIG", "Missing passive trace output")
                if ($value$plusargs("POOL_SEED=%d", seed))
                    sequence_item.srandom(seed);
                trace.file_handle = $fopen(trace_path, "w");
                if (trace.file_handle == 0)
                    `uvm_fatal("POOL_CONFIG", "Cannot open passive trace output")
                sequence_item.start(sequencer);
                $fclose(trace.file_handle);
                if (trace.edges != sequence_item.sent_edges || sequence_item.read_edges == 0)
                    `uvm_fatal("POOL_MONITOR", "Passive monitor edge count differs from the driven sample count")
                $display("POOL_REPLAY_PASS edges=%0d activity=%0d", trace.edges, sequence_item.activity_edges);
            end
            phase.drop_objection(this);
        endtask
    endclass
endpackage

module multi_egress_pool_replay;
    import uvm_pkg::*;
    import multi_egress_pool_types::*;
    import multi_egress_pool_bench::*;

    bit clk;
    always #5 clk = ~clk;
    multi_egress_pool_bus signals(clk);
    initial begin
        if ($bits(edge_batch_t) != (N_RX == 4 ? 6360 : 3589))
            $fatal(1, "Unexpected pool observation ABI width");
        uvm_config_db#(virtual multi_egress_pool_bus)::set(null, "uvm_test_top", "bus", signals);
        run_test("pool_test");
    end
endmodule
