// Focused UVM analysis-imp/barrier capability probe, separate from bus stimulus.
class tm_batch_test extends uvm_test;
    `uvm_component_utils(tm_batch_test)
    tm_coordinator coordinator;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
        coordinator=tm_coordinator::type_id::create("coordinator",this);
    endfunction
    function void submit(int source,int cycle);
        tm_sample s=new;
        s.source=source;s.batch.epoch=1;s.batch.cycle=64'(cycle);
        s.live.unreserved=CELL_COUNT_W'(N_CELL);s.live.physical_free=CELL_COUNT_W'(N_CELL);s.live.free_desc=DESC_COUNT_W'(N_DESC);
        coordinator.write(s);
    endfunction
    task run_phase(uvm_phase phase);
        int order[$];
        phase.raise_objection(this);
        for(int source=0;source<N_RX+5;source++) order.push_back(source);
        for(int cycle=0;cycle<128;cycle++) begin
            order.shuffle();
            foreach(order[i]) submit(order[i],cycle);
        end
        if(coordinator.batches!=128) `uvm_fatal("BATCH_COUNT","idle callbacks did not seal exactly once")
        if($test$plusargs("MUT_BATCH_DUPLICATE")) begin submit(0,128);submit(0,128);end
        if($test$plusargs("MUT_BATCH_MISSING")) begin submit(0,128);submit(1,129);end
        if($test$plusargs("MUT_BATCH_STALE")) submit(0,127);
        coordinator.drained();
        `uvm_info("BATCH","TM_BATCH_PASS batches=128",UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass

// Directed model capability: reserve/materialize + TX return + zero-cell abort
// completion, including both descriptor returns in the same architectural batch.
class tm_atomic_test extends uvm_test;
    `uvm_component_utils(tm_atomic_test)
    tm_service_checker model;
    int cycle;
    function new(string name,uvm_component parent);super.new(name,parent);cycle=0;endfunction
    function void build_phase(uvm_phase phase);
        model=tm_service_checker::type_id::create("model",this);
        if($test$plusargs("MUT_ATOMIC_LIMIT")) model.limits[0]=2;
    endfunction
    function beat_t word(bit bad=0);
        beat_t beat='0;
        beat.data=64'h55;beat.keep=bad?0:1;beat.last=1;beat.user={24'b0,16'd7,16'd1,8'd0};return beat;
    endfunction
    function descriptor_t info(int source);
        descriptor_t v='0;v.ncell=1;v.length=1;v.tag=7;v.source=RX_ID_W'(source);return v;
    endfunction
    function void step(monitor_batch_t b,int owned,int assigned,int reserved,int descriptors);
        live_t live='0;
        b.epoch=1;b.cycle=64'(cycle++);
        live.unreserved=CELL_COUNT_W'(N_CELL-owned);live.reserved_free=CELL_COUNT_W'(reserved);
        live.assigned=CELL_COUNT_W'(assigned);live.physical_free=CELL_COUNT_W'(N_CELL-assigned);
        live.free_desc=DESC_COUNT_W'(N_DESC-descriptors);live.owned[0+:CELL_COUNT_W]=CELL_COUNT_W'(owned);
        model.apply(b,live);
    endfunction
    function monitor_batch_t capture(int port,bit bad=0);
        monitor_batch_t b='0;b.captures[port*(BEAT_W+2)+:BEAT_W+2]={1'b1,1'b1,word(bad)};return b;
    endfunction
    function monitor_batch_t service(int port,int desc,int cell_id,bit bad=0);
        monitor_batch_t b='0;
        b.policy.rx_service='{1,RX_ID_W'(port),word(bad),1};
        b.policy.admit='{1,RX_ID_W'(port),8'd0,16'd7,16'd1,CELL_COUNT_W'(1),1,COMMITTED,DESC_ID_W'(desc)};
        if(bad) b.policy.abort_mark='{1,RX_ID_W'(port),DESC_ID_W'(desc),Q_ID_W'(0),CELL_ID_W'(0),CELL_COUNT_W'(0),CELL_COUNT_W'(1)};
        else begin
            b.policy.cell_alloc='{1,CELL_ID_W'(cell_id),DESC_ID_W'(desc)};
            b.policy.commit='{1,DESC_ID_W'(desc),Q_ID_W'(0),info(port)};b.policy.commit.info.head=CELL_ID_W'(cell_id);
        end
        return b;
    endfunction
    task run_phase(uvm_phase phase);
        monitor_batch_t b;
        if(N_RX<2) `uvm_fatal("ATOMIC_PROFILE","two distinct status ports required")
        phase.raise_objection(this);
        b='0;b.reset_asserted=1;step(b,0,0,0,0);
        step(capture(0),0,0,0,0);
        step(service(0,0,0),0,0,0,0);
        b=capture(1,1);b.statuses[0+:STATUS_W]={1'b1,4'(COMMITTED),16'd7,8'd0,16'd1};step(b,1,1,0,1);
        step(service(1,1,0,1),1,1,0,1);
        step(capture(0),2,1,1,2);
        b=service(0,2,1);
        b.output_sample='{1,1,word()};
        b.policy.cell_free='{1,CELL_ID_W'(0),0,Q_ID_W'(0),DESC_ID_W'(0)};
        b.policy.tx_done='{1,DESC_ID_W'(0),Q_ID_W'(0),16'd1};
        b.policy.abort_done='{1,RX_ID_W'(1),DESC_ID_W'(1),Q_ID_W'(0),CELL_COUNT_W'(1)};
        step(b,2,1,1,2);
        if(model.unreserved_cells!=N_CELL-1 || model.reserved_cells!=0 || model.assigned_cells!=1 || model.free_descriptors!=N_DESC-1 || model.queue_owned_cells[0]!=1) `uvm_fatal("ATOMIC_DELTA","simultaneous deltas were overwritten")
        b='0;b.statuses[0+:STATUS_W]={1'b1,4'(COMMITTED),16'd7,8'd0,16'd1};b.statuses[(N_RX>1?STATUS_W:0)+:STATUS_W]={1'b1,4'(FRAME_ERROR),16'd7,8'd0,16'd1};step(b,1,1,0,1);
        b='0;b.output_sample='{1,1,word()};b.policy.cell_free='{1,CELL_ID_W'(1),0,Q_ID_W'(0),DESC_ID_W'(2)};b.policy.tx_done='{1,DESC_ID_W'(2),Q_ID_W'(0),16'd1};step(b,1,1,0,1);
        b='0;step(b,0,0,0,0);model.drained();
        `uvm_info("ATOMIC","TM_ATOMIC_PASS simultaneous_descriptor_returns=2",UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass
