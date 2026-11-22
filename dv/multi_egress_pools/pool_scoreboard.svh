    function automatic edge_batch_t normalize(edge_batch_t batch);
        if (!batch.cell_write.present)
            batch.cell_write = '0;
        if (!batch.publication.present)
            batch.publication = '0;
        if (!batch.cleanup.present)
            batch.cleanup = '0;
        if (!batch.read_issue.command.valid)
            batch.read_issue = '0;
        if (!batch.read_response.identity.valid)
            batch.read_response = '0;
        for (int lane = 0; lane < N_RX; ++lane) begin
            if (!batch.admission[lane].present)
                batch.admission[lane] = '0;
            if (!batch.abort_mark[lane].present)
                batch.abort_mark[lane] = '0;
            if (!batch.ingress_service[lane].present)
                batch.ingress_service[lane] = '0;
        end
        for (int lane = 0; lane < N_TX; ++lane) begin
            if (!batch.dispatch[lane].present)
                batch.dispatch[lane] = '0;
            if (!batch.egress_service[lane].present)
                batch.egress_service[lane] = '0;
        end
        for (int lane = 0; lane <= N_TX; ++lane) begin
            if (!batch.cell_return[lane].present)
                batch.cell_return[lane] = '0;
            if (!batch.descriptor_return[lane].present)
                batch.descriptor_return[lane] = '0;
        end
        return batch;
    endfunction

    `include "pool_model.svh"
    `include "pool_coverage.svh"
    `include "pool_witnesses.svh"

    localparam int ACTIVITY_FLOOR = 2048;
    localparam int SEED_COUNT = 8;
    localparam int SEEDS[SEED_COUNT] = '{17, 31, 53, 67, 89, 113, 149, 197};

    typedef enum {
        DESC_ZERO, DESC_ONE, DESC_FULL, CELL_ZERO, CELL_ONE, CELL_FULL,
        GRANT_AND_RETURN, WRITE_AND_RETURN, MIXED_SOURCE, SAME_QUEUE, DIFFERENT_QUEUE,
        RESET_WITH_OWNERSHIP, NEXT_EDGE_REUSE
    } random_feature;
    localparam int FEATURE_COUNT = int'(NEXT_EDGE_REUSE) + 1;

    typedef struct packed {
        bit reset_n;
        bit initialized;
        edge_batch_t accepted;
        pool_counts_t result_counts;
    } checked_edge_t;

    class pool_scoreboard extends uvm_subscriber #(pool_item);
        `uvm_component_utils(pool_scoreboard)
        pool_model model;
        pool_witnesses witnesses;
        pool_coverage coverage;
        string case_name, intended_fault;
        int fault_edge, first_divergence;
        string detected;
        bit isolated;
        int edges, samples, activity_edges, last_checked;
        int case_seed;
        bit replay_seed;
        int report;
        bit [FEATURE_COUNT-1:0] random_features;
        string reached[string];
        int triggers[string];
        checked_edge_t first_seed[$];
        bit [SEED_COUNT-1:0] checked_seeds;
        bit seed_replayed;
        bit [63:0] seed_signatures[bit [63:0]];
        bit [63:0] signature;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            coverage = new;
        endfunction

        function void begin_case(string name, string required[$], string trigger_path,
                                 string fault, int divergence, int seed, bit replay);
            int input_file, status, edge_number;
            string label;
            case_name = name;
            intended_fault = fault;
            fault_edge = divergence;
            case_seed = seed;
            replay_seed = replay;
            model = new;
            witnesses = new;
            triggers.delete();
            reached.delete();
            detected = "";
            first_divergence = -1;
            last_checked = -1;
            isolated = 0;
            edges = 0;
            samples = 0;
            activity_edges = 0;
            signature = 64'hcbf29ce484222325;
            if (trigger_path == "")
                return;

            input_file = $fopen(trigger_path, "r");
            if (input_file == 0)
                `uvm_fatal("DIRECTED_CONFIG", {"Missing trigger schedule for ", name})
            status = $fscanf(input_file, "%d %s", edge_number, label);
            while (status == 2) begin
                if (edge_number < 0 || triggers.exists(label) != 0)
                    `uvm_fatal("DIRECTED_CONFIG", {"Invalid or duplicate trigger ", label})
                triggers[label] = edge_number;
                status = $fscanf(input_file, "%d %s", edge_number, label);
            end
            $fclose(input_file);
            if (status != -1 || triggers.num() != required.size())
                `uvm_fatal("DIRECTED_CONFIG", {"Malformed or incomplete trigger schedule for ", name})
            foreach (required[index])
                if (triggers.exists(required[index]) == 0)
                    `uvm_fatal("DIRECTED_CONFIG", {"Missing required trigger ", required[index]})
        endfunction

        function void divergence(string code, int edge_number, string detail = "");
            if (code != intended_fault || detected != "" || edge_number != fault_edge)
                $fatal(1, "POOL_CHECK_FAILED %s %s edge=%0d %s", code, case_name, edge_number, detail);
            detected = code;
            first_divergence = edge_number;
            // The stale return is rejected before any state change. Continue
            // checking its legal suffix through drain.
            isolated = code != "STALE_OWNER";
            $display("POOL_DETECTED %s %s edge=%0d %s", case_name, code, edge_number, detail);
        endfunction

        function void check_triggers(pool_sample_t sample, edge_features_t observed,
                                     pool_counts_t pre, pool_counts_t post);
            foreach (triggers[label]) begin
                if (sample.edge_number != triggers[label])
                    continue;
                if (!witnesses.matches_witness(label, sample.batch, observed, pre, post))
                    `uvm_fatal("DIRECTED_TRIGGER", $sformatf("%s %s edge=%0d",
                               case_name, label, sample.edge_number))
                reached[label] = label;
                $fdisplay(report, "witness %s %s %0d %h %h %h %h %0d",
                          case_name, label, sample.edge_number, pre, post, observed.desc_mask,
                          observed.cell_mask, observed.grants);
            end
        endfunction

        function void sample_bins(pool_sample_t sample, edge_features_t observed,
                                  pool_counts_t pre);
            int desc_returns = $countones(observed.desc_mask);
            int cell_returns = $countones(observed.cell_mask);
            int desc_bucket = occupancy_bucket(int'(pre.descriptor_free), N_DESC);
            int cell_bucket = occupancy_bucket(int'(pre.physical_free), N_CELL);
            int desc_source = return_source(observed.desc_mask);
            int cell_source = return_source(observed.cell_mask);

            if (!sample.reset_n && case_seed != 0 && !replay_seed && pre.descriptor_free < N_DESC)
                random_features[RESET_WITH_OWNERSHIP] = 1;
            if (!sample.reset_n || !sample.initialized)
                return;
            ++samples;
            if (intended_fault == "" && !replay_seed)
                coverage.sample(observed.grants, int'(sample.batch.cell_write.present),
                    desc_returns, cell_returns, desc_bucket, cell_bucket, desc_source, cell_source,
                    case_seed != 0);
            if (case_seed == 0 || !has_events(sample.batch))
                return;
            ++activity_edges;
            if (replay_seed)
                return;
            random_features[DESC_ZERO] |= desc_bucket == 0;
            random_features[DESC_ONE] |= desc_bucket == 1;
            random_features[DESC_FULL] |= desc_bucket == 4;
            random_features[CELL_ZERO] |= cell_bucket == 0;
            random_features[CELL_ONE] |= cell_bucket == 1;
            random_features[CELL_FULL] |= cell_bucket == 4;
            random_features[GRANT_AND_RETURN] |= observed.grants > 0 && desc_returns > 0;
            random_features[WRITE_AND_RETURN] |= sample.batch.cell_write.present && cell_returns > 0;
            random_features[MIXED_SOURCE] |= desc_source == 3 || cell_source == 3;
            random_features[SAME_QUEUE] |= observed.grants > 1 && $countones(observed.queues) == 1;
            random_features[DIFFERENT_QUEUE] |= $countones(observed.queues) > 1;
            random_features[NEXT_EDGE_REUSE] |= observed.reused_cell || observed.reused_desc;
        endfunction

        function void check_seed_replay(pool_sample_t sample, pool_counts_t expected);
            checked_edge_t record_data;
            logic [64*(($bits(checked_edge_t)+63)/64)-1:0] words;
            if (case_seed == 0)
                return;
            record_data = '{sample.reset_n, sample.initialized, normalize(sample.batch), expected};
            if (replay_seed) begin
                if (sample.edge_number >= first_seed.size() || first_seed[sample.edge_number] !== record_data)
                    `uvm_fatal("SEED_REPLAY", $sformatf("Seed %0d diverged at edge %0d", case_seed, sample.edge_number))
            end else if (case_seed == SEEDS[0]) begin
                first_seed.push_back(record_data);
            end

            // Distinct-seed diagnostic. Replay itself is checked edge for edge.
            words = (64*(($bits(checked_edge_t)+63)/64))'(record_data);
            for (int offset = 0; offset < $bits(words); offset += 64)
                signature = (signature ^ words[offset +: 64]) * 64'h100000001b3;
        endfunction

        function void write(pool_item transaction);
            pool_sample_t sample = transaction.sample;
            pool_counts_t pre, post;
            edge_features_t observed;
            string failure;
            if (!isolated && sample.edge_number != edges)
                divergence("EDGE_SEQUENCE", edges, $sformatf("observed index=%0d", sample.edge_number));
            ++edges;
            if (isolated)
                return;

            failure = model.measure(pre);
            if (failure != "")
                divergence(failure, sample.edge_number);
            if (!sample.reset_n && model.running)
                witnesses.before_reset(model);
            failure = model.advance(sample, pre, sample.edge_number, post);
            if (failure != "") begin
                divergence(failure, sample.edge_number,
                           $sformatf("pre=%h expected_post=%h observed_post=%h", pre, post, sample.counts));
                if (!isolated) begin
                    if (model.measure(post) != "" || pre !== post || post !== sample.counts)
                        `uvm_fatal("STALE_OWNER_EFFECT", "Stale return changed post-edge accounting")
                    witnesses.remember(edge_batch_t'('0), pre);
                end
                return;
            end
            observed = witnesses.observe(sample.batch);
            check_triggers(sample, observed, pre, post);
            sample_bins(sample, observed, pre);
            check_seed_replay(sample, post);
            witnesses.remember(sample.batch, pre);
            last_checked = sample.edge_number;
        endfunction

        function void end_case(int emitted);
            string failure;
            int seed_index = -1;
            if (edges == 0 || samples == 0)
                `uvm_fatal("EMPTY_OBSERVATION", case_name)
            if (edges != emitted)
                `uvm_fatal("MONITOR_EDGE_COUNT", $sformatf("%s observed=%0d sent=%0d", case_name, edges, emitted))
            if (!isolated) begin
                failure = model.drained();
                if (failure != "")
                    divergence(failure, edges - 1);
            end
            if (detected != intended_fault)
                `uvm_fatal("MUTATION_NOT_DETECTED", case_name)
            if (detected == "STALE_OWNER" && last_checked <= first_divergence)
                `uvm_fatal("STALE_REPLAY_NEIGHBOR", case_name)
            if (reached.num() != triggers.num())
                `uvm_fatal("MISSING_TRIGGERS", case_name)
            if (case_seed != 0) begin
                foreach (SEEDS[index])
                    if (SEEDS[index] == case_seed)
                        seed_index = index;
                if (seed_index < 0 || activity_edges < ACTIVITY_FLOOR)
                    `uvm_fatal("SEED_ACTIVITY", $sformatf("%s activity=%0d", case_name, activity_edges))
                if (replay_seed) begin
                    if (seed_index != 0 || edges != first_seed.size() || seed_replayed)
                        `uvm_fatal("SEED_REPLAY", "Missing, truncated or duplicate seed-17 replay")
                    seed_replayed = 1;
                end else begin
                    if (checked_seeds[seed_index] || seed_signatures.exists(signature) != 0)
                        `uvm_fatal("SEED_DISTINCT", case_name)
                    seed_signatures[signature] = 1;
                    checked_seeds[seed_index] = 1;
                end
            end
            $display("POOL_CASE_PASS %s edges=%0d activity=%0d signature=%016h",
                     case_name, edges, activity_edges, signature);
        endfunction

        function void end_campaign(int bin_report);
            if (!(&checked_seeds) || !seed_replayed || !(&random_features))
                `uvm_fatal("CAMPAIGN", $sformatf("seeds=%b replay=%b features=%b",
                           checked_seeds, seed_replayed, random_features))
            coverage.check_and_report(bin_report, 1);
        endfunction
    endclass
