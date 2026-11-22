package tm_pool_smoke_pkg;
    import uvm_pkg::*;
    import tm_pool_smoke_types::*;
    `include "uvm_macros.svh"

    function automatic void require(bit condition, string detector);
        if (!condition) `uvm_fatal("POOL_SMOKE", detector)
    endfunction

    class pool_monitor extends uvm_monitor;
        `uvm_component_utils(pool_monitor)
        virtual tm_pool_smoke_if bus;
        uvm_analysis_port #(pool_edge_t) completed_edge;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            completed_edge = new("completed_edge", this);
        endfunction

        task run_phase(uvm_phase phase);
            int index = 0;
            forever begin
                pool_edge_t transaction;
                @(posedge bus.clk);
                transaction.index = index++;
                transaction.reset_n = bus.rst_n;
                transaction.intent = bus.intent;
                transaction.pins = bus.pins;
                transaction.pre = bus.sampled;
                #1ns;
                transaction.post = bus.sampled;
                completed_edge.write(transaction);
            end
        endtask
    endclass

    class pool_driver extends uvm_driver;
        `uvm_component_utils(pool_driver)
        virtual tm_pool_smoke_if bus;
        int unsigned noise;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function automatic int unsigned next_noise(bit vary);
            if (!vary) return 0;
            noise ^= noise << 13;
            noise ^= noise >> 17;
            noise ^= noise << 5;
            return noise;
        endfunction

        function mask_t choose_commits(batch_t batch, int alpha);
            counts_t prefix = bus.sampled.counts;
            mask_t commit = '0;
            for (int lane = 0; lane < PORTS; ++lane) begin
                request_t candidate = batch.requests[lane];
                int remaining = int'(prefix.u) - int'(candidate.cells);
                int occupancy = int'(prefix.h[candidate.qid]) + int'(candidate.cells);
                if (!candidate.present || candidate.cells == 0 ||
                    int'(candidate.cells) > MAX_FRAME_CELLS || remaining < 0 || prefix.d == 0)
                    continue;
                if (alpha >= 0 && occupancy > (alpha * remaining) / 256) continue;
                commit[lane] = 1;
                prefix.u = count_t'(remaining);
                prefix.h[candidate.qid] = count_t'(occupancy);
                --prefix.d;
            end
            return commit;
        endfunction

        task prepare(batch_t batch, mask_t commit, qid_t [PORTS-1:0] tx_queues,
                     qid_t cleanup_queue, desc_t cleanup_descriptor, bit vary = 1);
            drive_t pins = '0;
            pins.commit = commit;
            pins.write_offer = batch.write_token != 0 || batch.blocked_write;
            pins.tx_final = mask_t'(next_noise(vary));
            for (int lane = 0; lane < PORTS; ++lane) begin
                request_t offer = batch.requests[lane];
                retire_t tx = batch.tx[lane];
                pins.cells[lane] = offer.present ? offer.cells : count_t'(next_noise(vary));
                pins.qid[lane] = offer.present ? offer.qid : qid_t'(next_noise(vary));
                pins.tx_present[lane] = tx.token != 0;
                if (tx.token != 0) pins.tx_final[lane] = tx.last;
                pins.tx_cell[lane] = tx.token != 0 ? tx.address : cell_t'(next_noise(vary));
                pins.tx_qid[lane] = tx.token != 0 && vary ? tx_queues[lane] : qid_t'(next_noise(vary));
                pins.tx_desc[lane] = tx.token != 0 && tx.last ? tx.descriptor : desc_t'(next_noise(vary));
            end
            pins.cleanup_present = batch.cleanup.token != 0;
            pins.cleanup_done = pins.cleanup_present ? batch.cleanup.done : 1'(next_noise(vary));
            pins.cleanup_has_cell = pins.cleanup_present ? batch.cleanup.has_cell : 1'(next_noise(vary));
            pins.cleanup_cell = batch.cleanup.has_cell ? batch.cleanup.address : cell_t'(next_noise(vary));
            pins.cleanup_qid = pins.cleanup_present && vary ? cleanup_queue : qid_t'(next_noise(vary));
            pins.cleanup_desc = batch.cleanup.done && vary ? cleanup_descriptor : desc_t'(next_noise(vary));
            pins.cleanup_released = batch.cleanup.done ? batch.cleanup.released : count_t'(next_noise(vary));
            bus.intent = batch;
            bus.pins = pins;
        endtask

        task pulse();
            #1ns;
            bus.clk = 1;
            #2ns;
            bus.clk = 0;
        endtask
    endclass

    `include "tm_pool_smoke_model.svh"
    `include "tm_pool_smoke_coverage.svh"
    `include "tm_pool_smoke_scoreboard.svh"
    `include "tm_pool_smoke_sequences.svh"
endpackage
