// FP-TX public-action history, independent of production cursors and free counts.
module tx_formal #(
`include "tm_parameters.svh"
)(input logic clk, rst_n, request, sink_ready,
  input logic [15:0] length_input, tag_input,
  input logic [DESC_ID_W-1:0] descriptor_input,
  input logic qid_input,
  input logic [8*CELL_ID_W-1:0] chain_input,
  input logic [63:0] read_word,
  input logic [CELL_ID_W-1:0] reused_link);
`include "tm_types.svh"
localparam integer CW=CELL_BYTES/8;
logic history=0;
logic [1:0] startup=0;
logic initialized=0, live=0;
logic [8*CELL_ID_W-1:0] owned_chain;
logic ever_work=0, reset_after_work=0, reset_pending_seen=0;
logic [MEM_RD_LATENCY-1:0] physical_valid='0, live_valid='0;
logic [63:0] physical_data[MEM_RD_LATENCY];
// Finite event counters retain headroom for the first illegal credit/read edge.
localparam integer SLOT_W=$clog2(TX_FIFO_DEPTH+2);
localparam integer TX_MONITOR_BEAT_W=$clog2((MAX_PACKET_BYTES+7)/8+2);
logic [SLOT_W-1:0] slots=0, arrived=0;
logic [TX_MONITOR_BEAT_W-1:0] issued=0, retired=0, total=0;
logic [TX_MONITOR_BEAT_W-1:0] response_index[MEM_RD_LATENCY];
logic [15:0] length, tag;
desc_id_t descriptor;
qid_t qid;
logic [N_CELL-1:0] returned='0;
dispatch_t dispatch;
ram_read_t read_req;
ram_response_t response;
cell_return_t cell_return;
tx_done_t done;
cell_id_t link_cell, next_cell;
logic valid, dispatch_ready, idle;
beat_t beat;
logic fire, arrival, held=0;
beat_t held_beat;
function automatic cell_id_t chain(input integer index);
    return owned_chain[(index%8)*CELL_ID_W +: CELL_ID_W];
endfunction
assign fire=valid && sink_ready;
assign arrival=live_valid[MEM_RD_LATENCY-1] && response.valid;
assign response.valid=physical_valid[MEM_RD_LATENCY-1];
assign response.data=physical_data[MEM_RD_LATENCY-1];
always_comb begin
    dispatch='0;
    dispatch.valid=request && rst_n && initialized;
    dispatch.desc=descriptor_input;
    dispatch.qid=qid_t'(qid_input);
    dispatch.info='{head:cell_id_t'(chain_input[0 +: CELL_ID_W]),ncell:cell_count_t'((int'(length_input)+CELL_BYTES-1)/CELL_BYTES),
        length:length_input,qid:qid_t'(qid_input),tag:tag_input,source:'0};
    next_cell=cell_id_t'(reused_link);
    for(int i=0;i<7;i++)
        if(link_cell==chain(i) && !returned[link_cell] && (i+1)*CELL_BYTES<int'(length)) next_cell=chain(i+1);
end
tm_tx_api #(.N_RX(N_RX),.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.CELL_BYTES(CELL_BYTES),
 .MAX_PACKET_BYTES(MAX_PACKET_BYTES),.MEM_RD_LATENCY(MEM_RD_LATENCY),.TX_FIFO_DEPTH(TX_FIFO_DEPTH)) dut(
 .clk,.rst_n,.dispatch,.dispatch_ready,.read_req,.response,.link_cell,.next_cell,
 .m_valid(valid),.m_beat(beat),.m_ready(sink_ready),.cell_return,.tx_done(done),.idle);
always_ff @(posedge clk) begin
    history<=1;
    if(dispatch.valid)for(int i=0;i<8;i++)begin
        assume(int'(cell_id_t'(chain_input[i*CELL_ID_W +: CELL_ID_W]))<N_CELL);
        for(int j=0;j<i;j++) assume(chain_input[i*CELL_ID_W +: CELL_ID_W]!=chain_input[j*CELL_ID_W +: CELL_ID_W]);
    end
    if(startup<2)begin startup<=startup+1;assume(!rst_n);end
    if(dispatch.valid)begin
        assume(dispatch_ready);
        assume(length_input>0 && int'(length_input)<=MAX_PACKET_BYTES);
        assume(int'(descriptor_input)<N_DESC);
    end
    physical_valid<=(physical_valid<<1)|MEM_RD_LATENCY'(read_req.valid);
    physical_data[0]<=read_word;
    for(int i=1;i<MEM_RD_LATENCY;i++) physical_data[i]<=physical_data[i-1];
    if(dispatch.valid) ever_work<=1;
    if(!rst_n && ever_work) reset_after_work<=1;
    c_reset_pending:cover(!rst_n && slots>0 && |physical_valid);
    if(!rst_n && slots>0) reset_pending_seen<=1;
    c_reset_reuse:cover(reset_pending_seen && dispatch.valid && tag_input==tag && descriptor_input==descriptor && chain_input[0 +: CELL_ID_W]==chain(0));
    c_new_chain:cover(ever_work && dispatch.valid && chain_input!=owned_chain);
    if(!rst_n)begin
        initialized<=0;live<=0;slots<=0;arrived<=0;issued<=0;retired<=0;total<=0;
        live_valid<='0;returned<='0;held<=0;
        a_reset:assert(!valid && !read_req.valid && !cell_return.valid && !done.valid);
    end else begin
        initialized<=1;
        a_response_contract:assert((live_valid & ~physical_valid)==0);
        a_inactive_empty:assert(live || slots==0);
        a_initialized_history:assert(!initialized || history);
        a_credit:assert(slots+int'(read_req.valid)-int'(fire)<=TX_FIFO_DEPTH);
        a_nonnegative:assert(arrived<=slots);
        a_slot_delta:assert(int'(slots)+int'(read_req.valid)-int'(fire)>=0);
        a_arrival_delta:assert(int'(arrived)+int'(arrival)-int'(fire)>=0 && int'(arrived)+int'(arrival)-int'(fire)<=TX_FIFO_DEPTH);
        a_outstanding_delta:assert(int'(slots)-int'(arrived)+int'(read_req.valid)-int'(arrival)>=0);
        a_arrival_space:assert(!arrival || arrived<TX_FIFO_DEPTH || fire);
        a_output_arrived:assert(!valid || (arrived>0 && live));
        a_validity:assert(valid==(arrived>0));
        a_idle:assert(idle==(!live && slots==0));
        a_dispatch_ready:assert(dispatch_ready==idle);
        if(held)begin a_stability:assert(valid && beat==held_beat);end
        held<=valid && !sink_ready;held_beat<=beat;
        a_retirement:assert(cell_return.valid==(fire && (retired%CW==CW-1 || retired+1==total)));
        a_completion:assert(done.valid==(fire && retired+1==total));
        if(cell_return.valid)begin
            a_return_id:assert(cell_return.id==chain(retired/CW));
            a_return_owner:assert(!returned[cell_return.id] && cell_return.desc==descriptor && cell_return.qid==qid);
            returned[cell_return.id]<=1;
        end
        if(done.valid)begin
            a_done_owner:assert(done.desc==descriptor && done.qid==qid && done.length==length);
            live<=0;
        end
        if(valid)begin
            a_last:assert(beat.last==(retired+1==total));
            a_keep:assert(beat.keep==(retired+1<total || length%8==0 ? 8'hff : 8'((1<<(length%8))-1)));
            a_user:assert(beat.user==({56'b0,8'(qid)} | (64'(length)<<8) | (64'(tag)<<24)));
        end
        if(read_req.valid)begin
            a_read_owner:assert(live && issued<total);
            a_read_address:assert(read_req.addr==ADDR_W'(int'(chain(issued/CW))*CW+issued%CW));
            a_no_read_after_return:assert(!returned[chain(issued/CW)]);
            issued<=issued+1;
        end
        if(live && issued==total)begin a_tail:assert(link_cell==chain((total-1)/CW));end
        if(fire)retired<=retired+1;
        slots<=slots+int'(read_req.valid)-int'(fire);
        arrived<=arrived+int'(arrival)-int'(fire);
        response_index[0]<=issued;
        for(int j=1;j<MEM_RD_LATENCY;j++) response_index[j]<=response_index[j-1];
        live_valid<=(live_valid<<1)|MEM_RD_LATENCY'(read_req.valid);
        if(dispatch.valid)begin
            owned_chain<=chain_input;live<=1;issued<=0;retired<=0;length<=length_input;tag<=tag_input;
            total<=(int'(length_input)+7)/8;descriptor<=descriptor_input;qid<=qid_t'(qid_input);returned<='0;
        end
        // Binding lemmas relate production storage to independently observed event totals.
        a_buffer_mapping:assert(int'(dut.buffered)==arrived);
        a_outstanding_mapping:assert(int'(dut.outstanding)==slots-arrived);
        a_live_mapping:assert(dut.active==live);
        if(live)begin
            a_length_domain:assert(length>0 && int'(length)<=MAX_PACKET_BYTES && total==(int'(length)+7)/8 && retired<total);
            a_packet_mapping:assert(dut.packet.info.length==length && dut.packet.info.tag==tag && dut.packet.qid==qid && dut.packet.desc==descriptor && dut.packet.info.source==0 && dut.packet.info.qid==qid && dut.packet.info.head==chain(0) && int'(dut.packet.info.ncell)==(int'(length)+CELL_BYTES-1)/CELL_BYTES);
            a_fetch_cell:assert(dut.fetch_cell==chain(issued==total ? (total-1)/CW : issued/CW));
            a_fetch_word:assert(int'(dut.fetch_word)==(issued==total ? 0 : issued%CW));
            a_fetch_bytes:assert(int'(dut.fetch_bytes)==(issued==total ? 0 : int'(length)-issued*8));
            a_fetch_cells:assert(int'(dut.fetch_cells)==(issued==total ? 0 : (int'(length)+CELL_BYTES-1)/CELL_BYTES-issued/CW));
        end
        a_pending_count:assert(slots-arrived==$countones(live_valid));
        a_slot_bound:assert(slots<=TX_FIFO_DEPTH);
        a_pending_mapping:assert(dut.pending_valid==live_valid);
        a_pointer_bounds:assert(int'(dut.rd_ptr)<TX_FIFO_DEPTH && int'(dut.wr_ptr)<TX_FIFO_DEPTH);
        a_pointer_distance:assert(int'(dut.wr_ptr)==(int'(dut.rd_ptr)+arrived)%TX_FIFO_DEPTH);
        a_count_order:assert(retired>=0 && retired<=issued && issued<=total && total<=(MAX_PACKET_BYTES+7)/8 && slots==issued-retired);
        c_full_credit:cover(slots==TX_FIFO_DEPTH);
        c_full_pending:cover(slots==TX_FIFO_DEPTH && |live_valid);
        c_pending_stall:cover(|live_valid && !sink_ready);
        c_exchange:cover(slots==TX_FIFO_DEPTH && arrival && read_req.valid && fire);
        c_final_hold:cover(valid && beat.last && !sink_ready);
        c_returned_link_change:cover(live && |returned && reused_link!=chain(1));
        c_completed:cover(done.valid);
    end
end
        for(genvar j=0;j<MEM_RD_LATENCY;j++)begin:g_pending
            always_ff @(posedge clk) if(rst_n && live_valid[j])begin
                integer newer;
                newer=0;
                for(int n=0;n<j;n++) newer+=int'(live_valid[n]);
                a_pending_index:assert(response_index[j]==issued-1-newer);
                a_pending_cell:assert(dut.pending_tag[j].cell_id==chain(response_index[j]/CW));
                a_pending_cell_last:assert(dut.pending_tag[j].cell_last==(response_index[j]%CW==CW-1 || response_index[j]+1==total));
                a_pending_last:assert(dut.pending_tag[j].packet_last==(response_index[j]+1==total));
                a_pending_keep:assert(dut.pending_tag[j].keep==(response_index[j]+1<total || length%8==0 ? 8'hff : 8'((1<<(length%8))-1)));
            end
        end
        for(genvar k=0;k<TX_FIFO_DEPTH;k++)begin:g_fifo
            always_ff @(posedge clk) if(rst_n && k<arrived)begin
                a_fifo_cell:assert(dut.fifo[(int'(dut.rd_ptr)+k)%TX_FIFO_DEPTH].cell_id==chain((retired+k)/CW));
                a_fifo_cell_last:assert(dut.fifo[(int'(dut.rd_ptr)+k)%TX_FIFO_DEPTH].cell_last==((retired+k)%CW==CW-1 || retired+k+1==total));
                a_fifo_last:assert(dut.fifo[(int'(dut.rd_ptr)+k)%TX_FIFO_DEPTH].beat.last==(retired+k+1==total));
                a_fifo_keep:assert(dut.fifo[(int'(dut.rd_ptr)+k)%TX_FIFO_DEPTH].beat.keep==(retired+k+1<total || length%8==0 ? 8'hff : 8'((1<<(length%8))-1)));
                a_fifo_user:assert(dut.fifo[(int'(dut.rd_ptr)+k)%TX_FIFO_DEPTH].beat.user==({56'b0,8'(qid)} | (64'(length)<<8) | (64'(tag)<<24)));
            end
        end

for(genvar i=0;i<8;i++)begin:g_returned
    always_ff @(posedge clk) if(rst_n && live)begin
        a_return_mask:assert(returned[chain(i)]==(i*CW<total && retired>=((i+1)*CW<total ? (i+1)*CW : total)));
    end
end
for(genvar i=0;i<8;i++)begin:g_owned_chain
    always_ff @(posedge clk) if(rst_n && live)begin
        a_owned_range:assert(int'(chain(i))<N_CELL);
    end
    for(genvar j=0;j<i;j++)begin:g_distinct
        always_ff @(posedge clk) if(rst_n && live)begin
            a_owned_distinct:assert(chain(i)!=chain(j));
        end
    end
end
endmodule
