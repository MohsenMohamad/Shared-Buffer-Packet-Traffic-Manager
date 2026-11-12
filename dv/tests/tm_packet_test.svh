// Capability checks precede generated traffic in the registered runner.
class tm_packet_constraints_test extends uvm_test;
    `uvm_component_utils(tm_packet_constraints_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        tm_packet packet = new;
        int result;
        phase.raise_objection(this);
        if(packet.randomize() != 1) `uvm_fatal("PACKET_RANDOMIZE", "legal packet constraints failed")
        result = packet.randomize() with {length == 0;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "zero length accepted")
        result = packet.randomize() with {length == MAX_PACKET_BYTES+1;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "oversize length accepted")
        result = packet.randomize() with {qid == N_Q;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "invalid queue accepted")
        result = packet.randomize() with {source == N_RX;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "invalid source accepted")
        result = packet.randomize() with {final_keep == 0;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "empty keep accepted")
        result = packet.randomize() with {beat_count == 0;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "inconsistent beat count accepted")
        result = packet.randomize() with {cell_count == 0;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "inconsistent cell count accepted")
        result = packet.randomize() with {pattern == 4;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "unknown pattern accepted")
        result = packet.randomize() with {gap == 4;};
        if(result != 0) `uvm_fatal("PACKET_UNSAT", "unsupported gap accepted")
        `uvm_info("PACKET", "TM_PACKET_CONSTRAINTS_PASS rejected=9", UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass

class tm_packet_sequence extends uvm_sequence;
    `uvm_object_utils(tm_packet_sequence)
    `uvm_declare_p_sequencer(tm_virtual_sequencer)
    int stimulus_file, packet_index;
    function new(string name="packet_sequence");
        super.new(name);
        packet_index = 0;
    endfunction

    function void record_item(tm_packet packet, tm_stream_item item, string phase_name, int expected_status);
        $fwrite(stimulus_file, "{\"index\":%0d,\"phase\":\"%s\",\"source\":%0d,\"qid\":%0d,\"length\":%0d,\"class\":%0d,\"pattern\":%0d,\"payload_seed\":%0d,\"gap\":%0d,\"tag\":%0d,\"beat_count\":%0d,\"cell_count\":%0d,\"final_keep\":%0d,\"expected_status\":%0d,\"beats\":[",
            packet_index++, phase_name, packet.source, packet.qid, packet.length, packet.length_class,
            packet.pattern, packet.payload_seed, packet.gap, packet.tag, item.beats.size(), packet.cell_count,
            packet.final_keep, expected_status);
        foreach(item.beats[index]) begin
            $fwrite(stimulus_file, "%s{\"data\":\"%h\",\"keep\":%0d,\"last\":%0d,\"user\":\"%h\"}",
                index == 0 ? "" : ",", item.beats[index].data, item.beats[index].keep,
                item.beats[index].last, item.beats[index].user);
        end
        $fdisplay(stimulus_file, "]}");
        $fflush(stimulus_file);
    endfunction

    task send_item(tm_packet packet, tm_stream_item item, string phase_name, int expected_status=0);
        tm_environment env = p_sequencer.env;
        tm_packet_item_sequence sequence_item = new;
        int previous_statuses = env.coordinator.service_model.status_count;
        int previous_deliveries = env.coordinator.bytes_model.delivered;
        bit finished = 0;
        record_item(packet, item, phase_name, expected_status);
        sequence_item.item = item;
        sequence_item.start(env.rx[packet.source].sequencer);
        // Keep the generator qualification below resource limits. Admission
        // pressure/concurrency remain covered by independent existing probes.
        for(int cycle=0; cycle<4000; cycle++) begin
            @(negedge env.observe.clk);
            if(env.coordinator.service_model.status_count == previous_statuses+1 &&
               env.coordinator.bytes_model.delivered == previous_deliveries+(expected_status == 0 ? 1 : 0) &&
               env.coordinator.service_model.unreserved_cells == N_CELL) begin
                finished = 1;
                break;
            end
        end
        if(!finished) `uvm_fatal("PACKET_PROGRESS", "packet did not reach its expected disposition/delivery")
        repeat(3) @(negedge env.observe.clk);
        env.coordinator.drained();
    endtask

    task send_legal(int target_length=-1, int target_source=-1, int target_queue=-1, int target_pattern=-1,
                    string phase_name="random");
        tm_packet packet = new;
        int succeeded;
        if($test$plusargs("MUT_PACKET_RANDOMIZE"))
            succeeded = packet.randomize() with {length == 0;};
        else
            succeeded = packet.randomize() with {
                if(local::target_length >= 0) length == local::target_length;
                if(local::target_source >= 0) source == local::target_source;
                if(local::target_queue >= 0) qid == local::target_queue;
                if(local::target_pattern >= 0) pattern == local::target_pattern;
                tag == 7; // Deliberate duplicate tags in every generated packet.
            };
        if(succeeded != 1) `uvm_fatal("PACKET_RANDOMIZE", "packet randomization failed; no item was sent")
        send_item(packet, packet.to_stream_item(), phase_name);
    endtask

    // Deliberate errors mutate raw items after legal construction. No legal
    // constraint is disabled or widened to admit malformed traffic.
    task directed_errors();
        tm_packet packet;
        tm_stream_item item;
        int expected_status;
        for(int scenario=0; scenario<10; scenario++) begin
            packet = new;
            if(packet.randomize() with {length == 9; source == 0; qid == 0; tag == 7;} != 1)
                `uvm_fatal("PACKET_RANDOMIZE", "directed template randomization failed")
            item = packet.to_stream_item();
            expected_status = int'(FRAME_ERROR);
            case(scenario)
                0: begin item.beats[0].user[7:0] = 255; expected_status = int'(BAD_QID); end
                1: begin item.beats[0].user[23:8] = 0; expected_status = int'(BAD_LENGTH); end
                2: begin item.beats[0].user[23:8] = 16'(MAX_PACKET_BYTES+1); expected_status = int'(BAD_LENGTH); end
                3: item.beats[0].keep = 8'h55;
                4: item.beats[0].keep = 0;
                5: item.beats[0].keep = 1;
                6: item.beats[1].keep = 3;
                7: begin item.beats[0].last = 1; item.beats.delete(1); item.gaps.delete(1); end
                8: begin
                    beat_t extra = item.beats[1];
                    item.beats[1].last = 0;
                    item.beats.push_back(extra);
                    item.gaps.push_back(int'(packet.gap));
                end
                9: begin item.beats[1].user = '1; expected_status = int'(COMMITTED); end
            endcase
            send_item(packet, item, $sformatf("directed-%0d", scenario), expected_status);
        end
    endtask

    task body();
        int boundaries[9] = '{1, 7, 8, 9, CELL_BYTES-1, CELL_BYTES, CELL_BYTES+1, MAX_PACKET_BYTES-1, MAX_PACKET_BYTES};
        stimulus_file = $fopen("stimulus.jsonl", "w");
        if(stimulus_file == 0) `uvm_fatal("PACKET_RECORD", "cannot open stimulus record")
        foreach(boundaries[index]) send_legal(boundaries[index], -1, -1, index%4, "boundary");
        for(int width=1; width<=8; width++) send_legal(width, -1, -1, -1, "keep-width");
        for(int q=0; q<N_Q; q++) send_legal(-1, q%N_RX, q, q%4, "profile-lanes");
        repeat(128) send_legal();
        directed_errors();
        $fclose(stimulus_file);
    endtask
endclass

class tm_packet_test extends tm_foundation_test;
    `uvm_component_utils(tm_packet_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        tm_sink_sequence sink_sequence = new;
        tm_packet_sequence packet_sequence = new;
        phase.raise_objection(this);
        env.observe.rst_n = 0;
        repeat(4) @(negedge env.observe.clk);
        env.observe.rst_n = 1;
        fork sink_sequence.start(env.tx.sequencer); join_none
        for(int order=0; order<3; order++) begin
            tm_bus_sequence bus_sequence = new;
            bus_sequence.order = order;
            bus_sequence.start(env.axil.sequencer);
        end
        packet_sequence.start(sequencer);
        sink_sequence.kill();
        env.coordinator.drained();
        `uvm_info("PACKET", $sformatf("TM_PACKET_PASS packets=%0d captures=%0d delivered=%0d",
            packet_sequence.packet_index, env.coverage_collector.captures, env.coordinator.bytes_model.delivered), UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass
