// Preparation assertions over sampled public API actions. No DUT proof is claimed.
module memory_tx_obligations #(
    parameter int LATENCY=1, DEPTH=4, CELL_BYTES=16
)(
    input logic clk, sample_enable, rst_n,
    input logic dispatch_valid,
    input logic [31:0] dispatch_length,
    input logic read_valid, response_valid,
    input logic output_valid, output_ready, output_last,
    input logic [7:0] output_keep,
    input logic cell_return_valid, done_valid
);
    int slots=0, arrived=0, remaining=0, word_in_cell=0;
    logic [LATENCY-1:0] response_pipe='0;
    logic fire, final_packet, final_cell;
    always_comb begin
        fire=output_valid && output_ready;
        final_packet=remaining>0 && remaining<=8;
        final_cell=final_packet || word_in_cell==CELL_BYTES/8-1;
    end
    always_ff @(posedge clk) begin
        if(sample_enable)begin
            c_reset_pending:cover(!rst_n && slots>0);
            if(!rst_n)begin
                slots<=0;arrived<=0;remaining<=0;word_in_cell<=0;response_pipe<='0;
                a_reset:assert(!output_valid && !cell_return_valid && !done_valid);
            end else begin
                a_response_due:assert(response_valid==response_pipe[LATENCY-1]);
                a_credit:assert(slots+int'(read_valid)-int'(fire)<=DEPTH);
                a_credit_nonnegative:assert(slots+int'(read_valid)-int'(fire)>=0);
                a_output_arrived:assert(!output_valid || (arrived>0 && remaining>0));
                a_done:assert(done_valid==(fire && final_packet));
                a_cell_return:assert(cell_return_valid==(fire && final_cell));
                if(output_valid)begin
                    a_last:assert(output_last==final_packet);
                    a_keep:assert(output_keep==(remaining>=8?8'hff:8'((1<<remaining)-1)));
                end
                if(dispatch_valid)begin
                    a_dispatch_empty:assert(slots==0 && remaining==0);
                    a_dispatch_length:assert(dispatch_length>0);
                    remaining<=int'(dispatch_length);word_in_cell<=0;
                end else if(fire)begin
                    remaining<=remaining>8?remaining-8:0;
                    word_in_cell<=final_cell?0:word_in_cell+1;
                end
                response_pipe<=(response_pipe<<1)|LATENCY'(read_valid);
                slots<=slots+int'(read_valid)-int'(fire);
                arrived<=arrived+int'(response_valid)-int'(fire);
                c_full_pending:cover(slots==DEPTH && |response_pipe);
                c_exchange:cover(slots==DEPTH && response_valid && read_valid && fire);
                c_final_hold:cover(output_valid && !output_ready && final_packet);
                c_recovered:cover(done_valid && slots==1);
            end
        end
    end
endmodule
