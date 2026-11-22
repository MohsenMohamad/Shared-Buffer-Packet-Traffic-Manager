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

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void write(pool_item transaction);
            pool_sample_t sample = transaction.sample;
            $fwrite(file_handle, "%0d %0d %0d %0d %0h %0d %0d %0d %0d %0d",
                    sample.edge_number, sample.reset_n, sample.initialized, sample.origin, sample.batch,
                    sample.counts.physical_free, sample.counts.unreserved,
                    sample.counts.reserved_free, sample.counts.assigned, sample.counts.descriptor_free);
            for (int q = 0; q < N_Q; ++q)
                $fwrite(file_handle, " %0d", sample.counts.queue_credit[q]);
            $fwrite(file_handle, "\n");
        endfunction
    endclass

    `include "pool_scoreboard.svh"

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

    // Keep fixture draws local to the sequence. Simulator-wide random state
    // can advance in other UVM processes between replays.
    class fixture_rng;
        int unsigned state;

        function new(int unsigned seed);
            state = seed == 0 ? 1 : seed;
        endfunction

        function int unsigned next_word();
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            return state;
        endfunction

        function int unsigned between(int unsigned upper, int unsigned lower = 0);
            return lower + next_word() % (upper - lower + 1);
        endfunction
    endclass

    `include "pool_random.svh"

    // The sequence composes legal state trajectories. The length table is a
    // stimulus ledger for compatible metadata, independent of monitor results.
    class pool_replay_sequence extends uvm_sequence #(pool_item);
        `uvm_object_utils(pool_replay_sequence)
        string input_path, template_dir;
        int activity_edges;
        int sent_edges;
        int next_edge;
        int seed = 0;
        fixture_rng rng;
        string transport_fault;
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
                    intent_length[index] = 16'(rng.between(maximum, minimum));
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
                    batch.cell_return[lane].owner.tag_value = 16'(rng.next_word());
                    batch.cell_return[lane].address = cell_id_t'(rng.next_word());
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
                    batch.descriptor_return[lane].owner.tag_value = 16'(rng.next_word());
                    batch.descriptor_return[lane].owner.desc = desc_id_t'(rng.next_word());
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
            sample.edge_number = next_edge++;
            if (sample.edge_number == 5 && transport_fault == "lost-edge")
                return;
            if (sample.edge_number == 5 && transport_fault == "duplicate-edge")
                --sample.edge_number;
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
            int target = activity_edges + ACTIVITY_FLOOR;
            int attempts = 0;
            choice.srandom(seed);
            ledger.rng = rng;
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
            rng = new(seed);
            if (template_dir == "") begin
                play(input_path, choice, 0);
                return;
            end
            choice.srandom(seed);
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
            while (remaining.size() != 0 || activity_edges < ACTIVITY_FLOOR) begin
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

    typedef struct {
        string name;
        string detector;
        int edge_number;
    } fault_case_t;

    class pool_test extends uvm_test;
        `uvm_component_utils(pool_test)
        pool_driver driver;
        uvm_sequencer #(pool_item) sequencer;
        pool_monitor monitor;
        pool_trace trace;
        pool_scoreboard scoreboard;
        string fixtures, evidence_dir;
        fault_case_t faults[11];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            faults = '{
                '{"desc-return-bypass", "DESC_PRE_FREE", N_RX == 4 ? 772 : 28},
                '{"cell-return-bypass", "CELL_PRE_FREE", N_RX == 4 ? 1116 : 32},
                '{"descriptor-prefix-repeat", "DESC_PRE_FREE", N_RX == 4 ? 766 : 22},
                '{"credit-return-bypass", "CREDIT_PREFIX", N_RX == 4 ? 1116 : 32},
                '{"physical-exhaustion", "PHYSICAL_EXHAUSTION", N_RX == 4 ? 1116 : 32},
                '{"repeat-return", "DUPLICATE_CELL_RETURN", N_RX == 4 ? 27 : 19},
                '{"omit-high-lane", "TX_CELL_EVENT", N_RX == 4 ? 27 : 19},
                '{"early-abort-credit", "EARLY_CLEANUP_CREDIT", 8},
                '{"stale-owner", "STALE_OWNER", 19},
                '{"omit-final-return", "TX_DESC_EVENT", 12},
                '{"omit-final-cleanup", "DRAIN_OWNERSHIP", 4}
            };
        endfunction

        function void build_phase(uvm_phase phase);
            virtual multi_egress_pool_bus bus;
            if (!uvm_config_db#(virtual multi_egress_pool_bus)::get(this, "", "bus", bus))
                `uvm_fatal("POOL_CONFIG", "Missing passive observation interface")
            sequencer = new("sequencer", this);
            driver = pool_driver::type_id::create("driver", this);
            monitor = pool_monitor::type_id::create("monitor", this);
            trace = pool_trace::type_id::create("trace", this);
            scoreboard = pool_scoreboard::type_id::create("scoreboard", this);
            driver.bus = bus;
            monitor.bus = bus;
        endfunction

        function void connect_phase(uvm_phase phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
            monitor.accepted.connect(trace.analysis_export);
            monitor.accepted.connect(scoreboard.analysis_export);
        endfunction

        function void required_triggers(string name, ref string required[$]);
            case (name)
                "descriptor-empty-return", "descriptor-one-prefix", "descriptor-two-prefix":
                    required = {name, "descriptor-next-edge"};
                "cell-exchange": required = {"cell-one-exchange", "credit-next-edge",
                    "cell-next-edge", "reserved-write-zero-U"};
                "return-lanes": required = {"full-return", "highest-return", "sparse-cleanup"};
                "full-grant-same-q", "full-grant-different-q": required.push_back(name);
                "abort-accounting": required = {"grant-and-abort", "zero-cell-cleanup",
                    "mark-with-staged-write", "nonfinal-abort-reclaim"};
                "active-reset": required = {"active-abort-reset", "epoch-reused-cell-desc-tag", "bound-without-final"};
                "identity-and-drain": required = {"repeated-tag-shared-queue", "zero-and-highest-IDs",
                    "absent-fields", "exact-drain"};
                "crosses": begin
                    for (int kind = 0; kind < 2; ++kind) begin
                        string kind_name;
                        if (kind == 0)
                            kind_name = "descriptor";
                        else
                            kind_name = "cell";
                        for (int ret = 0; ret <= N_TX+1; ++ret)
                            for (int alloc = 0; alloc <= (kind == 0 ? N_RX : 1); ++alloc)
                                for (int bucket = 0; bucket < 5; ++bucket)
                                    for (int origin = 0; origin < 4; ++origin)
                                        if (scoreboard.coverage.exclusion(kind, ret, alloc, bucket, origin) == "")
                                            required.push_back($sformatf("%s:%0d:%0d:%0d:%0d",
                                                kind_name, ret, alloc, bucket, origin));
                    end
                end
                default: return;
            endcase
        endfunction

        task run_case(string name, string detector = "", int divergence = -1, int seed = 0,
                      bit replay = 0, bit raw = 0);
            string required[$];
            string trigger_path = "";
            string path = {fixtures, "/", name, ".edges"};
            pool_replay_sequence scenario = pool_replay_sequence::type_id::create("campaign");
            if (seed != 0) begin
                scenario.seed = seed;
                scenario.srandom(seed);
                scenario.template_dir = fixtures;
            end else if (name == "duplicate-edge" || name == "lost-edge") begin
                scenario.transport_fault = name;
                scenario.input_path = {fixtures, "/identity-and-drain.edges"};
            end else begin
                scenario.input_path = path;
            end
            if (!raw && detector == "" && seed == 0) begin
                required_triggers(name, required);
                trigger_path = {fixtures, "/", name, ".triggers"};
            end
            scoreboard.begin_case(name, required, trigger_path, raw ? "" : detector, divergence, seed, replay);
            trace.file_handle = $fopen({evidence_dir, "/", name, ".edges"}, "w");
            if (trace.file_handle == 0)
                `uvm_fatal("POOL_CONFIG", {"Cannot open passive trace for ", name})
            scenario.start(sequencer);
            $fclose(trace.file_handle);
            scoreboard.end_case(scenario.sent_edges);
        endtask

        task run_phase(uvm_phase phase);
            string selected;
            bit selected_case, raw;
            int bin_report;
            string positives[] = '{"descriptor-empty-return", "descriptor-one-prefix", "descriptor-two-prefix",
                "cell-exchange", "cell-exhaustion", "return-lanes", "full-grant-same-q",
                "full-grant-different-q", "abort-accounting", "final-cleanup", "active-reset",
                "identity-and-drain", "crosses"};
            phase.raise_objection(this);
            if (!$value$plusargs("FIXTURES=%s", fixtures) || !$value$plusargs("EVIDENCE_DIR=%s", evidence_dir))
                `uvm_fatal("POOL_CONFIG", "Missing fixture or evidence directory")
            scoreboard.report = $fopen({evidence_dir, "/witnesses.txt"}, "w");
            bin_report = $fopen({evidence_dir, "/bins.txt"}, "w");
            if (scoreboard.report == 0 || bin_report == 0)
                `uvm_fatal("POOL_CONFIG", "Cannot open checked evidence records")
            selected_case = $value$plusargs("POOL_CASE=%s", selected);
            raw = $test$plusargs("UNQUALIFIED");
            if (raw && !selected_case)
                `uvm_fatal("POOL_CONFIG", "An unqualified run requires a replay case")
            if (selected_case) begin
                bit found = 0;
                foreach (positives[index])
                    if (positives[index] == selected) begin
                        run_case(selected, "", -1, 0, 0, raw);
                        found = 1;
                    end
                foreach (faults[index])
                    if (faults[index].name == selected) begin
                        run_case(selected, faults[index].detector, faults[index].edge_number, 0, 0, raw);
                        found = 1;
                    end
                if (selected == "duplicate-edge" || selected == "lost-edge") begin
                    run_case(selected, "EDGE_SEQUENCE", 5, 0, 0, raw);
                    found = 1;
                end
                if (!found)
                    `uvm_fatal("POOL_SELECTION", {"Unknown case ", selected})
                scoreboard.coverage.check_and_report(bin_report, selected == "crosses");
            end else begin
                foreach (positives[index])
                    run_case(positives[index]);
                foreach (faults[index])
                    run_case(faults[index].name, faults[index].detector, faults[index].edge_number);
                foreach (SEEDS[index]) begin
                    run_case($sformatf("seed-%0d", SEEDS[index]), "", -1, SEEDS[index]);
                    if (index == 0)
                        run_case("replay-17", "", -1, SEEDS[index], 1);
                end
                scoreboard.end_campaign(bin_report);
            end
            $fclose(bin_report);
            $fclose(scoreboard.report);
            phase.drop_objection(this);
        endtask

        function void report_phase(uvm_phase phase);
            uvm_report_server server = uvm_report_server::get_server();
            if (server.get_severity_count(UVM_ERROR) != 0 || server.get_severity_count(UVM_FATAL) != 0)
                `uvm_fatal("POOL_UVM_REPORT", "UVM errors prevent completion")
            $display("POOL_REPLAY_PASS");
        endfunction
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
