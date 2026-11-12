class tm_observation_monitor extends uvm_monitor;
    `uvm_component_utils(tm_observation_monitor)
    virtual tm_observe_if vif;
    int source;
    uvm_analysis_port #(tm_sample) observed;
    tm_stamp stamp;
    function new(string name,uvm_component parent);
        super.new(name,parent); observed=new("observed",this);stamp=new;
    endfunction
    task run_phase(uvm_phase phase);
        tm_sample s;
        forever begin
            @(posedge vif.clk);s=new;s.source=source;stamp.apply(s,!vif.rst_n);
            case(source)
                N_RX+2:s.batch.statuses=vif.statuses;
                N_RX+3:begin s.batch.policy=vif.trace_events;s.live=vif.live;end
                N_RX+4:;
                default:`uvm_fatal("MONITOR_SOURCE","unknown observation source")
            endcase
            observed.write(s);
        end
    endtask
endclass

class tm_foundation_coverage extends uvm_subscriber #(tm_sample);
    `uvm_component_utils(tm_foundation_coverage)
    int captures,outputs,aw_cycle,w_cycle;
    covergroup traffic with function sample(int port,int qid,int keep_width,bit stall);
        option.per_instance=1;
        source:coverpoint port { bins ports[]={[0:N_RX-1]}; }
        queue_id:coverpoint qid { bins valid_q[]={[0:N_Q-1]}; bins invalid_q={255}; }
        keep:coverpoint keep_width { bins widths[]={[0:8]}; }
        backpressure:coverpoint stall;
        source_queue:cross source,queue_id;
    endgroup
    covergroup bus with function sample(int order,bit stalled);
        option.per_instance=1;
        arrival_order:coverpoint order { bins w_first={0};bins simultaneous={1};bins aw_first={2}; }
        response_stall:coverpoint stalled;
        order_stall:cross arrival_order,response_stall;
    endgroup
    bit b_stalled;
    function new(string name,uvm_component parent);super.new(name,parent);captures=0;outputs=0;traffic=new;bus=new;aw_cycle=-1;w_cycle=-1;endfunction
    function void write(tm_sample x);
        stream_sample_t s;
        monitor_batch_t b=x.batch;
        if(b.reset_asserted) begin aw_cycle=-1;w_cycle=-1;b_stalled=0;return;end
        for(int p=0;p<N_RX;p++) begin
            s=stream_sample_t'(b.captures[p*(BEAT_W+2)+:BEAT_W+2]);
            if(s.valid) traffic.sample(p,int'(s.beat.user[7:0]),$countones(s.beat.keep),!s.ready);
            if(s.valid && s.ready) captures++;
        end
        if(b.output_sample.valid && b.output_sample.ready) outputs++;
        if(b.bus_req.awvalid && b.bus_rsp.awready) aw_cycle=int'(b.cycle);
        if(b.bus_req.wvalid && b.bus_rsp.wready) w_cycle=int'(b.cycle);
        if(b.bus_rsp.bvalid && !b.bus_req.bready) b_stalled=1;
        if(b.bus_rsp.bvalid && b.bus_req.bready) begin
            bus.sample(aw_cycle==w_cycle?1:(aw_cycle<w_cycle?2:0),b_stalled);
            aw_cycle=-1;w_cycle=-1;b_stalled=0;
        end
    endfunction
endclass

class tm_coordinator extends uvm_component;
    `uvm_component_utils(tm_coordinator)
    uvm_analysis_imp #(tm_sample,tm_coordinator) input_samples;
    uvm_analysis_port #(tm_sample) sealed_batches;
    tm_byte_checker bytes_model;
    tm_service_checker service_model;
    tm_schedule_checker schedule_model;
    monitor_batch_t pending;
    live_t live;
    bit [N_RX+4:0] seen;
    int batches,trace_file;
    int unsigned last_epoch;
    longint unsigned last_cycle;
    bit have_last;
    function new(string name,uvm_component parent);
        super.new(name,parent);batches=0;last_epoch=0;last_cycle=0;input_samples=new("input_samples",this);sealed_batches=new("sealed_batches",this);
    endfunction
    function void build_phase(uvm_phase phase);
        bytes_model=tm_byte_checker::type_id::create("bytes_model",this);
        service_model=tm_service_checker::type_id::create("service_model",this);
        schedule_model=tm_schedule_checker::type_id::create("schedule_model",this);
        if($test$plusargs("SMALL_QUANTUM")) schedule_model.quantum=64;
        trace_file=$fopen("transactions.jsonl","w");
    endfunction
    function void write(tm_sample x);
        tm_sample sealed;
        if(x.source<0 || x.source>N_RX+4) `uvm_fatal("BATCH_SOURCE","unknown source")
        if(seen=='0) begin
            if(have_last && (x.batch.epoch<last_epoch || (x.batch.epoch==last_epoch && x.batch.cycle<=last_cycle))) `uvm_fatal("BATCH_STALE","stale cycle")
            pending='0;pending.epoch=x.batch.epoch;pending.cycle=x.batch.cycle;pending.reset_asserted=x.batch.reset_asserted;
        end
        if(x.batch.epoch!=pending.epoch || x.batch.cycle!=pending.cycle || x.batch.reset_asserted!=pending.reset_asserted) `uvm_fatal("BATCH_MISSING","mixed/incomplete batch")
        if(seen[x.source]) `uvm_fatal("BATCH_DUPLICATE","duplicate monitor callback")
        seen[x.source]=1;
        if(x.source<N_RX) pending.captures[x.source*(BEAT_W+2)+:BEAT_W+2]=x.batch.captures[x.source*(BEAT_W+2)+:BEAT_W+2];
        else case(x.source)
            N_RX:pending.output_sample=x.batch.output_sample;
            N_RX+1:begin pending.bus_req=x.batch.bus_req;pending.bus_rsp=x.batch.bus_rsp;end
            N_RX+2:pending.statuses=x.batch.statuses;
            N_RX+3:begin pending.policy=x.batch.policy;live=x.live;end
            N_RX+4:;
        endcase
        if(&seen) begin
            // No callback mutates any model before this barrier.
            bytes_model.apply(pending);
            service_model.apply(pending,live);
            schedule_model.apply(pending,service_model.committed_frame);
            sealed=new;sealed.batch=pending;sealed_batches.write(sealed);
            $fdisplay(trace_file,"{\"epoch\":%0d,\"cycle\":%0d,\"reset\":%0d,\"service\":%0d,\"admit\":%0d,\"commit\":%0d,\"dispatch\":%0d,\"output\":%0d,\"status\":\"%h\",\"U\":%0d}",pending.epoch,pending.cycle,pending.reset_asserted,pending.policy.rx_service.valid,pending.policy.admit.valid,pending.policy.commit.valid,pending.policy.dispatch.valid,pending.output_sample.valid&&pending.output_sample.ready,pending.statuses,service_model.unreserved_cells);
            $fflush(trace_file);
            batches++;seen='0;last_epoch=pending.epoch;last_cycle=pending.cycle;have_last=1;
        end
    endfunction
    function void drained();
        if(seen!='0) `uvm_fatal("BATCH_MISSING","incomplete final cycle")
        bytes_model.drained();service_model.drained();schedule_model.drained();
    endfunction
    function void final_phase(uvm_phase phase);$fclose(trace_file);endfunction
endclass

class tm_environment extends uvm_env;
    `uvm_component_utils(tm_environment)
    tm_stream_agent rx[N_RX],tx;
    tm_axil_agent axil;
    tm_observation_monitor observations[3];
    tm_coordinator coordinator;
    tm_foundation_coverage coverage_collector;
    tm_fixture_register_block registers;
    tm_register_block production_registers;
    tm_axil_adapter adapter;
    uvm_reg_predictor #(tm_axil_item) predictor;
    virtual tm_observe_if observe;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual tm_observe_if)::get(this,"","observe",observe)) `uvm_fatal("CONFIG","observation vif missing")
        foreach(rx[p]) begin rx[p]=tm_stream_agent::type_id::create($sformatf("rx%0d",p),this);rx[p].source=p;end
        tx=tm_stream_agent::type_id::create("tx",this);tx.sink=1;tx.source=N_RX;
        axil=tm_axil_agent::type_id::create("axil",this);
        foreach(observations[i]) begin
            observations[i]=tm_observation_monitor::type_id::create($sformatf("observation%0d",i),this);
            observations[i].vif=observe;observations[i].source=N_RX+2+i;
        end
        coordinator=tm_coordinator::type_id::create("coordinator",this);
        coverage_collector=tm_foundation_coverage::type_id::create("coverage_collector",this);
        registers=tm_fixture_register_block::type_id::create("registers");registers.build();registers.reset();
        production_registers=tm_register_block::type_id::create("production_registers");production_registers.build();
        if(production_registers.words["ID"].get_reset()!=64'h544d0100 || production_registers.words.num()!=34+16*N_Q) `uvm_fatal("RAL_MAP","production map shape/reset mismatch")
        adapter=tm_axil_adapter::type_id::create("adapter");predictor=new("predictor",this);
    endfunction
    function void connect_phase(uvm_phase phase);
        foreach(rx[p]) rx[p].monitor.observed.connect(coordinator.input_samples);
        tx.monitor.observed.connect(coordinator.input_samples);
        axil.monitor.samples.connect(coordinator.input_samples);
        foreach(observations[i]) observations[i].observed.connect(coordinator.input_samples);
        coordinator.sealed_batches.connect(coverage_collector.analysis_export);
        registers.default_map.set_sequencer(axil.sequencer,adapter);
        registers.default_map.set_auto_predict(0);predictor.map=registers.default_map;predictor.adapter=adapter;
        axil.monitor.transactions.connect(predictor.bus_in);
    endfunction
endclass
