// Malformed dispatch diagnostics are isolated from the legal-operation monitor.
module queues_dispatch_guard_tb #(
`include "tm_parameters.svh"
) ();
`include "tm_types.svh"
logic clk=0, rst_n=0;
always #5 clk=~clk;
commit_t commit='0;
dispatch_t dispatch='0;
logic [N_Q*DESC_ID_W-1:0] heads, tails;
logic [N_Q*DESC_COUNT_W-1:0] counts;
desc_link_write_t next_write;
desc_id_t read_id='0, old_head_next;
logic invariant_error;
`define GUARD_PARAMS .N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),.MAX_PACKET_BYTES(MAX_PACKET_BYTES),.DESC_ID_W(DESC_ID_W),.DESC_COUNT_W(DESC_COUNT_W)
tm_queue_ctrl_api #(`GUARD_PARAMS) dut(.*);
tm_desc_links #(`GUARD_PARAMS) links(.clk(clk),.write_req(next_write),.read_id(read_id),.read_next(old_head_next));
`undef GUARD_PARAMS

localparam int HEAD_ID=0, TAIL_ID=2, APPEND_ID=3;
// A free ID differing from head only in its highest supported ID bit catches
// truncated comparisons; the other queue also exercises the maximum valid ID.
localparam int OTHER_ID=N_DESC-1, UNQUEUED_ID=N_DESC/2;
// Expected state comes only from the fixture's successful publication events.
int fifo[N_Q][N_DESC], size[N_Q];
bit expected_error=0;
bit [N_DESC-1:0] known_links='0;
desc_id_t expected_link[N_DESC];
int scenario_hits[N_Q][2][3][3]; // qid x singleton/long x wrong-ID source x publication scope
int rejected=0, sticky_checks=0, resets=0, publications=0;

task automatic check_queries;
    for(int q=0;q<N_Q;q++) begin
        assert(int'(counts[q*DESC_COUNT_W+:DESC_COUNT_W])==size[q])
            else $fatal(1,"QUEUE_DV_WRONG_DESC_COUNT q=%0d",q);
        if(size[q]>0) begin
            assert(int'(heads[q*DESC_ID_W+:DESC_ID_W])==fifo[q][0])
                else $fatal(1,"QUEUE_DV_WRONG_DESC_HEAD q=%0d",q);
            assert(int'(tails[q*DESC_ID_W+:DESC_ID_W])==fifo[q][size[q]-1])
                else $fatal(1,"QUEUE_DV_WRONG_DESC_TAIL q=%0d",q);
        end
    end
endtask

task automatic check_links;
    for(int id=0;id<N_DESC;id++) if(known_links[id]) begin
        read_id=DESC_ID_W'(id);
        #1;
        assert(old_head_next==expected_link[id])
            else $fatal(1,"QUEUE_DV_WRONG_DESC_LINK_DATA id=%0d",id);
    end
endtask

task automatic reset_case;
    @(negedge clk);
    rst_n=0; commit='0; dispatch='0;
    @(posedge clk); #1;
    for(int q=0;q<N_Q;q++) size[q]=0;
    expected_error=0;
    assert(!invariant_error && counts=='0 && !next_write.valid)
        else $fatal(1,"QUEUE_DV_WRONG_DESC_RESET");
    // The physical link array is unreset; saved expected values survive reset.
    check_links();
    resets++;
endtask

task automatic sample_cycle(input int publish_q=-1, publish_id=0,
                            wrong_q=-1, wrong_id=0);
    desc_link_write_t expected_write;
    int depth_bin, id_bin, publication_bin;
    @(negedge clk);
    rst_n=1; commit='0; dispatch='0;
    if(publish_q>=0) begin
        assert(publish_q<N_Q && publish_id>=0 && publish_id<N_DESC)
            else $fatal(1,"QUEUE_DV_GUARD_PUBLICATION_RANGE");
        for(int q=0;q<N_Q;q++) for(int k=0;k<size[q];k++)
            assert(fifo[q][k]!=publish_id) else $fatal(1,"QUEUE_DV_GUARD_DUPLICATE_PUBLICATION");
        commit.valid=1; commit.qid=Q_ID_W'(publish_q); commit.desc=DESC_ID_W'(publish_id);
        commit.info.qid=commit.qid;
    end
    if(wrong_q>=0) begin
        assert(wrong_q<N_Q && size[wrong_q]>0 && wrong_id>=0 && wrong_id<N_DESC && wrong_id!=fifo[wrong_q][0])
            else $fatal(1,"QUEUE_DV_GUARD_STIMULUS");
        dispatch.valid=1; dispatch.qid=Q_ID_W'(wrong_q); dispatch.desc=DESC_ID_W'(wrong_id);
        // No dispatch descriptor or expected head is copied from DUT queries.
        read_id=DESC_ID_W'(fifo[wrong_q][0]);
    end
    #1;
    check_queries();
    expected_write='0;
    if(commit.valid && size[publish_q]>0) begin
        expected_write.valid=1;
        expected_write.id=DESC_ID_W'(fifo[publish_q][size[publish_q]-1]);
        expected_write.next_id=DESC_ID_W'(publish_id);
    end
    assert(next_write.valid==expected_write.valid)
        else $fatal(1,"QUEUE_DV_WRONG_DESC_LINK_PORT");
    if(expected_write.valid) assert(next_write.id==expected_write.id && next_write.next_id==expected_write.next_id)
        else $fatal(1,"QUEUE_DV_WRONG_DESC_LINK_PORT");
    @(posedge clk);
    // Classify sampled API levels against the independent PRE-state.
    if(dispatch.valid) begin
        depth_bin=int'(size[dispatch.qid]>1);
        id_bin=int'(dispatch.desc)==UNQUEUED_ID ? 0 : int'(dispatch.desc)==OTHER_ID ? 1 : 2;
        publication_bin=commit.valid ? (commit.qid==dispatch.qid ? 1 : 2) : 0;
        $display("QUEUE_DV_WRONG_DESC_INJECT q=%0d count=%0d head=%0d wrong=%0d publication=%0d",
                 dispatch.qid,size[dispatch.qid],fifo[dispatch.qid][0],dispatch.desc,publication_bin);
        expected_error=1;
    end
    if(commit.valid) begin
        if(size[commit.qid]>0) begin
            expected_link[fifo[commit.qid][size[commit.qid]-1]]=commit.desc;
            known_links[fifo[commit.qid][size[commit.qid]-1]]=1;
        end
        fifo[commit.qid][size[commit.qid]]=int'(commit.desc);
        size[commit.qid]++;
        publications++;
    end
    #1;
    if(expected_error) assert(invariant_error)
        else $fatal(1,"QUEUE_DV_WRONG_DESC_ERROR");
    else assert(!invariant_error) else $fatal(1,"QUEUE_DV_GUARD_UNEXPECTED_ERROR");
    check_queries();
    if(dispatch.valid) begin
        scenario_hits[dispatch.qid][depth_bin][id_bin][publication_bin]++;
        rejected++;
    end else if(expected_error) sticky_checks++;
    // Stop all actions before probing links across additional idle clock edges.
    @(negedge clk); commit='0; dispatch='0;
    check_links();
    check_queries();
endtask

initial begin
    int fd, other_q, wrong_id, publish_q;
    if($test$plusargs("TRACE")) begin $dumpfile("wave.vcd"); $dumpvars(0,queues_dispatch_guard_tb); end
    for(int q=0;q<N_Q;q++) begin
        other_q=(q+1)%N_Q;
        for(int depth=0;depth<2;depth++) for(int kind=0;kind<3;kind++) begin
            if(depth==0 && kind==2) continue; // a singleton has no queued non-head ID
            for(int publication=0;publication<3;publication++) begin
                reset_case();
                sample_cycle(q,HEAD_ID);
                if(depth==1) begin sample_cycle(q,1); sample_cycle(q,TAIL_ID); end
                sample_cycle(other_q,OTHER_ID);
                wrong_id=kind==0 ? UNQUEUED_ID : kind==1 ? OTHER_ID : TAIL_ID;
                publish_q=publication==0 ? -1 : publication==1 ? q : other_q;
                sample_cycle(publish_q,APPEND_ID,q,wrong_id);
                sample_cycle(); sample_cycle(); // sticky through idle cycles
                reset_case(); // error clears and no queue remains published
            end
        end
    end
    for(int q=0;q<N_Q;q++) for(int depth=0;depth<2;depth++)
        for(int kind=0;kind<3;kind++) for(int publication=0;publication<3;publication++)
            if(!(depth==0 && kind==2))
                assert(scenario_hits[q][depth][kind][publication]==1)
                    else $fatal(1,"QUEUE_DV_WRONG_DESC_COVERAGE");
    assert(rejected==15*N_Q && sticky_checks==2*rejected && resets==2*rejected)
        else $fatal(1,"QUEUE_DV_WRONG_DESC_COVERAGE_TOTAL");
    fd=$fopen("dispatch-guard-coverage.json","w");
    $fdisplay(fd,"{\"rejected\":%0d,\"sticky_checks\":%0d,\"resets\":%0d,\"publications\":%0d,\"bins\":[",rejected,sticky_checks,resets,publications);
    for(int q=0;q<N_Q;q++) for(int depth=0;depth<2;depth++)
        for(int kind=0;kind<3;kind++) for(int publication=0;publication<3;publication++)
            $fdisplay(fd,"%s{\"qid\":%0d,\"depth\":%0d,\"wrong_kind\":%0d,\"publication\":%0d,\"hits\":%0d}",
                      (q==0 && depth==0 && kind==0 && publication==0)?"":",",q,depth,kind,publication,scenario_hits[q][depth][kind][publication]);
    $fdisplay(fd,"]}"); $fclose(fd);
    $c("VerilatedCov::write(\"coverage.dat\");");
    $display("TM_QUEUE_DISPATCH_GUARD_PASS rejected=%0d sticky=%0d resets=%0d",rejected,sticky_checks,resets);
    $finish;
end
endmodule
