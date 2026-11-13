// Independent specification model; observations are sampled at API acceptance.
module queue_api_monitor import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk, rst_n,
    input commit_t commit,
    input dispatch_t dispatch,
    input admission_t admit,
    input desc_return_t tx_return, abort_return,
    input logic available, pool_error, invariant_error,
    input desc_id_t available_id, read_id, old_head_next,
    input desc_count_t free_count,
    input desc_link_write_t next_write,
    input logic [N_Q*DESC_ID_W-1:0] heads, tails,
    input logic [N_Q*DESC_COUNT_W-1:0] counts
);
localparam int FREE=0, RX=1, QUEUED=2, TX=3;
int owner[N_DESC], allocated_at[N_DESC];
int items[N_Q][N_DESC], size[N_Q];
int transition[N_Q][3][4]; // sampled pre-count class x {commit,pop}
int cycles=0, delayed_publish=0, reuse=0, tx_retained=0, full=0;
int reset_active=0, reset_collision=0, read_checks=0, link_collision=0;
int owner_peak=0, same_singleton=0, same_long=0, different=0, empty_publish=0;
bit initialized=0, ever_used[N_DESC];
bit link_known[N_DESC];
desc_id_t link_value[N_DESC]; // port semantics only; never FIFO expectation
int events;

task automatic queries;
    int live;
    live=0;
    foreach(owner[id]) if(owner[id]!=FREE) live++;
    if(live>owner_peak) owner_peak=live;
    assert(int'(free_count)==N_DESC-live && !pool_error && !invariant_error)
        else $fatal(1,"QUEUE_DV_OWNERSHIP cycle=%0d",cycles);
    assert(available==(rst_n && live<N_DESC)) else $fatal(1,"QUEUE_DV_AVAILABLE");
    if(available) assert(int'(available_id)<N_DESC && owner[int'(available_id)]==FREE)
        else $fatal(1,"QUEUE_DV_FREE_ID");
    foreach(size[q]) begin
        assert(int'(counts[q*DESC_COUNT_W+:DESC_COUNT_W])==size[q])
            else $fatal(1,"QUEUE_DV_COUNT q=%0d cycle=%0d",q,cycles);
        if(size[q]>0) begin
            assert(int'(heads[q*DESC_ID_W+:DESC_ID_W])==items[q][0])
                else $fatal(1,"QUEUE_DV_ORDER q=%0d cycle=%0d",q,cycles);
            assert(int'(tails[q*DESC_ID_W+:DESC_ID_W])==items[q][size[q]-1])
                else $fatal(1,"QUEUE_DV_TAIL q=%0d",q);
        end
    end
endtask

always @(posedge clk) begin : observe
    bit pub, pop, alloc;
    int live, before_total;
    desc_link_write_t expected_write;
    pub=rst_n && commit.valid;
    pop=rst_n && dispatch.valid;
    alloc=rst_n && admit.valid && admit.accept;
    cycles++;
    if(initialized && rst_n) queries();
    expected_write='0;
    before_total=0;
    foreach(size[q]) before_total+=size[q];
    if(!rst_n) begin
        if(before_total>0) reset_active++;
        if(before_total>0 && commit.valid && dispatch.valid) reset_collision++;
        foreach(size[q]) size[q]=0;
        foreach(owner[id]) owner[id]=FREE;
        initialized=1;
    end else begin
        // All legality is checked against the SAME pre-state, before any update.
        if(alloc) assert(available && int'(admit.desc)<N_DESC && owner[int'(admit.desc)]==FREE && admit.desc==available_id)
            else $fatal(1,"QUEUE_DV_ALLOC_LEGAL");
        if(pub) begin
            assert(int'(commit.qid)<N_Q && int'(commit.desc)<N_DESC)
                else $fatal(1,"QUEUE_DV_COMMIT_RANGE");
            assert(owner[int'(commit.desc)]==RX || (alloc && admit.desc==commit.desc))
                else $fatal(1,"QUEUE_DV_COMMIT_OWNER");
            foreach(size[q]) for(int k=0;k<size[q];k++)
                assert(items[q][k]!=int'(commit.desc)) else $fatal(1,"QUEUE_DV_DUPLICATE");
        end
        if(pop) begin
            assert(int'(dispatch.qid)<N_Q && size[dispatch.qid]>0)
                else $fatal(1,"QUEUE_DV_EMPTY_BYPASS");
            assert(int'(dispatch.desc)==items[dispatch.qid][0] && owner[int'(dispatch.desc)]==QUEUED)
                else $fatal(1,"QUEUE_DV_DISPATCH_OWNER");
        end
        if(tx_return.valid) assert(owner[int'(tx_return.desc)]==TX)
            else $fatal(1,"QUEUE_DV_EARLY_RETURN");
        if(abort_return.valid) assert(owner[int'(abort_return.desc)]==RX)
            else $fatal(1,"QUEUE_DV_ABORT_OWNER");
        // The list contract defines which pre-state tail remains linked.
        if(pub && size[commit.qid]>0 && !(pop && dispatch.qid==commit.qid && size[commit.qid]==1)) begin
            expected_write.valid=1;
            expected_write.id=DESC_ID_W'(items[commit.qid][size[commit.qid]-1]);
            expected_write.next_id=commit.desc;
        end
        foreach(size[q]) begin
            int c, e;
            c=size[q]==0 ? 0 : size[q]==1 ? 1 : 2;
            e=2*int'(pub && int'(commit.qid)==q)+int'(pop && int'(dispatch.qid)==q);
            transition[q][c][e]++;
            // Compare only API-visible live edges, independently of saved writes.
            for(int k=0;k+1<size[q];k++) if(int'(read_id)==items[q][k]) begin
                assert(int'(old_head_next)==items[q][k+1]) else $fatal(1,"QUEUE_DV_NEXT");
                read_checks++;
            end
        end
        if(pub && size[commit.qid]==0) empty_publish++;
        if(pub && pop) begin
            if(commit.qid!=dispatch.qid) different++;
            else if(size[commit.qid]==1) same_singleton++;
            else same_long++;
        end
        if(before_total==N_DESC) full++;
        live=0;
        foreach(owner[id]) if(owner[id]==TX) live++;
        if(live>0 && int'(free_count)<N_DESC-before_total) tx_retained++;
        if(alloc) begin
            if(ever_used[int'(admit.desc)]) reuse++;
            ever_used[int'(admit.desc)]=1;
            allocated_at[int'(admit.desc)]=cycles;
        end
        if(pub && owner[int'(commit.desc)]==RX && cycles>allocated_at[int'(commit.desc)]+1) delayed_publish++;
        $fdisplay(events,"{\"cycle\":%0d,\"alloc\":%0d,\"commit\":%0d,\"pop\":%0d,\"cq\":%0d,\"pq\":%0d,\"desc\":%0d}",cycles,alloc,pub,pop,commit.qid,dispatch.qid,commit.desc);
        if(tx_return.valid) owner[int'(tx_return.desc)]=FREE;
        if(abort_return.valid) owner[int'(abort_return.desc)]=FREE;
        if(alloc) owner[int'(admit.desc)]=RX;
        if(pop) begin
            for(int k=0;k+1<size[dispatch.qid];k++) items[dispatch.qid][k]=items[dispatch.qid][k+1];
            size[dispatch.qid]--;
            owner[int'(dispatch.desc)]=TX;
        end
        if(pub) begin
            items[commit.qid][size[commit.qid]]=int'(commit.desc);
            size[commit.qid]++;
            owner[int'(commit.desc)]=QUEUED;
        end
    end
    assert(next_write===expected_write) else $fatal(1,"QUEUE_DV_LINK_PORT");
    if(link_known[int'(read_id)]) assert(old_head_next===link_value[int'(read_id)])
        else $fatal(1,"QUEUE_DV_LINK_PRESTATE");
    if(next_write.valid) begin
        if(next_write.id==read_id) link_collision++;
        link_known[int'(next_write.id)]=1;
        link_value[int'(next_write.id)]=next_write.next_id;
    end
    #1;
    queries();
end
initial events=$fopen("api-events.jsonl","w");

task automatic report;
    int fd;
    foreach(size[q]) begin
        // Empty+accepted-pop is illegal; every other pre-count/action bin is mandatory.
        for(int c=0;c<3;c++) for(int e=0;e<4;e++)
            if(!(c==0 && (e==1 || e==3)))
                assert(transition[q][c][e]>0) else $fatal(1,"QUEUE_DV_COVERAGE q=%0d count=%0d event=%0d",q,c,e);
    end
    assert(same_singleton>0 && same_long>0 && different>0 && empty_publish>0 && delayed_publish>0 && reuse>0 && tx_retained>0 && full>0 && reset_active>0 && reset_collision>0 && read_checks>0 && link_collision>0)
        else $fatal(1,"QUEUE_DV_COVERAGE lifetime/reset/link");
    fd=$fopen("queue-coverage.json","w");
    $fdisplay(fd,"{\"cycles\":%0d,\"delayed_publish\":%0d,\"reuse\":%0d,\"tx_retained\":%0d,\"full\":%0d,\"reset_active\":%0d,\"reset_collision\":%0d,\"read_checks\":%0d,\"link_collision\":%0d,\"owner_peak\":%0d,\"bins\":[",cycles,delayed_publish,reuse,tx_retained,full,reset_active,reset_collision,read_checks,link_collision,owner_peak);
    foreach(size[q]) for(int c=0;c<3;c++) for(int e=0;e<4;e++)
        $fdisplay(fd,"%s{\"qid\":%0d,\"pre_count\":%0d,\"event\":%0d,\"hits\":%0d}",(q==0 && c==0 && e==0)?"":",",q,c,e,transition[q][c][e]);
    $fdisplay(fd,"],\"same_singleton\":%0d,\"same_long\":%0d,\"different\":%0d,\"empty_publish\":%0d}",same_singleton,same_long,different,empty_publish);
    $fclose(fd); $fclose(events);
endtask
endmodule
