// Scheduling expectations use canonical event/length model state only. No RTL
// cursor, visit or implementation state is read by this sequence or coverage.
class tm_scheduler_control extends uvm_object;
    `uvm_object_utils(tm_scheduler_control)
    rand bit [N_Q-1:0] active_mask;
    rand int unsigned quantum, burst, gap;
    constraint legal {
        active_mask!='0;
        quantum dist {64:=3,4096:=3,[65:4095]:/6};
        burst inside {[1:5]};
        gap inside {[0:12]};
    }
    function new(string name="scheduler_control"); super.new(name); endfunction
endclass

class tm_scheduler_stress_test extends tm_scheduler_rtl_test;
    `uvm_component_utils(tm_scheduler_stress_test)
    longint coverage_counts[string];
    monitor_batch_t last_batch;
    int log_fd, pre_cursor, pre_entries, pre_completed, pre_q, visit_packets[N_Q];
    int stall_run, random_publications, random_steps, progress_checks, reconfigurations;
    int arrivals_behind, arrivals_ahead, completion_commits, skip_commits, boundary_reactivations;
    bit pre_busy, random_phase;
    int random_epoch, random_lengths[10], random_qids[N_Q], random_quanta[3][N_Q];
    function new(string name, uvm_component parent);
        super.new(name,parent);
        foreach(visit_packets[q]) visit_packets[q]=0;
        coverage_counts["backlog.zero"]=0; coverage_counts["backlog.one"]=0; coverage_counts["backlog.multiple"]=0; coverage_counts["backlog.all"]=0;
        coverage_counts["cursor.wrap"]=0;
        coverage_counts["quantum.less"]=0; coverage_counts["quantum.equal"]=0; coverage_counts["quantum.greater"]=0;
        coverage_counts["stall.none"]=0; coverage_counts["stall.short"]=0; coverage_counts["stall.medium"]=0; coverage_counts["stall.long"]=0;
        coverage_counts["visit.zero"]=0; coverage_counts["visit.one"]=0; coverage_counts["visit.many"]=0;
        for(int phase_id=0;phase_id<6;phase_id++) for(int busy=0;busy<2;busy++)
            coverage_counts[$sformatf("reset.%0d.%0d",phase_id,busy)]=0;
        coverage_counts["quantum.minimum"]=0; coverage_counts["quantum.maximum"]=0;
        coverage_counts["final.stall"]=0;
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        log_fd=$fopen("scheduler-events.jsonl","w");
        if(log_fd==0) `uvm_fatal("SCHED_STRESS_LOG","cannot save passive events")
    endfunction
    function void observe_pre(monitor_batch_t batch);
        int active_queues, length, quantum;
        last_batch=batch;
        if(random_phase) begin
            random_steps++;
            if(batch.policy.commit.valid) begin
                random_publications++;
                random_qids[batch.policy.commit.qid]++;
            end
        end
        pre_cursor=model.cursor; pre_busy=model.active!=null;
        pre_q=model.cursor; pre_entries=model.visit_entries[pre_q]; pre_completed=model.completed_visits[pre_q];
        foreach(model.queues[q]) if(model.queues[q].frames.size()!=0) active_queues++;
        if(active_queues==0) coverage_counts["backlog.zero"]++;
        if(active_queues==1) coverage_counts["backlog.one"]++;
        if(active_queues>1) coverage_counts["backlog.multiple"]++;
        if(active_queues==N_Q) coverage_counts["backlog.all"]++;
        if(vif.cfg.run && !pre_busy && model.queues[pre_q].frames.size()!=0) begin
            length=model.queues[pre_q].frames[0].length;
            quantum=int'(vif.cfg.quantum[pre_q*13+:13]);
            if(quantum<length) coverage_counts["quantum.less"]++;
            else if(quantum==length) coverage_counts["quantum.equal"]++;
            else coverage_counts["quantum.greater"]++;
            if(quantum==64) coverage_counts["quantum.minimum"]++;
            if(quantum==4096) coverage_counts["quantum.maximum"]++;
        end
        if(batch.output_sample.valid && !batch.output_sample.ready) begin
            stall_run++;
            if(batch.output_sample.beat.last) coverage_counts["final.stall"]++;
        end else if(batch.output_sample.valid && batch.output_sample.ready) begin
            if(stall_run==0) coverage_counts["stall.none"]++;
            else if(stall_run<=3) coverage_counts["stall.short"]++;
            else if(stall_run<=15) coverage_counts["stall.medium"]++;
            else coverage_counts["stall.long"]++;
            stall_run=0;
        end
        if(batch.policy.commit.valid || batch.policy.dispatch.valid || batch.policy.tx_done.valid ||
           (batch.output_sample.valid && batch.output_sample.ready))
            $fwrite(log_fd,"{\"cycle\":%0d,\"commit\":\"%h\",\"dispatch\":\"%h\",\"done\":\"%h\",\"output\":\"%h\"}\n",
                cycles,batch.policy.commit,batch.policy.dispatch,batch.policy.tx_done,batch.output_sample);
    endfunction
    function void observe_post();
        if(pre_cursor==N_Q-1 && model.cursor==0 && !pre_busy) coverage_counts["cursor.wrap"]++;
        if(SCHED_MODE==1 && model.visit_entries[pre_q]!=pre_entries) visit_packets[pre_q]=0;
        if(last_batch.policy.dispatch.valid) begin
            if(SCHED_MODE==0) coverage_counts["visit.one"]++;
            else visit_packets[pre_q]++;
        end
        if(SCHED_MODE==1 && model.completed_visits[pre_q]!=pre_completed) begin
            if(visit_packets[pre_q]==0) coverage_counts["visit.zero"]++;
            else if(visit_packets[pre_q]==1) coverage_counts["visit.one"]++;
            else coverage_counts["visit.many"]++;
        end else if(SCHED_MODE==0 && !pre_busy && vif.cfg.run &&
                    model.queues[pre_q].frames.size()==0 && !last_batch.policy.dispatch.valid)
            coverage_counts["visit.zero"]++;
    endfunction
    task reset_case(int q0,int q1);
        stall_run=0;
        foreach(visit_packets[q]) visit_packets[q]=0;
        super.reset_case(q0,q1);
    endtask
    task configure_quanta(bit distinct_values=0);
        tm_scheduler_control control=new;
        @(negedge vif.clk);
        for(int q=0;q<N_Q;q++) begin
            if(control.randomize()==0) `uvm_fatal("SCHED_RANDOMIZE","control constraints failed")
            vif.cfg.quantum[q*13+:13]=13'(distinct_values ? 64+q*257 : control.quantum);
        end
        if(distinct_values) begin
            vif.cfg.quantum[0+:13]=13'(64);
            vif.cfg.quantum[(N_Q-1)*13+:13]=13'(4096);
        end
    endtask
    function int occupancy();
        int total=int'(model.active!=null);
        foreach(model.queues[q]) total+=model.queues[q].frames.size();
        return total;
    endfunction
    task random_traffic();
        tm_scheduler_control control=new;
        tm_packet p=new;
        bit [N_Q-1:0] active_mask;
        int gap, burst, hold_cycles, q, length_kind, quantum_value, randomized, final_held=-1;
        bit sink, ready;
        reset_case(64,64);
        configure_quanta();
        if(random_epoch==0) begin
            vif.cfg.quantum[0+:13]=13'(64);
            vif.cfg.quantum[(N_Q-1)*13+:13]=13'(4096);
        end else if(random_epoch==1) vif.cfg.quantum[0+:13]=13'($urandom_range(65,4095));
        for(int q=0;q<N_Q;q++) random_quanta[random_epoch][q]=int'(vif.cfg.quantum[q*13+:13]);
        random_phase=1;
        if(control.randomize()==0) `uvm_fatal("SCHED_RANDOMIZE","active subset constraints failed")
        active_mask=control.active_mask;
        for(int iteration=0;iteration<1600;iteration++) begin
            if(iteration%80==0) begin
                if(control.randomize()==0) `uvm_fatal("SCHED_RANDOMIZE","active subset constraints failed")
                active_mask=control.active_mask;
            end
            q=-1;
            if(gap==0 && occupancy()<N_DESC-1) begin
                int selected=$urandom_range(0,N_Q-1);
                int desired;
                while(!active_mask[selected]) selected=(selected+1)%N_Q;
                quantum_value=int'(vif.cfg.quantum[selected*13+:13]);
                length_kind=$urandom_range(0,9);
                case(length_kind)
                    0: desired=1;
                    1: desired=8;
                    2: desired=quantum_value-1<=MAX_PACKET_BYTES ? quantum_value-1 : MAX_PACKET_BYTES;
                    3: desired=quantum_value<=MAX_PACKET_BYTES ? quantum_value : MAX_PACKET_BYTES;
                    4: desired=quantum_value+1<=MAX_PACKET_BYTES ? quantum_value+1 : MAX_PACKET_BYTES;
                    5: desired=MAX_PACKET_BYTES;
                    default: desired=0;
                endcase
                randomized=p.randomize() with {qid==local::selected; source==0; length_class==3;
                    if(local::desired!=0) length==local::desired;};
                if(randomized==0)
                    `uvm_fatal("SCHED_RANDOMIZE","P07 packet constraints failed")
                q=int'(p.qid);
                if(burst==0) begin
                    if(control.randomize()==0) `uvm_fatal("SCHED_RANDOMIZE","gap/burst constraints failed")
                    burst=control.burst;
                end
                burst--;
                if(burst==0) gap=control.gap;
                random_lengths[length_kind]++;
            end else if(gap>0) gap--;
            ready=$urandom_range(0,9)<7;
            if(hold_cycles==0 && transmitting!=null) begin
                if(transmitting.length-tx_offset<=8 && final_held!=transmitting.desc) begin
                    final_held=transmitting.desc;
                    hold_cycles=$urandom_range(16,35);
                end else if($urandom_range(0,49)==0) hold_cycles=$urandom_range(16,40);
                else if($urandom_range(0,5)==0) hold_cycles=$urandom_range(1,12);
            end
            sink=hold_cycles==0;
            if(hold_cycles>0) hold_cycles--;
            step(q,q<0 ? 1 : int'(p.length),1,sink,ready);
        end
        random_phase=0; random_epoch++;
        drain();
    endtask
    task all_and_sparse();
        reset_case(64,64); configure_quanta(1);
        for(int q=0;q<N_Q;q++) step(q,q%2==0 ? 1 : MAX_PACKET_BYTES,0);
        // Several queues empty and reactivate during one round, behind the scan.
        repeat(N_Q) begin
            int selected;
            until_eligible(); selected=model.cursor;
            step();
            finish_tx();
            step(selected,1);
        end
        drain();
        reset_case(64,64); configure_quanta(1);
        for(int q=0;q<N_Q;q+=2) step(q,MAX_PACKET_BYTES,0);
        drain();
    endtask
    task arrival_boundaries();
        int age;
        reset_case(64,64);
        step(N_Q-1,1); // Behind the pre-state cursor: no same-edge bypass.
        age=0;
        while(model.active==null) begin step(); age++; end
        if(age!=N_Q-1) `uvm_fatal("SCHED_ARRIVAL_ROUND","behind-cursor arrival did not wait one round")
        arrivals_behind++;
        drain();
        reset_case(64,64);
        step(1,1); // Ahead of cursor zero, eligible on the next edge.
        step();
        if(last_batch.policy.dispatch.valid==0 || last_batch.policy.dispatch.qid!=1)
            `uvm_fatal("SCHED_ARRIVAL_AHEAD","ahead-cursor arrival was missed")
        arrivals_ahead++;
        drain();
        reset_case(64,64);
        step(0,1,0); until_eligible(); step();
        // One-byte TX completion and publication to the retained cursor occur
        // together; neither can enable a decision on that busy pre-state edge.
        step(model.cursor,65);
        if(!last_batch.policy.tx_done.valid || !last_batch.policy.commit.valid || last_batch.policy.dispatch.valid)
            `uvm_fatal("SCHED_EVENT_COMBINATION","completion/publication batch absent")
        completion_commits++;
        if(SCHED_MODE==1) begin
            step(model.cursor,1); // The 65-byte old head cannot fit quantum 64.
            if(last_batch.policy.dispatch.valid) `uvm_fatal("SCHED_SKIP_COMMIT","commit funded an insufficient head")
            skip_commits++;
        end
        drain();
        // Reach an emptied queue exactly when publishing its next incarnation.
        while(model.cursor!=0) step();
        step(0,1);
        if(last_batch.policy.dispatch.valid) `uvm_fatal("SCHED_REACTIVATION","reactivation bypassed an empty pre-state")
        boundary_reactivations++;
        drain();
    endtask
    task reconfigure();
        reset_case(64,64);
        step(0,65,0); drain();
        step(-1,1,0); // Disable only after the component has drained.
        @(negedge vif.clk);
        for(int q=0;q<N_Q;q++) vif.cfg.quantum[q*13+:13]=13'(q==0 ? 4096 : 127);
        step(-1,1,0);
        if(vif.deficits!='0) `uvm_fatal("SCHED_RECONFIGURE","drained reconfiguration retained stale credit")
        step(0,MAX_PACKET_BYTES,0);
        drain();
        reconfigurations++;
    endtask
    task progress_bound();
        // At least one accepted output beat every three cycles; readiness is
        // continuously true. A MAX-byte packet retires within TX_BOUND clocks.
        localparam int TX_BOUND=3*((MAX_PACKET_BYTES+7)/8);
        localparam longint ROUND_BOUND=longint'(N_Q)*(64'd2+(64'd4096+longint'(MAX_PACKET_BYTES)-64'd1)*(longint'(TX_BOUND)+64'd1));
        int needed, age, entries_at_start, last_entry_cycle, prior_entries;
        reset_case(64,4096);
        for(int q=0;q<N_Q;q++) step(q,MAX_PACKET_BYTES,0);
        needed=(MAX_PACKET_BYTES+63)/64;
        entries_at_start=model.visit_entries[0]; prior_entries=entries_at_start;
        age=0; last_entry_cycle=0;
        while(model.dispatched_bytes[0]==0) begin
            int selected=-1;
            if(eligible()) selected=model.cursor;
            step(selected,MAX_PACKET_BYTES,1,age%3==0,1);
            age++;
            if(longint'(age)>longint'(needed)*ROUND_BOUND)
                `uvm_fatal("SCHED_PROGRESS_CYCLES","head exceeded the concept-derived visit/round/retirement deadline")
            if(model.visit_entries[0]!=prior_entries) begin
                if((longint'(age)-longint'(last_entry_cycle))>ROUND_BOUND)
                    `uvm_fatal("SCHED_PROGRESS_ROUND","backlogged queue missed a bounded cursor round")
                last_entry_cycle=age; prior_entries=model.visit_entries[0];
            end
            if(SCHED_MODE==1 && model.visit_entries[0]-entries_at_start>needed)
                `uvm_fatal("SCHED_PROGRESS_VISITS","head exceeded ceil((length-credit)/quantum) visits")
        end
        if(SCHED_MODE==1 && model.visit_entries[0]-entries_at_start!=needed)
            `uvm_fatal("SCHED_PROGRESS_VISITS","small-quantum boundary was not exercised exactly")
        progress_checks++;
        `uvm_info("SCHED_PROGRESS",$sformatf("age=%0d needed_visits=%0d round_bound=%0d tx_bound=%0d",age,needed,ROUND_BOUND,TX_BOUND),UVM_NONE)
        drain();
    endtask
    task packet_rr_terms();
        int first_q[3*N_Q], first_length[3*N_Q];
        if(SCHED_MODE!=0) return;
        for(int phase_id=0;phase_id<2;phase_id++) begin
            reset_case(phase_id==0 ? 64 : 4096,phase_id==0 ? 4096 : 64);
            for(int q=0;q<N_Q;q++) step(q,q%2==0 ? 1 : MAX_PACKET_BYTES,0);
            for(int k=0;k<3*N_Q;k++) begin
                int selected;
                until_eligible(); selected=model.cursor;
                step(selected,k%2==0 ? MAX_PACKET_BYTES : 1);
                if(last_batch.policy.dispatch.qid!=Q_ID_W'(k%N_Q) || vif.deficits!='0)
                    `uvm_fatal("SCHED_PACKET_RR","RR did not rotate one packet per nonempty visit with zero credit")
                if(phase_id==0) begin first_q[k]=int'(last_batch.policy.dispatch.qid); first_length[k]=int'(last_batch.policy.dispatch.info.length); end
                else if(first_q[k]!=int'(last_batch.policy.dispatch.qid) || first_length[k]!=int'(last_batch.policy.dispatch.info.length))
                    `uvm_fatal("SCHED_PACKET_RR_QUANTUM","packet RR service depended on quantum")
            end
            drain();
        end
    endtask
    // phase IDs: idle, funded/no-owner, pending commit, eligible dispatch,
    // completion, owned stall. Reset cancels actions on its own edge.
    task pulse_reset(int phase_id);
        bit busy=transmitting!=null;
        coverage_counts[$sformatf("reset.%0d.%0d",phase_id,int'(busy))]++;
        $fwrite(log_fd,"{\"reset_phase\":%0d,\"owned\":%0d,\"cycle\":%0d}\n",phase_id,busy,cycles);
        vif.rst_n=0;
        repeat(2) begin
            @(posedge vif.clk); #1;
            if(vif.dispatch.valid || vif.deficits!='0 || vif.counts!='0)
                `uvm_fatal("SCHED_RESET","reset accepted work or retained queue/credit")
        end
        @(negedge vif.clk);
        vif.commit='0; vif.tx_done='0; vif.output_sample='0; vif.cell_free='0;
        vif.cfg='0; vif.tx_ready=1;
        for(int q=0;q<N_Q;q++) vif.cfg.quantum[q*13+:13]=13'(64);
        model.flush(); input_checker.flush(); transmitting=null; tx_offset=0; next_id=0;
        foreach(visit_packets[q]) visit_packets[q]=0;
        stall_run=0;
        vif.rst_n=1;
        step(0,1,0); // First new-epoch visit must start at queue zero.
        step(0,1);
        if(!last_batch.policy.dispatch.valid || last_batch.policy.dispatch.qid!=0 ||
           (SCHED_MODE==1 && int'(vif.deficits[0+:DEFICIT_W])!=63))
            `uvm_fatal("SCHED_RESET_ENTRY","new epoch did not start at zero with exactly one quantum")
        drain();
    endtask
    task reset_phases();
        tm_frame f;
        reset_case(64,64); @(negedge vif.clk); pulse_reset(0);
        if(SCHED_MODE==1) begin
            reset_case(64,64); step(0,1,0); step(-1,1,1,1,0);
            @(negedge vif.clk); pulse_reset(1);
        end
        reset_case(64,64);
        @(negedge vif.clk); f=packet(0,1);
        vif.commit='{1,DESC_ID_W'(f.desc),Q_ID_W'(0),f.descriptor}; pulse_reset(2);
        reset_case(64,64); step(0,MAX_PACKET_BYTES,0); until_eligible(); step();
        @(negedge vif.clk); f=packet(1,1);
        vif.commit='{1,DESC_ID_W'(f.desc),Q_ID_W'(1),f.descriptor}; pulse_reset(2);
        reset_case(64,64); step(0,1,0);
        @(negedge vif.clk); vif.cfg.run=1; #1; pulse_reset(3);
        reset_case(64,64); step(0,1,0); until_eligible(); step();
        @(negedge vif.clk);
        vif.tx_done='{1,DESC_ID_W'(transmitting.desc),Q_ID_W'(transmitting.qid),16'(transmitting.length)};
        pulse_reset(4);
        reset_case(64,64); step(0,MAX_PACKET_BYTES,0); until_eligible(); step();
        repeat(3) step(-1,1,1,0);
        @(negedge vif.clk); pulse_reset(5);
    endtask
    task input_probe(string kind);
        monitor_batch_t batch;
        tm_frame frame;
        reset_case(64,64);
        if(kind=="duplicate_commit") step(0,1,0);
        else if(kind=="done_mismatch") begin step(0,MAX_PACKET_BYTES,0); until_eligible(); step(); end
        else if(kind=="config") step(0,1);
        else if(kind=="stale_done") begin
            step(0,MAX_PACKET_BYTES,0); until_eligible(); step();
            reset_case(64,64);
        end
        @(negedge vif.clk);
        vif.commit='0; vif.tx_done='0; vif.output_sample='0;
        if(kind=="duplicate_commit") begin
            frame=model.queues[0].frames[0];
            vif.commit='{1,DESC_ID_W'(frame.desc),Q_ID_W'(0),frame.descriptor};
        end else if(kind=="config") begin vif.cfg.run=1; vif.cfg.quantum[0+:13]=13'(128); end
        else if(kind=="done_mismatch")
            vif.tx_done='{1,DESC_ID_W'((transmitting.desc+1)%N_DESC),Q_ID_W'(transmitting.qid),16'(transmitting.length)};
        else vif.tx_done='{1,DESC_ID_W'(0),Q_ID_W'(0),16'(MAX_PACKET_BYTES)};
        @(posedge vif.clk); monitor.sample(batch,frame);
        // A stale unowned completion must leave the reset epoch's external
        // queue/credit state intact before the neighbor violation is reported.
        if(kind=="stale_done") begin
            #1;
            if(vif.deficits!='0 || vif.counts!='0 || vif.dispatch.valid)
                `uvm_fatal("SCHED_STALE_EPOCH","stale completion changed reset epoch state")
        end
        input_checker.check(batch,vif.cfg);
        `uvm_fatal("SCHED_INPUT_PROBE","invalid neighbor was not detected")
    endtask
    function void save_coverage();
        int fd=$fopen("scheduler-stress.json","w");
        if(fd==0) `uvm_fatal("SCHED_STRESS_LOG","cannot save functional counters")
        $fwrite(fd,"{\"mode\":%0d,\"random_publications\":%0d,\"random_steps\":%0d,\"progress_checks\":%0d,\"reconfigurations\":%0d,\"behind\":%0d,\"ahead\":%0d,\"completion_commits\":%0d,\"skip_commits\":%0d,\"reactivation_boundary\":%0d,\"coverage_counts\":{",SCHED_MODE,random_publications,random_steps,progress_checks,reconfigurations,arrivals_behind,arrivals_ahead,completion_commits,skip_commits,boundary_reactivations);
        begin bit first=1; foreach(coverage_counts[name]) begin
            $fwrite(fd,"%s\"%s\":%0d",first ? "" : ",",name,coverage_counts[name]); first=0;
        end end
        $fwrite(fd,"},\"random_quanta\":[");
        for(int epoch_id=0;epoch_id<3;epoch_id++) begin
            $fwrite(fd,"%s[",epoch_id==0 ? "" : ",");
            for(int q=0;q<N_Q;q++) $fwrite(fd,"%s%0d",q==0 ? "" : ",",random_quanta[epoch_id][q]);
            $fwrite(fd,"]");
        end
        $fwrite(fd,"],\"random_qids\":[");
        for(int q=0;q<N_Q;q++) $fwrite(fd,"%s%0d",q==0 ? "" : ",",random_qids[q]);
        $fwrite(fd,"],\"length_choices\":[");
        for(int k=0;k<10;k++) $fwrite(fd,"%s%0d",k==0 ? "" : ",",random_lengths[k]);
        $fwrite(fd,"]}\n"); $fclose(fd); $fclose(log_fd);
    endfunction
    task additional_cases();
        all_and_sparse(); arrival_boundaries(); reconfigure(); progress_bound();
        packet_rr_terms(); repeat(3) random_traffic(); reset_phases();
        // Deliberately close every stall-duration class, including final beat.
        foreach(visit_packets[q]) visit_packets[q]=0;
        for(int duration=1;duration<=16;duration*=4) begin
            reset_case(64,64); step(0,1,0); until_eligible(); step();
            repeat(duration) step(-1,1,1,0);
            finish_tx(); drain();
        end
        save_coverage();
        `uvm_info("SCHED_STRESS",$sformatf("TM_SCHED_STRESS_PASS random_publications=%0d random_steps=%0d progress=%0d",random_publications,random_steps,progress_checks),UVM_NONE)
    endtask
    task run_phase(uvm_phase phase);
        string probe;
        if($value$plusargs("INPUT_PROBE=%s",probe)) begin
            phase.raise_objection(this); input_probe(probe); phase.drop_objection(this);
        end else super.run_phase(phase);
    endtask
endclass
