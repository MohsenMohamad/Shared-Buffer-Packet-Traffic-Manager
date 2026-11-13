// Illegal empty dispatch diagnostics, isolated from the legal-action model.
module queues_empty_tb #(
`include "tm_parameters.svh"
) ();
`include "tm_types.svh"
logic clk=0, rst_n=0;
always #5 clk=~clk;
commit_t commit='0;
dispatch_t dispatch='0;
logic [N_Q*DESC_ID_W-1:0] heads,tails;
logic [N_Q*DESC_COUNT_W-1:0] counts;
desc_link_write_t next_write;
desc_id_t read_id='0, old_head_next;
logic invariant_error;
`define QPARAM .N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),.MAX_PACKET_BYTES(MAX_PACKET_BYTES)
tm_queue_ctrl_api #(`QPARAM) dut(.*);
tm_desc_links #(`QPARAM) links(.clk(clk),.write_req(next_write),.read_id(read_id),.read_next(old_head_next));
`undef QPARAM
initial begin
    for(int q=0;q<N_Q;q++) for(int publish=0;publish<2;publish++) begin
        @(negedge clk); rst_n=0; commit='0; dispatch='0;
        @(posedge clk); #1;
        assert(counts=='0 && !invariant_error) else $fatal(1,"QUEUE_DV_EMPTY_RESET");
        @(negedge clk); rst_n=1;
        commit.valid=1'(publish); commit.qid=Q_ID_W'(q); commit.desc=DESC_ID_W'(q%N_DESC);
        dispatch.valid=1; dispatch.qid=Q_ID_W'(q); dispatch.desc=commit.desc;
        #1;
        assert(!next_write.valid) else $fatal(1,"QUEUE_DV_EMPTY_LINK");
        @(posedge clk); #1;
        assert(invariant_error && int'(counts[q*DESC_COUNT_W+:DESC_COUNT_W])==publish)
            else $fatal(1,"QUEUE_DV_EMPTY_GUARD");
        if(publish!=0) begin
            assert(heads[q*DESC_ID_W+:DESC_ID_W]==commit.desc && tails[q*DESC_ID_W+:DESC_ID_W]==commit.desc)
                else $fatal(1,"QUEUE_DV_EMPTY_BYPASS");
            @(negedge clk); commit='0; // now the old published head may dispatch
            @(posedge clk); #1;
            assert(counts=='0 && invariant_error) else $fatal(1,"QUEUE_DV_EMPTY_NEXT_EDGE");
        end
    end
    $display("TM_QUEUE_DV_EMPTY_PASS"); $finish;
end
endmodule
