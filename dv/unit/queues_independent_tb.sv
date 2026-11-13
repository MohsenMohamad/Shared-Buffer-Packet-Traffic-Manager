module queues_independent_tb #(
`include "tm_parameters.svh"
) ();
`include "tm_types.svh"
logic clk=0, rst_n=0;
always #5 clk=~clk;
commit_t commit='0;
dispatch_t dispatch='0;
admission_t admit='0;
desc_return_t tx_return='0, abort_return='0;
logic [N_Q*DESC_ID_W-1:0] heads,tails;
logic [N_Q*DESC_COUNT_W-1:0] counts;
desc_link_write_t next_write;
desc_id_t read_id='0, old_head_next, available_id;
desc_count_t free_count;
logic available, pool_error, invariant_error;
`define QPARAM .N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),.MAX_PACKET_BYTES(MAX_PACKET_BYTES),.DESC_ID_W(DESC_ID_W),.DESC_COUNT_W(DESC_COUNT_W)
tm_queue_ctrl_api #(`QPARAM) dut(.*);
tm_desc_links #(`QPARAM) links(.clk(clk),.write_req(next_write),.read_id(read_id),.read_next(old_head_next));
tm_desc_pool_api #(`QPARAM) pool(.clk(clk),.rst_n(rst_n),.admit(admit),.tx_return(tx_return),.abort_return(abort_return),.available_id(available_id),.free_count(free_count),.available(available),.invariant_error(pool_error));
queue_api_monitor #(`QPARAM) mon(.*);
`undef QPARAM
int unsigned rng;
function automatic int unsigned draw();
    rng^=rng<<13; rng^=rng>>17; rng^=rng<<5; return rng;
endfunction
function automatic int candidate(input int state);
    int start;
    start=int'(draw()%N_DESC);
    for(int k=0;k<N_DESC;k++) if(mon.owner[(start+k)%N_DESC]==state) return (start+k)%N_DESC;
    return -1;
endfunction
// Drive before the edge; the passive monitor alone owns model updates/checking.
task automatic drive_cycle(input bit allocate=0, input int publish=-1, cq=0, pq=-1, ret=-1, input bit reset_now=0);
    @(negedge clk);
    rst_n=!reset_now;
    admit='0; commit='0; dispatch='0; tx_return='0;
    #1;
    if(allocate && available) begin
        admit.valid=1; admit.accept=1; admit.desc=available_id;
    end
    if(publish>=0) begin
        commit.valid=1; commit.desc=DESC_ID_W'(publish); commit.qid=Q_ID_W'(cq);
        commit.info.qid=commit.qid;
    end
    if(pq>=0) begin
        dispatch.valid=1; dispatch.qid=Q_ID_W'(pq);
        dispatch.desc=heads[pq*DESC_ID_W+:DESC_ID_W];
        read_id=dispatch.desc;
    end else read_id=DESC_ID_W'(draw()%N_DESC);
    if(ret>=0) begin tx_return.valid=1; tx_return.desc=DESC_ID_W'(ret); end
    @(posedge clk); #2;
endtask

task automatic publish_new(input int q, pq=-1);
    int id;
    drive_cycle(1); id=int'(admit.desc);
    drive_cycle(0,id,q,pq);
endtask
initial begin
    int delayed_id;
    if(!$value$plusargs("SEED=%d",rng)) rng=17;
    if($test$plusargs("TRACE")) begin $dumpfile("wave.vcd"); $dumpvars(0,queues_independent_tb); end
    drive_cycle(0,-1,0,-1,-1,1);
    // Deliberately hit all legal per-qid pre-count/action bins.
    for(int q=0;q<N_Q;q++) begin
        drive_cycle(0,-1,0,-1,-1,1);
        drive_cycle();
        drive_cycle(1,int'(available_id),q); // legal same-edge allocation/publication
        drive_cycle();
        publish_new(q,q); // singleton replacement
        publish_new(q); drive_cycle(); // multi idle
        publish_new(q); publish_new(q,q); // multi push / replacement
        drive_cycle(0,-1,0,q); drive_cycle(0,-1,0,q); drive_cycle(0,-1,0,q); // multi + last pop
    end
    drive_cycle(0,-1,0,-1,-1,1);
    for(int k=0;k<N_DESC;k++) publish_new(0);
    drive_cycle();
    for(int k=0;k<N_DESC;k++) drive_cycle(0,-1,0,0);
    drive_cycle(1,-1,0,-1,candidate(mon.TX)); // no same-edge return-funded allocation
    drive_cycle(1); delayed_id=int'(admit.desc); drive_cycle(); drive_cycle(); drive_cycle(0,delayed_id,1);
    // Random publication is independent of allocation, and TX returns are delayed.
    for(int k=0;k<16000;k++) begin
        int id,cq,pq,ret;
        id=(draw()%4!=0)?candidate(mon.RX):-1;
        cq=int'(draw()%N_Q); pq=int'(draw()%N_Q);
        if(mon.size[pq]==0 || draw()%4==0) pq=-1;
        ret=(draw()%3==0)?candidate(mon.TX):-1;
        drive_cycle(draw()%3!=0,id,cq,pq,ret,k%977==976);
    end
    // Reset with active publication/dispatch, then immediate reuse.
    drive_cycle(0,-1,0,-1,-1,1);
    publish_new(0); drive_cycle(1);
    drive_cycle(0,int'(admit.desc),0,0,-1,1);
    publish_new(0);
    mon.report();
    $c("VerilatedCov::write(\"coverage.dat\");");
    $display("TM_QUEUE_DV_PASS"); $finish;
end
endmodule
