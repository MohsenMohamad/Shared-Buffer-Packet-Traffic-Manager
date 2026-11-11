class tm_source_sequence extends uvm_sequence #(tm_stream_item);
    `uvm_object_utils(tm_source_sequence)
    int length=9,qid=0,tag=7,pattern=1,gap=0;
    bit malformed;
    function new(string name="source_sequence");super.new(name);endfunction
    task body();
        tm_stream_item x=new;
        beat_t beat;
        int count;
        for(int offset=0;offset<length;offset+=8) begin
            count=(length-offset>=8)?8:length-offset;
            beat='0;beat.keep=8'((1<<count)-1);beat.last=(offset+8>=length);
            beat.user={24'(offset==0?0:123),16'(tag),16'(length),8'(qid)};
            for(int lane=0;lane<8;lane++) beat.data[lane*8+:8]=8'(pattern+offset+lane);
            if(malformed && offset==0) beat.keep=8'h55;
            x.beats.push_back(beat);x.gaps.push_back(gap);
        end
        start_item(x);finish_item(x);
    endtask
endclass

class tm_sink_sequence extends uvm_sequence #(tm_stream_item);
    `uvm_object_utils(tm_sink_sequence)
    function new(string name="sink_sequence");super.new(name);endfunction
    task body();
        tm_stream_item x;
        forever begin
            x=new;x.stall_cycles=$urandom_range(0,7);x.ready_cycles=$urandom_range(1,9);
            start_item(x);finish_item(x);
        end
    endtask
endclass

class tm_bus_sequence extends uvm_sequence #(tm_axil_item);
    `uvm_object_utils(tm_bus_sequence)
    int order;
    bit read_only,expect_reset;
    int response_stall=5;
    bit [31:0] address=0;
    function new(string name="bus_sequence");super.new(name);endfunction
    task body();
        tm_axil_item x=new;
        tm_axil_item response;
        x.write=!read_only;x.addr=address;x.data=32'h12345678;x.aw_delay=order==0?6:0;x.w_delay=order==2?6:0;x.response_stall=response_stall;
        start_item(x);finish_item(x);get_response(response);
        if(response.response!=(expect_reset?SLVERR:OKAY)) `uvm_fatal("BUS_RESPONSE","fixture write failed")
    endtask
endclass

// This sequencer coordinates stream, register and reset phases explicitly.
class tm_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(tm_virtual_sequencer)
    tm_environment env;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
endclass
class tm_foundation_sequence extends uvm_sequence;
    `uvm_object_utils(tm_foundation_sequence)
    `uvm_declare_p_sequencer(tm_virtual_sequencer)
    function new(string name="foundation_sequence");super.new(name);endfunction
    task send(int port,int length,int qid,int pattern,bit malformed=0);
        tm_source_sequence s=new;
        s.length=length;s.qid=qid;s.pattern=pattern;s.gap=pattern%3;s.malformed=malformed;
        s.start(p_sequencer.env.rx[port].sequencer);
    endtask
    task body();
        uvm_status_e status;
        uvm_reg_data_t data;
        tm_bus_sequence bus_seq;
        tm_environment e=p_sequencer.env;
        for(int order=0;order<3;order++) begin bus_seq=new;bus_seq.order=order;bus_seq.start(e.axil.sequencer);end
        fork
            begin tm_bus_sequence read_seq=new;read_seq.read_only=1;read_seq.start(e.axil.sequencer);end
            begin tm_bus_sequence write_seq=new;write_seq.order=0;write_seq.start(e.axil.sequencer);end
        join
        e.registers.control.write(status,64'h0badcafe,UVM_FRONTDOOR);
        if(status!=UVM_IS_OK) `uvm_fatal("RAL_WRITE","frontdoor write failed")
        e.registers.control.read(status,data,UVM_FRONTDOOR);
        if(status!=UVM_IS_OK || data!=64'h0badcafe || e.registers.control.get_mirrored_value()!=data) `uvm_fatal("RAL_PREDICT","frontdoor read/predict mismatch")
        e.registers.control.write(status,64'h0badcaff,UVM_FRONTDOOR);
        e.registers.control.mirror(status,UVM_CHECK,UVM_FRONTDOOR);
        if(status!=UVM_IS_OK) `uvm_fatal("RAL_MIRROR","frontdoor mirror failed")
        // All ports and queues, repeated tags, partial words and cell boundaries.
        for(int q=0;q<N_Q;q++) send(q%N_RX,9,q,3+q);
        if(N_RX>1) begin
            fork
                send(0,MAX_PACKET_BYTES,0,31);
                send(1,1,0,32);
            join
        end
        send(0,1,0,20);send(0,7,0,21);send(0,8,0,22);
        fork
            send(0,CELL_BYTES-1,0,23);
            begin
                for(int i=0;i<3;i++) begin
                    tm_bus_sequence resource_read=new;resource_read.read_only=1;resource_read.address=32'h24+32'(4*i);resource_read.start(e.axil.sequencer);
                end
            end
        join
        send(0,CELL_BYTES,0,24);send(0,CELL_BYTES+1,0,25);
        send(0,MAX_PACKET_BYTES,0,26);
        send(0,9,255,27);send(0,9,0,28,1);
        repeat(1000) @(negedge e.observe.clk);
        e.coordinator.drained();
        // Reset with committed/partially captured traffic and a stalled sink.
        fork
            begin
                tm_bus_sequence aborted_bus=new;aborted_bus.expect_reset=1;aborted_bus.response_stall=MAX_PACKET_BYTES*2+50;
                aborted_bus.start(e.axil.sequencer);
            end
            begin
                wait(e.axil.vif.rsp.bvalid);
                send(0,MAX_PACKET_BYTES,0,29);
                @(negedge e.observe.clk);e.observe.rst_n=0;
                repeat(4) @(negedge e.observe.clk);
                e.observe.rst_n=1;e.registers.reset();
            end
        join
        // Deliberate empty new epoch separates stale data from fresh captures.
        repeat(16) @(negedge e.observe.clk);
        send(0,9,0,42);
        repeat(1000) @(negedge e.observe.clk);
        e.coordinator.drained();
    endtask
endclass

class tm_foundation_test extends uvm_test;
    `uvm_component_utils(tm_foundation_test)
    tm_environment env;
    tm_virtual_sequencer sequencer;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
        env=tm_environment::type_id::create("env",this);sequencer=new("sequencer",this);sequencer.env=env;
    endfunction
    task run_phase(uvm_phase phase);
        tm_sink_sequence sink_seq=new;
        tm_foundation_sequence seq=new;
        phase.raise_objection(this);
        env.observe.rst_n=0;
        repeat(4) @(negedge env.observe.clk);
        env.observe.rst_n=1;
        fork sink_seq.start(env.tx.sequencer); join_none
        seq.start(sequencer);
        sink_seq.kill();
        `uvm_info("FOUNDATION",$sformatf("TM_FOUNDATION_PASS captures=%0d services=%0d commits=%0d delivered=%0d dispatches=%0d batches=%0d",env.coverage_collector.captures,env.coordinator.service_model.services,env.coordinator.service_model.commits,env.coordinator.bytes_model.delivered,env.coordinator.schedule_model.dispatches,env.coordinator.batches),UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass
