`timescale 1ns/1ps
package memory_tx_wires;
    `include "wires.svh"
endpackage

interface memory_tx_replay_if(input logic clk);
    import memory_tx_wires::*;
    logic capture, rst_n;
    memory_actions_t actions;
endinterface

package memory_tx_replay_pkg;
    import uvm_pkg::*;
    import tm_bench_types::*;
    import tm_bench_pkg::*;
    import memory_tx_wires::*;
    `include "uvm_macros.svh"

    class memory_action_sample extends tm_sample;
        memory_actions_t actions;
        function new(string name="action_sample");super.new(name);endfunction
    endclass

    class memory_action_monitor extends uvm_monitor;
        `uvm_component_utils(memory_action_monitor)
        virtual memory_tx_replay_if vif;
        uvm_analysis_port #(tm_sample) observed;
        tm_stamp stamp;
        bit injected;
        function new(string name,uvm_component parent);
            super.new(name,parent);observed=new("observed",this);stamp=new;
        endfunction
        task run_phase(uvm_phase phase);
            memory_action_sample sample;
            forever begin
                @(posedge vif.clk);
                sample=new;sample.source=N_RX+3;sample.actions=vif.actions;
                stamp.apply(sample,!vif.rst_n);
                if(vif.capture && !injected && $test$plusargs("MIXED_SAMPLE"))sample.batch.cycle++;
                observed.write(sample);
                if(vif.capture && !injected && $test$plusargs("DUPLICATE_SAMPLE"))observed.write(sample);
                if(vif.capture)injected=1;
            end
        endtask
    endclass

    class memory_replay_collector extends uvm_component;
        `uvm_component_utils(memory_replay_collector)
        uvm_analysis_imp #(tm_sample,memory_replay_collector) samples;
        virtual memory_tx_replay_if vif;
        bit [1:0] seen;
        int epoch,cycle,reset,edges,reads,responses,outputs,returns,completions,stalls;
        int live_reads,buffered;
        int due_cycles[$];
        logic [63:0] due_data[$];
        logic [63:0] memory_image[int];
        int file;
        monitor_batch_t pending;
        memory_actions_t actions;
        bit have_last;
        int last_epoch;
        longint unsigned last_cycle;
        covergroup observed_traffic with function sample(bit read_v,bit response_v,bit transfer,bit held,bit release_cell,bit complete);
            option.per_instance=1;
            issue:coverpoint read_v;
            response:coverpoint response_v;
            output_transfer:coverpoint transfer;
            output_hold:coverpoint held;
            cell_return:coverpoint release_cell;
            descriptor_done:coverpoint complete;
            overlap:cross response,output_transfer,issue;
        endgroup
        function new(string name,uvm_component parent);
            super.new(name,parent);samples=new("samples",this);observed_traffic=new;
        endfunction
        function void build_phase(uvm_phase phase);file=$fopen("observed.jsonl","w");endfunction
        function void write(tm_sample sample);
            memory_action_sample action_sample;
            int lane;
            bit transfer;
            if(!vif.capture)return;
            lane=(sample.source==N_RX)?0:1;
            if(sample.source!=N_RX && sample.source!=N_RX+3) `uvm_fatal("MEMORY_SAMPLE_SOURCE","unknown monitor source")
            if($test$plusargs("OMIT_ACTION") && lane==1)return;
            if($test$plusargs("OMIT_FINAL_ACTION") && lane==1 && vif.actions.done_v!=0)return;
            if(seen=='0)begin
                pending='0;pending.epoch=sample.batch.epoch;pending.cycle=sample.batch.cycle;
                pending.reset_asserted=sample.batch.reset_asserted;
                if(have_last && (sample.batch.epoch<last_epoch || (sample.batch.epoch==last_epoch && sample.batch.cycle<=last_cycle)))
                    `uvm_fatal("MEMORY_SAMPLE_STALE","stale sample")
            end
            if(sample.batch.epoch!=pending.epoch || sample.batch.cycle!=pending.cycle || sample.batch.reset_asserted!=pending.reset_asserted)
                `uvm_fatal("MEMORY_SAMPLE_MIXED","incomplete or mixed-cycle sample")
            if(seen[lane]) `uvm_fatal("MEMORY_SAMPLE_DUPLICATE","duplicate sample")
            seen[lane]=1;
            if(lane==0)pending.output_sample=sample.batch.output_sample;
            else begin
                if(!$cast(action_sample,sample)) `uvm_fatal("MEMORY_SAMPLE_TYPE","missing action record")
                actions=action_sample.actions;
            end
            if(&seen)begin
                $fdisplay(file,"{\"epoch\":%0d,\"cycle\":%0d,\"reset\":%0d,\"actions\":\"%h\",\"valid\":%0d,\"ready\":%0d,\"data\":\"%h\",\"keep\":\"%h\",\"last\":%0d,\"user\":\"%h\"}",pending.epoch,edges,pending.reset_asserted,actions,pending.output_sample.valid,pending.output_sample.ready,pending.output_sample.beat.data,pending.output_sample.beat.keep,pending.output_sample.beat.last,pending.output_sample.beat.user);
                $fflush(file);                if((actions.response_v!=0)!=(due_cycles.size()>0 && due_cycles[0]==edges))
                    `uvm_fatal("MEMORY_RESPONSE_PRESENCE","fixed-latency response missing or extra")
                if(actions.response_v!=0)begin
                    if(actions.response_data!=due_data[0]) `uvm_fatal("MEMORY_RESPONSE_DATA","response differs from sampled write image")
                    void'(due_cycles.pop_front());void'(due_data.pop_front());
                end
                if(actions.read_v!=0)begin
                    if(!memory_image.exists(int'(actions.read_addr))) `uvm_fatal("MEMORY_READ_UNWRITTEN","read before sampled write")
                    due_cycles.push_back(edges+MEM_RD_LATENCY);due_data.push_back(memory_image[int'(actions.read_addr)]);
                end
                if(actions.write_v!=0)begin
                    if(actions.read_v!=0 && actions.read_addr==actions.write_addr) `uvm_fatal("MEMORY_COLLISION","same-word read/write")
                    memory_image[int'(actions.write_addr)]=actions.write_data;
                end
                transfer=pending.output_sample.valid && pending.output_sample.ready;
                if(pending.reset_asserted)begin live_reads=0;buffered=0;end
                else begin
                    if(actions.read_v!=0)begin live_reads++;reads++;end
                    // Old physical responses during reset are sampled but give no live credit.
                    if(actions.response_v!=0 && live_reads>0)begin live_reads--;buffered++;responses++;end
                    if(transfer)begin buffered--;outputs++;end
                    if(buffered<0 || live_reads<0 || buffered+live_reads>TX_FIFO_DEPTH)
                        `uvm_fatal("MEMORY_CREDIT","sampled credit equation")
                    if(actions.free_v!=0)returns++;
                    if(actions.done_v!=0)completions++;
                    if(pending.output_sample.valid && !pending.output_sample.ready)stalls++;
                    observed_traffic.sample(actions.read_v!=0,actions.response_v!=0,transfer,
                        pending.output_sample.valid&&!pending.output_sample.ready,actions.free_v!=0,actions.done_v!=0);
                end
edges++;seen='0;have_last=1;last_epoch=pending.epoch;last_cycle=pending.cycle;
            end
        endfunction
        function void drained();
            if(seen!='0) `uvm_fatal("MEMORY_SAMPLE_MISSING","incomplete final sample")
            if(live_reads!=0 || buffered!=0) `uvm_fatal("MEMORY_SHUTDOWN","nonempty transactions")
            if(reads==0 || responses==0 || outputs==0 || returns==0 || completions==0 || stalls==0)
                `uvm_fatal("MEMORY_REQUIRED_TRIGGER","absent required trigger")
            $display("TM_MEMORY_TX_BENCH_PASS edges=%0d reads=%0d responses=%0d outputs=%0d returns=%0d done=%0d holds=%0d",edges,reads,responses,outputs,returns,completions,stalls);
        endfunction
        function void final_phase(uvm_phase phase);$fclose(file);endfunction
    endclass

    class memory_replay_item extends uvm_sequence_item;
        `uvm_object_utils(memory_replay_item)
        bit reset;
        memory_actions_t actions;
        bit valid,ready;
        beat_t beat;
        function new(string name="memory_replay_item");super.new(name);endfunction
    endclass

    class memory_replay_sequence extends uvm_sequence #(memory_replay_item);
        `uvm_object_utils(memory_replay_sequence)
        function new(string name="memory_replay_sequence");super.new(name);endfunction
        task body();
            string path;
            int input_file,got,reset_value,valid_value,ready_value,last_value,rows;
            memory_actions_t values;
            logic [63:0] data,user;
            logic [7:0] keep;
            memory_replay_item item;
            if(!$value$plusargs("REPLAY=%s",path)) `uvm_fatal("REPLAY_INPUT","missing replay")
            input_file=$fopen(path,"r");
            if(input_file==0) `uvm_fatal("REPLAY_INPUT","cannot open replay")
            while(!$feof(input_file))begin
                got=$fscanf(input_file,"%d %h %d %d %h %h %d %h\n",reset_value,values,valid_value,ready_value,data,keep,last_value,user);
                if(got!=8) `uvm_fatal("REPLAY_INPUT","malformed or empty row")
                item=new;start_item(item);
                item.reset=reset_value!=0;item.actions=values;
                item.valid=valid_value!=0;item.ready=ready_value!=0;
                item.beat='{data:data,keep:keep,last:last_value!=0,user:user};
                finish_item(item);rows++;
            end
            if(rows==0) `uvm_fatal("REPLAY_INPUT","empty replay")
            $fclose(input_file);
        endtask
    endclass

    class memory_replay_driver extends uvm_driver #(memory_replay_item);
        `uvm_component_utils(memory_replay_driver)
        virtual memory_tx_replay_if vif;
        virtual tm_stream_if stream;
        function new(string name,uvm_component parent);super.new(name,parent);endfunction
        task run_phase(uvm_phase phase);
            memory_replay_item item;
            forever begin
                seq_item_port.get_next_item(item);
                @(negedge vif.clk);vif.capture=1;vif.rst_n=!item.reset;vif.actions=item.actions;
                stream.valid=item.valid;stream.ready=item.ready;stream.beat=item.beat;
                @(posedge vif.clk);seq_item_port.item_done();
            end
        endtask
    endclass

    class memory_tx_replay_test extends uvm_test;
        `uvm_component_utils(memory_tx_replay_test)
        virtual memory_tx_replay_if vif;
        virtual tm_stream_if stream;
        tm_stream_agent output_agent;
        memory_action_monitor action_monitor;
        memory_replay_collector collector;
        memory_replay_driver driver;
        uvm_sequencer #(memory_replay_item) sequencer;
        function new(string name,uvm_component parent);super.new(name,parent);endfunction
        function void build_phase(uvm_phase phase);
            if(!uvm_config_db#(virtual memory_tx_replay_if)::get(this,"","vif",vif)) `uvm_fatal("CONFIG","replay vif missing")
            if(!uvm_config_db#(virtual tm_stream_if)::get(this,"","stream",stream)) `uvm_fatal("CONFIG","stream vif missing")
            uvm_config_db#(virtual tm_stream_if)::set(this,"output_agent","vif",stream);
            output_agent=tm_stream_agent::type_id::create("output_agent",this);
            output_agent.is_active=UVM_PASSIVE;output_agent.source=N_RX;
            action_monitor=memory_action_monitor::type_id::create("action_monitor",this);action_monitor.vif=vif;
            collector=memory_replay_collector::type_id::create("collector",this);collector.vif=vif;
            driver=memory_replay_driver::type_id::create("driver",this);driver.vif=vif;driver.stream=stream;
            sequencer=new("sequencer",this);
        endfunction
        function void connect_phase(uvm_phase phase);
            output_agent.monitor.observed.connect(collector.samples);
            action_monitor.observed.connect(collector.samples);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
        task run_phase(uvm_phase phase);
            memory_replay_sequence stimulus;
            phase.raise_objection(this);stimulus=new;
            stimulus.start(sequencer);
            @(negedge vif.clk);vif.capture=0;
            collector.drained();phase.drop_objection(this);
        endtask
    endclass
endpackage

module memory_tx_replay_top;
    import uvm_pkg::*;
    import tm_bench_pkg::*;
    import memory_tx_replay_pkg::*;
    logic clk=0;
    always #5 clk=~clk;
    memory_tx_replay_if replay(clk);
    tm_stream_if stream(clk,replay.rst_n);
    memory_tx_obligations #(.LATENCY(tm_bench_types::MEM_RD_LATENCY),
        .DEPTH(tm_bench_types::TX_FIFO_DEPTH),.CELL_BYTES(tm_bench_types::CELL_BYTES)) obligations(
        .clk(clk),.sample_enable(replay.capture),.rst_n(replay.rst_n),
        .dispatch_valid(replay.actions.dispatch_v!=0),.dispatch_length(replay.actions.dispatch_info_length),
        .read_valid(replay.actions.read_v!=0),.response_valid(replay.actions.response_v!=0),
        .output_valid(stream.valid),.output_ready(stream.ready),.output_last(stream.beat.last),
        .output_keep(stream.beat.keep),.cell_return_valid(replay.actions.free_v!=0),.done_valid(replay.actions.done_v!=0));
    tm_report_server reports;
    initial begin
        replay.capture=0;replay.rst_n=1;replay.actions='0;
        stream.valid=0;stream.ready=0;stream.beat='0;
        reports=new;uvm_report_server::set_server(reports);
        uvm_config_db#(virtual memory_tx_replay_if)::set(null,"uvm_test_top","vif",replay);
        uvm_config_db#(virtual tm_stream_if)::set(null,"uvm_test_top","stream",stream);
        run_test("memory_tx_replay_test");
    end
    initial if($test$plusargs("TRACE"))begin $dumpfile("wave.vcd");$dumpvars(0,memory_tx_replay_top);end
endmodule
