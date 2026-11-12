module queues_tb #(
`include "tm_parameters.svh"
) ();
`include "tm_types.svh"
logic clk=0, rst_n=0;
always #5 clk=~clk;
commit_t commit='0;
dispatch_t dispatch='0;
desc_link_write_t next_write;
desc_id_t old_head_next, read_id, available_id;
logic [N_Q*DESC_ID_W-1:0] heads,tails;
logic [N_Q*DESC_COUNT_W-1:0] counts;
logic invariant_error, pool_error, available;
desc_count_t free_count;
admission_t admit='0;
desc_return_t tx_return='0, abort_return='0;
`define QUEUE_PARAMS .N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),.MAX_PACKET_BYTES(MAX_PACKET_BYTES),.DESC_ID_W(DESC_ID_W),.DESC_COUNT_W(DESC_COUNT_W)
tm_queue_ctrl_api #(`QUEUE_PARAMS) dut(.*);
tm_desc_links #(`QUEUE_PARAMS) links(.clk(clk),.write_req(next_write),.read_id(read_id),.read_next(old_head_next));
// Real P02 boundary: queue dispatch has no connection to either return lane.
tm_desc_pool_api #(`QUEUE_PARAMS) pool(.clk(clk),.rst_n(rst_n),.admit(admit),
    .tx_return(tx_return),.abort_return(abort_return),.available_id(available_id),
    .free_count(free_count),.available(available),.invariant_error(pool_error));
`undef QUEUE_PARAMS

// Independent lists and ownership states, consumed only from accepted actions.
desc_id_t model [N_Q][N_DESC];
int length [N_Q];
bit [N_DESC-1:0] owned='0, tx_owned='0;
// Passive port-contract checker; unlike the FIFO model this follows writes.
desc_id_t saved_link [N_DESC];
bit [N_DESC-1:0] link_known='0;
int cycles=0, pushes=0, pops=0, last_replace=0, long_replace=0;
int different=0, empty_attempts=0, full=0, reused_stale=0, reset_collisions=0;
int read_write_collision=0, delayed_returns=0, rapid_reuse=0;
int rejected_empty=0;
int last_return=-1;
int unsigned rng;
function automatic int unsigned random_word();
    rng=rng ^ (rng<<13); rng=rng ^ (rng>>17); rng=rng ^ (rng<<5);
    return rng;
endfunction
function automatic int tx_candidate();
    for(int id=0;id<N_DESC;id++) if(tx_owned[id]) return id;
    return -1;
endfunction

task automatic check_queries;
    for(int q=0;q<N_Q;q++) begin
        assert(int'(counts[q*DESC_COUNT_W +: DESC_COUNT_W])==length[q])
            else $fatal(1,"TM_QUEUES_FAIL count q=%0d",q);
        if(length[q]>0) begin
            assert(heads[q*DESC_ID_W +: DESC_ID_W]==model[q][0])
                else $fatal(1,"TM_QUEUES_FAIL order q=%0d",q);
            assert(tails[q*DESC_ID_W +: DESC_ID_W]==model[q][length[q]-1])
                else $fatal(1,"TM_QUEUES_FAIL tail q=%0d",q);
        end
    end
    assert(int'(free_count)==N_DESC-$countones(owned) && !pool_error && !invariant_error)
        else $fatal(1,"TM_QUEUES_FAIL ownership/count");
    assert(available==(rst_n && $countones(owned)<N_DESC))
        else $fatal(1,"TM_QUEUES_FAIL availability");
    if(available) assert(!owned[available_id])
        else $fatal(1,"TM_QUEUES_FAIL selected owned ID");
endtask

task automatic step(input bit want_commit, want_pop, input int cq,pq,
                    input int return_id=-1, input bit reset_now=0);
    bit push,pop;
    int old_length;
    desc_id_t removed;
    desc_link_write_t expected_write;
    @(negedge clk);
    rst_n=!reset_now;
    #1;
    commit='0; dispatch='0; admit='0; tx_return='0;
    commit.valid=want_commit && (available || reset_now);
    commit.qid=Q_ID_W'(cq); commit.desc=available_id;
    commit.info.qid=commit.qid;
    admit.valid=commit.valid; admit.accept=1; admit.desc=commit.desc;
    // Scheduler-style pre-state acceptance. Empty attempts never dispatch.
    dispatch.valid=want_pop && length[pq]>0;
    dispatch.qid=Q_ID_W'(pq); dispatch.desc=model[pq][0];
    read_id=heads[pq*DESC_ID_W +: DESC_ID_W];
    if(return_id>=0) begin
        tx_return.valid=1; tx_return.desc=DESC_ID_W'(return_id);
    end
    #1;
    if(!reset_now) check_queries();
    push=commit.valid && rst_n; pop=dispatch.valid && rst_n;
    old_length=length[cq];
    expected_write='0;
    if(push && old_length>0 && !(pop && cq==pq && old_length==1)) begin
        expected_write.valid=1;
        expected_write.id=model[cq][old_length-1];
        expected_write.next_id=commit.desc;
    end
    assert(next_write===expected_write)
        else $fatal(1,"TM_QUEUES_FAIL link write port");
    if(link_known[read_id]) assert(old_head_next===saved_link[read_id])
        else $fatal(1,"TM_QUEUES_FAIL combinational pre-state link");
    @(posedge clk);
    cycles++;
    if(reset_now) begin
        if(want_commit && dispatch.valid) reset_collisions++;
        for(int q=0;q<N_Q;q++) length[q]=0;
        owned='0; tx_owned='0; last_return=-1;
    end else begin
        if(want_pop && length[pq]==0) empty_attempts++;
        if($countones(owned)==N_DESC) full++;
        if(push && pop) begin
            if(cq!=pq) different++;
            else if(old_length==1) last_replace++;
            else long_replace++;
        end
        if(tx_return.valid) begin
            assert(tx_owned[tx_return.desc]) else $fatal(1,"TM_QUEUES_FAIL premature return");
            tx_owned[tx_return.desc]=0; owned[tx_return.desc]=0; delayed_returns++;
        end
        if(pop) begin
            removed=model[pq][0];
            assert(dispatch.desc==removed && owned[removed] && !tx_owned[removed])
                else $fatal(1,"TM_QUEUES_FAIL dispatch ownership");
            for(int k=0;k<length[pq]-1;k++) model[pq][k]=model[pq][k+1];
            length[pq]--; tx_owned[removed]=1; pops++;
        end
        if(push) begin
            assert(!owned[commit.desc]) else $fatal(1,"TM_QUEUES_FAIL duplicate commit");
            if(link_known[commit.desc]) reused_stale++;
            if(int'(commit.desc)==last_return) rapid_reuse++;
            owned[commit.desc]=1;
            model[cq][length[cq]]=commit.desc; length[cq]++; pushes++;
        end
        last_return=tx_return.valid ? int'(tx_return.desc) : -1;
    end
    if(next_write.valid) begin
        if(next_write.id==read_id) read_write_collision++;
        saved_link[next_write.id]=next_write.next_id;
        link_known[next_write.id]=1;
    end
    #1;
    check_queries();
endtask

// Illegal dispatch_fire is diagnosed and cannot consume a same-edge commit.
// Normal stimulus above emits only accepted pre-state dispatch actions.
task automatic check_empty_guard(input bit publish);
    step(0,0,0,0,-1,1);
    @(negedge clk);
    rst_n=1;
    #1;
    commit='0;
    commit.valid=publish;
    commit.desc=available_id;
    admit='0;
    admit.valid=publish;
    admit.accept=1;
    admit.desc=commit.desc;
    dispatch='0;
    dispatch.valid=1;
    dispatch.desc=commit.desc;
    tx_return='0;
    #1;
    assert(!next_write.valid) else $fatal(1,"TM_QUEUES_FAIL empty wrote link");
    @(posedge clk);
    #1;
    assert(invariant_error && int'(counts[0 +: DESC_COUNT_W])==int'(publish))
        else $fatal(1,"TM_QUEUES_FAIL empty dispatch accepted");
    if(publish) assert(heads[0 +: DESC_ID_W]==commit.desc && tails[0 +: DESC_ID_W]==commit.desc)
        else $fatal(1,"TM_QUEUES_FAIL empty commit bypass");
    assert(int'(free_count)==N_DESC-int'(publish))
        else $fatal(1,"TM_QUEUES_FAIL empty dispatch returned descriptor");
    rejected_empty++;
endtask

initial begin
    if(!$value$plusargs("SEED=%d",rng)) rng=17;
    if($test$plusargs("TRACE")) begin $dumpfile("wave.vcd"); $dumpvars(0,queues_tb); end
    for(int q=0;q<N_Q;q++) length[q]=0;
    step(0,0,0,0,-1,1);
    for(int q=0;q<N_Q;q++) begin
        step(1,1,q,q); // empty attempt plus commit: visible only after edge
        step(1,1,q,q); // singleton replacement
        step(1,0,q,q);
        step(1,1,q,q); // longer replacement
        step(1,1,(q+1)%N_Q,q); // independent qid changes
        step(1,1,q,(q+1)%N_Q,-1,1); // active reset collision
    end
    // Fill all descriptors in one queue, then dispatch without releasing any.
    for(int k=0;k<N_DESC;k++) step(1,0,0,0);
    step(1,0,0,0); // no free pre-state descriptor
    for(int k=0;k<N_DESC;k++) step(0,1,0,0);
    assert(!available && free_count==0) else $fatal(1,"TM_QUEUES_FAIL dispatch freed descriptor");
    step(1,1,0,0,tx_candidate()); // return cannot fund same-edge allocation
    assert(!commit.valid) else $fatal(1,"TM_QUEUES_FAIL return bypass");
    step(1,0,0,0);
    for(int k=0;k<12000;k++) begin
        int cq,pq,ret;
        bit c,p,r;
        cq=int'(random_word()%N_Q); pq=int'(random_word()%N_Q);
        c=(random_word()%4)!=0; p=(random_word()%4)!=0;
        r=(random_word()%3)!=0;
        ret=r ? tx_candidate() : -1;
        step(c,p,cq,pq,ret,k%997==996);
    end
    assert(last_replace>0 && long_replace>0 && different>0 && empty_attempts>0 && full>0 &&
           reused_stale>0 && reset_collisions>0 && rapid_reuse>0 && read_write_collision>0)
        else $fatal(1,"TM_QUEUES_FAIL missing required scenario");
    check_empty_guard(0);
    check_empty_guard(1);
    step(0,0,0,0,-1,1);
    $display("TM_QUEUES_PASS cycles=%0d pushes=%0d pops=%0d last_replace=%0d long_replace=%0d different=%0d empty_attempts=%0d full=%0d reused_stale=%0d reset_collisions=%0d rapid_reuse=%0d read_write_collision=%0d delayed_returns=%0d rejected_empty=%0d",cycles,pushes,pops,last_replace,long_replace,different,empty_attempts,full,reused_stale,reset_collisions,rapid_reuse,read_write_collision,delayed_returns,rejected_empty);
    $finish;
end
endmodule
