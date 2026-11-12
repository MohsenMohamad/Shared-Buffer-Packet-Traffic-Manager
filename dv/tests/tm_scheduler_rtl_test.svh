class tm_scheduler_rtl_test extends uvm_test;
    `uvm_component_utils(tm_scheduler_rtl_test)
    virtual tm_scheduler_if vif;
    tm_schedule_checker model;
    tm_frame transmitting;
    int tx_offset, next_id, cycles, grants, replacements, longer, different;
    int stalls, completions, reactivations, max_credit, waiting, continuing;
        covergroup policy_cg with function sample(int collision, bit busy, bit reactivation, int relation);
        option.per_instance=1;
        update_kind: coverpoint collision { bins none={0}; bins singleton={1}; bins longer={2}; bins different={3}; }
        tx_busy: coverpoint busy;
        activated: coverpoint reactivation;
        fit: coverpoint relation { bins insufficient={0}; bins equal={1}; bins surplus={2}; }
        replacement_busy: cross update_kind, tx_busy;
    endgroup
    function new(string name, uvm_component parent);
        super.new(name,parent);
        policy_cg=new;
    endfunction
    function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual tm_scheduler_if)::get(this,"","vif",vif))
            `uvm_fatal("SCHEDULER_VIF","missing interface")
        model=tm_schedule_checker::type_id::create("model",this);
        model.mode=SCHED_MODE;
    endfunction
    function tm_frame packet(int q, int length);
        tm_packet p=new;
        tm_frame f=new;
        bit occupied;
        int candidate;
        candidate=next_id;
        for(int attempt=0;attempt<N_DESC;attempt++) begin
            occupied=model.active!=null && model.active.desc==candidate;
            foreach(model.queues[q]) foreach(model.queues[q].frames[k])
                if(model.queues[q].frames[k].desc==candidate) occupied=1;
            if(!occupied) break;
            candidate=(candidate+1)%N_DESC;
        end
        if(occupied) `uvm_fatal("SCHEDULER_STIMULUS","no unowned descriptor for publication")
        // Existing packet object defines consistent legal lengths/framing.
        p.qid=32'(q); p.length=32'(length); p.source=0;
        p.beat_count=32'((length+7)/8); p.cell_count=32'((length+CELL_BYTES-1)/CELL_BYTES);
        p.final_keep=8'((1<<(((length-1)%8)+1))-1);
        f.qid=q; f.length=int'(p.length); f.source=int'(p.source); f.desc=candidate;
        next_id=(candidate+1)%N_DESC;
        f.descriptor='0; f.descriptor.qid=Q_ID_W'(q);
        f.descriptor.length=16'(length); f.descriptor.ncell=CELL_COUNT_W'(p.cell_count);
        return f;
    endfunction
    task reset_case(int q0, int q1);
        @(negedge vif.clk);
        vif.rst_n=0; vif.commit='0; vif.tx_done='0; vif.cfg='0;
        vif.tx_ready=1; transmitting=null; tx_offset=0; next_id=0;
        model.flush(); model.quanta[0]=q0;
        for(int q=1;q<N_Q;q++) model.quanta[q]=q1;
        repeat(2) @(posedge vif.clk);
        @(negedge vif.clk);
        vif.rst_n=1;
        for(int q=0;q<N_Q;q++) vif.cfg.quantum[q*13+:13]=13'(model.quanta[q]);
    endtask
    // Drive queue publications and a packet-granular TX endpoint. The checker
    // gets observed records; it never reads the RTL cursor/visit state.
    task step(int cq=-1, int length=1, bit run=1, bit sink_ready=1, bit ready=1);
        monitor_batch_t b='0;
        tm_frame committed=null;
        int collision, relation, q, credit;
        bit activation;
        @(negedge vif.clk);
        vif.cfg.run=run; vif.tx_ready=ready;
        vif.commit='0; vif.tx_done='0;
        if(cq>=0) begin
            committed=packet(cq,length);
            vif.commit='{1'b1,Q_ID_W'(cq),DESC_ID_W'(committed.desc),committed.descriptor};
        end
        if(transmitting!=null) begin
            b.output_sample.valid=1; b.output_sample.ready=sink_ready;
            b.output_sample.beat.keep=8'((1<<(transmitting.length-tx_offset>=8 ? 8 : transmitting.length-tx_offset))-1);
            b.output_sample.beat.last=transmitting.length-tx_offset<=8;
            b.output_sample.beat.user={16'b0,8'(transmitting.source),16'(transmitting.tag),16'(transmitting.length),8'(transmitting.qid)};
            if(sink_ready) begin
                if((tx_offset+8)%CELL_BYTES==0 || b.output_sample.beat.last)
                    b.policy.cell_free='{1'b1,CELL_ID_W'(0),1'b0,Q_ID_W'(transmitting.qid),DESC_ID_W'(transmitting.desc)};
                if(b.output_sample.beat.last)
                    vif.tx_done='{1'b1,DESC_ID_W'(transmitting.desc),Q_ID_W'(transmitting.qid),16'(transmitting.length)};
            end else stalls++;
        end
        @(posedge vif.clk);
        b.policy.commit=vif.commit; b.policy.dispatch=vif.dispatch; b.policy.tx_done=vif.tx_done;
        q=model.cursor; credit=model.deficit[q]+(model.visit ? 0 : model.quanta[q]);
        relation=model.queues[q].frames.size()==0 ? 0 :
            (model.queues[q].frames[0].length>credit ? 0 : (model.queues[q].frames[0].length==credit ? 1 : 2));
        activation=cq>=0 && model.queues[cq].frames.size()==0;
        if(activation) reactivations++;
        if(vif.dispatch.valid) begin
            grants++;
            if(model.visit) continuing++;
            if(cq==int'(vif.dispatch.qid)) begin
                collision=model.queues[cq].frames.size()==1 ? 1 : 2;
                if(collision==1) replacements++; else longer++;
            end else if(cq>=0) begin collision=3; different++; end
        end
        if(run && model.active==null && !ready && (SCHED_MODE==0 || relation>0)) waiting++;
        policy_cg.sample(collision,model.active!=null,activation,relation);
        model.apply(b,committed,run,ready);
        // The independent model rejects illegal or omitted dispatches before
        // this endpoint consumes any observed grant.
        if(vif.tx_done.valid) begin transmitting=null; completions++; end
        else if(transmitting!=null && sink_ready) tx_offset+=8;
        if(vif.dispatch.valid) begin transmitting=model.active; tx_offset=0; end
        #1;
        if(vif.queue_error) `uvm_fatal("SCHEDULER_QUEUE","production queue rejected action")
        foreach(model.deficit[i]) begin
            if(int'(vif.deficits[i*DEFICIT_W+:DEFICIT_W])!=model.deficit[i])
                `uvm_fatal("SCHEDULE_CREDIT","production credit differs from independent byte model")
            if(model.deficit[i]>max_credit) max_credit=model.deficit[i];
            if(int'(vif.counts[i*DESC_COUNT_W+:DESC_COUNT_W])!=model.queues[i].frames.size())
                `uvm_fatal("SCHEDULER_QUEUE","production count differs from packet list")
            if(model.queues[i].frames.size()>0 && int'(vif.heads[i*DESC_ID_W+:DESC_ID_W])!=model.queues[i].frames[0].desc)
                `uvm_fatal("SCHEDULER_QUEUE","production head differs from packet list")
        end
        cycles++;
    endtask
    function bit eligible();
        int q=model.cursor;
        return model.active==null && model.queues[q].frames.size()>0 &&
            (SCHED_MODE==0 || model.queues[q].frames[0].length<=model.deficit[q]+(model.visit ? 0 : model.quanta[q]));
    endfunction
    task until_eligible();
        int watchdog=0;
        while(!eligible()) begin
            step();
            if(watchdog++>10000) `uvm_fatal("SCHEDULER_PROGRESS","no eligible dispatch")
        end
    endtask
    task finish_tx();
        while(transmitting!=null) step();
    endtask
    task drain();
        int watchdog=0;
        while(transmitting!=null || !empty()) begin
            step();
            if(watchdog++>100000) `uvm_fatal("SCHEDULER_PROGRESS","drain timeout")
        end
        model.drained();
    endtask
    function bit empty();
        foreach(model.queues[q]) if(model.queues[q].frames.size()>0) return 0;
        return 1;
    endfunction
    task saturated(int quantum0, int quantum1);
        reset_case(quantum0,quantum1);
        step(0,64,0); step(1,MAX_PACKET_BYTES,0);
        repeat(160) begin
            until_eligible();
            // Keep both queues backlogged through every dequeue. A finite
            // endpoint may include the entire just-dispatched TX packet.
            step(model.cursor,model.cursor==0 ? 64 : MAX_PACKET_BYTES);
        end
        model.check_accounting();
        if(model.active==null || model.dispatched_bytes[0]==0 || model.dispatched_bytes[1]==0 ||
           model.cleared[0]!=0 || model.cleared[1]!=0)
            `uvm_fatal("SCHEDULE_ACCOUNTING","saturated endpoint not exercised")
        `uvm_info("SCHEDULER_BYTES",$sformatf("quantum0=%0d quantum1=%0d dispatch0=%0d dispatch1=%0d delivered0=%0d delivered1=%0d deficit0=%0d deficit1=%0d inflight=%0d",quantum0,quantum1,model.dispatched_bytes[0],model.dispatched_bytes[1],model.delivered_bytes[0],model.delivered_bytes[1],model.deficit[0],model.deficit[1],model.active.length-model.offset),UVM_NONE)
        drain();
    endtask
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        reset_case(64,128);
        step(0,65,0); // No same-edge visibility.
        until_eligible();
        // Fitting head waits; the first addition is not repeated per wait.
        repeat(4) step(-1,1,1,1,0);
        step(0,1); // Actual singleton dequeue/commit replacement.
        repeat(7) step(-1,1,1,0);
        finish_tx();
        until_eligible(); step(); // Continuing visit, then true empty.
        step(0,MAX_PACKET_BYTES); // Reactivation while prior packet is TX-owned.
        drain();
        reset_case(4096,64);
        step(0,1,0); step(0,1,0); step(0,MAX_PACKET_BYTES,0); step(1,MAX_PACKET_BYTES,0);
        until_eligible(); step(0,MAX_PACKET_BYTES); // Longer same-qid update.
        finish_tx(); until_eligible(); step(1,64); // Different qid update.
        drain();
        // Fixed maximum quantum, repeated maximum lengths and singleton
        // replacements exercise carry near the arithmetic bound.
        reset_case(4096,4096);
        step(0,1,0);
        repeat(12) begin
            until_eligible(); step(0,MAX_PACKET_BYTES);
            finish_tx();
        end
        drain();
        saturated(MAX_PACKET_BYTES,MAX_PACKET_BYTES);
        saturated(64,128);
        if(grants==0 || replacements==0 || longer==0 || different==0 || stalls==0 || waiting==0 || reactivations==0)
            `uvm_fatal("SCHEDULER_COVERAGE","mandatory scenario absent")
        `uvm_info("SCHEDULER",$sformatf("TM_SCHEDULER_PASS mode=%0d grants=%0d replacement=%0d longer=%0d different=%0d stalls=%0d waiting=%0d reactivation=%0d continuing=%0d max_credit=%0d cycles=%0d",SCHED_MODE,grants,replacements,longer,different,stalls,waiting,reactivations,continuing,max_credit,cycles),UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass
