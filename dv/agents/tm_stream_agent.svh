// Raw beats intentionally preserve malformed framing and non-SOP metadata.
class tm_stream_item extends uvm_sequence_item;
    `uvm_object_utils(tm_stream_item)
    beat_t beats[$];
    int gaps[$];
    int ready_cycles=1, stall_cycles=0;
    function new(string name="tm_stream_item"); super.new(name); endfunction
endclass

// Every monitor publishes an explicit idle sample as well as transfers.
class tm_sample extends uvm_sequence_item;
    `uvm_object_utils(tm_sample)
    int source;
    monitor_batch_t batch;
    live_t live;
    function new(string name="sample"); super.new(name); endfunction
endclass

class tm_stamp;
    int unsigned epoch=0;
    longint unsigned cycle=0;
    bit in_reset=0;
    function void apply(tm_sample s, bit reset_asserted);
        if(reset_asserted && !in_reset) begin epoch++; cycle=0; end
        s.batch.epoch=epoch; s.batch.cycle=cycle++;
        s.batch.reset_asserted=reset_asserted;
        in_reset=reset_asserted;
    endfunction
endclass

class tm_stream_driver extends uvm_driver #(tm_stream_item);
    `uvm_component_utils(tm_stream_driver)
    virtual tm_stream_if vif;
    bit sink;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    task run_phase(uvm_phase phase);
        tm_stream_item x;
        if(sink) vif.ready=0; else begin vif.valid=0; vif.beat='0; end
        forever begin
            seq_item_port.get_next_item(x);
            if(sink) begin
                repeat(x.stall_cycles) begin @(negedge vif.clk); vif.ready=0; end
                repeat(x.ready_cycles) begin @(negedge vif.clk); vif.ready=vif.rst_n; end
            end else begin
                foreach(x.beats[i]) begin
                    repeat(i<x.gaps.size()?x.gaps[i]:0) begin @(negedge vif.clk); vif.valid=0; end
                    while(!vif.rst_n) @(negedge vif.clk);
                    @(negedge vif.clk); vif.valid=1; vif.beat=x.beats[i];
                    do @(posedge vif.clk); while(vif.rst_n && !vif.ready);
                    @(negedge vif.clk); vif.valid=0;
                    if(!vif.rst_n) break; // reset cancels the current item
                end
            end
            seq_item_port.item_done();
        end
    endtask
endclass

class tm_stream_monitor extends uvm_monitor;
    `uvm_component_utils(tm_stream_monitor)
    virtual tm_stream_if vif;
    uvm_analysis_port #(tm_sample) observed;
    int source;
    tm_stamp stamp;
    function new(string name, uvm_component parent);
        super.new(name,parent); observed=new("observed",this); stamp=new;
    endfunction
    task run_phase(uvm_phase phase);
        tm_sample s;
        forever begin
            @(posedge vif.clk);
            s=new; s.source=source; stamp.apply(s,!vif.rst_n);
            if(source<N_RX) s.batch.captures[source*(BEAT_W+2)+:BEAT_W+2]={vif.valid,vif.ready,vif.beat};
            else s.batch.output_sample='{vif.valid,vif.ready,vif.beat};
            observed.write(s);
        end
    endtask
endclass

class tm_stream_agent extends uvm_agent;
    `uvm_component_utils(tm_stream_agent)
    virtual tm_stream_if vif;
    bit sink;
    int source;
    tm_stream_driver driver;
    tm_stream_monitor monitor;
    uvm_sequencer #(tm_stream_item) sequencer;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual tm_stream_if)::get(this,"","vif",vif)) `uvm_fatal("CONFIG","stream vif missing")
        monitor=tm_stream_monitor::type_id::create("monitor",this);
        monitor.vif=vif; monitor.source=source;
        if(is_active==UVM_ACTIVE) begin
            driver=tm_stream_driver::type_id::create("driver",this);
            driver.vif=vif; driver.sink=sink;
            sequencer=new("sequencer",this);
        end
    endfunction
    function void connect_phase(uvm_phase phase);
        if(is_active==UVM_ACTIVE) driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass
