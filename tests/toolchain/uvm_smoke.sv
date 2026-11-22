`timescale 1ns/1ps
// Simulator capability fixture; independent of the traffic-manager RTL.
interface tm_cap_if(input logic clk);
    logic rst_n,s_valid,s_ready,m_valid,m_ready;
    logic [31:0] s_data,m_data;
    int unsigned s_qid, s_len;
endinterface

module tm_cap_pipe(tm_cap_if v);
    assign v.s_ready=!v.m_valid || v.m_ready;
    always @(posedge v.clk or negedge v.rst_n)
        if(!v.rst_n) begin v.m_valid<=0;v.m_data<=0;end
        else if(v.s_ready) begin
            v.m_valid<=v.s_valid;
            if(v.s_valid) v.m_data<=v.s_data;
        end
        else if($test$plusargs("MUTATION_HOLD") && v.m_valid && !v.m_ready)
            v.m_data<=v.m_data+1;
    property hold_output;
        @(posedge v.clk) disable iff(!v.rst_n)
        v.m_valid && !v.m_ready |=> v.m_valid && $stable(v.m_data);
    endproperty
    a_hold: assert property(hold_output)
        else $fatal(1,"TM_CAP_STABILITY_FAIL");
endmodule

package tm_cap_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    class tm_cap_item extends uvm_sequence_item;
        `uvm_object_utils(tm_cap_item)
        rand bit [31:0] data;
        rand int unsigned qid,len;
        constraint legal { qid inside {[0:3]}; len inside {[1:128]}; }
        function new(string name="item");super.new(name);endfunction
    endclass
    localparam int TRANSACTIONS = 64;
    typedef struct packed {
        logic [31:0] data;
        int unsigned qid, len;
    } cap_record_t;

    class tm_cap_scoreboard extends uvm_component;
        `uvm_component_utils(tm_cap_scoreboard)
        cap_record_t pending[$];
        cap_record_t checked[TRANSACTIONS];
        bit [3:0][2:0] hits;
        int accepted, retired;

        covergroup cg with function sample(int qid, int len);
            option.per_instance = 1;
            q: coverpoint qid { bins queues[] = {[0:3]}; }
            l: coverpoint len {
                bins short_pkt = {[1:8]};
                bins mid_pkt = {[9:64]};
                bins long_pkt = {[65:128]};
            }
            ql: cross q, l;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg = new;
        endfunction

        function void begin_seed();
            accepted = 0;
            retired = 0;
            hits = '0;
        endfunction

        function void observe(bit output_accept, logic [31:0] output_data,
                              bit input_accept, cap_record_t input_record);
            cap_record_t expected;
            int bucket;
            if (output_accept) begin
                if (pending.size() == 0 || retired >= TRANSACTIONS)
                    `uvm_fatal("CAP_SURPLUS", "Output transfer has no matching input")
                expected = pending.pop_front();
                if (output_data !== expected.data)
                    `uvm_fatal("CAP_DATA", $sformatf("Transfer %0d differs from accepted input", retired))
                checked[retired++] = expected;
                bucket = expected.len <= 8 ? 0 : (expected.len <= 64 ? 1 : 2);
                hits[expected.qid][bucket] = 1;
                cg.sample(int'(expected.qid), int'(expected.len));
            end
            if (input_accept) begin
                if (input_record.qid > 3 || !(input_record.len inside {[1:128]}))
                    `uvm_fatal("CAP_CONSTRAINT", "Accepted input metadata is outside the legal range")
                pending.push_back(input_record);
                ++accepted;
            end
        endfunction

        function void end_seed(int seed);
            if (pending.size() != 0 || accepted != TRANSACTIONS || retired != TRANSACTIONS)
                `uvm_fatal("CAP_DRAIN", $sformatf("Seed %0d accepted=%0d retired=%0d", seed, accepted, retired))
            if (!(&hits))
                `uvm_fatal("CAP_BINS", $sformatf("Seed %0d cross bins=%b", seed, hits))
            $display("TM_CAP_SEED_PASS seed=%0d transactions=%0d crosses=12", seed, retired);
        endfunction
    endclass

    class tm_cap_monitor extends uvm_monitor;
        `uvm_component_utils(tm_cap_monitor)
        virtual tm_cap_if v;
        tm_cap_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                @(posedge v.clk);
                if (v.rst_n)
                    scoreboard.observe(v.m_valid && v.m_ready, v.m_data,
                                       v.s_valid && v.s_ready, '{v.s_data, v.s_qid, v.s_len});
            end
        endtask
    endclass

    class tm_cap_test extends uvm_test;
        `uvm_component_utils(tm_cap_test)
        virtual tm_cap_if v;
        tm_cap_monitor monitor;
        tm_cap_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual tm_cap_if)::get(this, "", "vif", v))
                `uvm_fatal("PROBE", "Missing interface")
            monitor = tm_cap_monitor::type_id::create("monitor", this);
            scoreboard = tm_cap_scoreboard::type_id::create("scoreboard", this);
            monitor.v = v;
            monitor.scoreboard = scoreboard;
        endfunction

        task exercise(int seed);
            tm_cap_item item = tm_cap_item::type_id::create("input");
            int qid, len_low, len_high;
            item.srandom(seed);
            scoreboard.begin_seed();
            v.rst_n = 0;
            v.s_valid = 0;
            v.m_ready = 0;
            repeat (4) @(negedge v.clk);
            v.rst_n = 1;
            for (int index = 0; index < TRANSACTIONS; ++index) begin
                if (index < 12) begin
                    // Guarantee each queue/range cross, with random data and length within the range.
                    qid = index / 3;
                    len_low = index % 3 == 0 ? 1 : (index % 3 == 1 ? 9 : 65);
                    len_high = index % 3 == 0 ? 8 : (index % 3 == 1 ? 64 : 128);
                    if (item.randomize() with {qid == local::qid; len inside {[len_low:len_high]};} != 1)
                        `uvm_fatal("PROBE", "Directed cross randomization failed")
                end else if (item.randomize() != 1) begin
                    `uvm_fatal("PROBE", "Randomization failed")
                end
                v.s_valid = 1;
                v.s_data = item.data;
                v.s_qid = item.qid;
                v.s_len = item.len;
                v.m_ready = 0;
                do @(posedge v.clk); while (!v.s_ready);
                @(negedge v.clk);
                v.s_valid = 0;
                repeat (3) @(negedge v.clk);
                v.m_ready = 1;
                @(posedge v.clk);
                @(negedge v.clk);
            end
            scoreboard.end_seed(seed);
        endtask

        task run_phase(uvm_phase phase);
            tm_cap_item impossible = tm_cap_item::type_id::create("unsat");
            cap_record_t baseline[TRANSACTIONS];
            string seed_path;
            int seed, handle, scanned;
            int seeds[$];
            bit distinct_seed = 0;
            phase.raise_objection(this);
            if (impossible.randomize() with { qid == 99; } != 0)
                `uvm_fatal("PROBE", "Unsatisfiable constraints accepted")
            $display("TM_CAP_UNSAT_PASS");
            if (!$value$plusargs("CAP_SEEDS=%s", seed_path))
                `uvm_fatal("CAP_SEEDS", "Missing seed input")
            handle = $fopen(seed_path, "r");
            if (handle == 0)
                `uvm_fatal("CAP_SEEDS", "Cannot open seed input")
            scanned = $fscanf(handle, "%d", seed);
            while (scanned == 1) begin
                if (seed < 1 || seed inside {seeds})
                    `uvm_fatal("CAP_SEEDS", "Invalid or duplicate seed")
                seeds.push_back(seed);
                scanned = $fscanf(handle, "%d", seed);
            end
            $fclose(handle);
            if (scanned != -1 || seeds.size() < 2)
                `uvm_fatal("CAP_SEEDS", "At least two valid seeds are required")

            if ($test$plusargs("MUTATION_HOLD")) begin
                exercise(seeds[0]);
                `uvm_fatal("CAP_MUTATION_MISSED", "Held-output assertion did not fire")
            end
            exercise(seeds[0]);
            baseline = scoreboard.checked;
            for (int index = 1; index < seeds.size(); ++index) begin
                exercise(seeds[index]);
                distinct_seed |= scoreboard.checked != baseline;
            end
            exercise(seeds[0]);
            if (!distinct_seed || scoreboard.checked != baseline)
                `uvm_fatal("CAP_REPLAY", "Checked transactions failed seed variation or exact replay")
            $display("TM_CAP_REPLAY_PASS seed=%0d", seeds[0]);
            phase.drop_objection(this);
        endtask

        function void report_phase(uvm_phase phase);
            uvm_report_server server = uvm_report_server::get_server();
            if (server.get_severity_count(UVM_ERROR) != 0 || server.get_severity_count(UVM_FATAL) != 0)
                `uvm_fatal("CAP_REPORT", "UVM errors prevent completion")
            $display("TM_UVM_SMOKE_PASS");
        endfunction
    endclass
endpackage

module tm_uvm_capabilities;
    import uvm_pkg::*;
    import tm_cap_pkg::*;
    logic clk=0;
    always #5 clk=~clk;
    tm_cap_if v(clk);
    tm_cap_pipe dut(v);
    initial begin
        uvm_config_db#(virtual tm_cap_if)::set(null,"uvm_test_top","vif",v);
        run_test("tm_cap_test");
    end
    initial if($test$plusargs("TRACE")) begin
        $dumpfile("wave.vcd"); $dumpvars(0,tm_uvm_capabilities);
    end
    initial begin #1000000000; $fatal(1,"TM_CAP_TIMEOUT");end
endmodule
