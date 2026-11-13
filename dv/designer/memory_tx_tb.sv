// Designer smoke only; independent P05 qualification belongs to its DV PR.
module memory_tx_tb import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) ();
localparam integer CELL_WORDS=CELL_BYTES/8;
logic clk=0;
always #5 clk=~clk;
logic rst_n=0;
ram_write_t write_req;
ram_read_t read_req;
ram_response_t response;
cell_link_write_t cell_write;
desc_link_write_t queue_write;
desc_write_t info_write;
cell_id_t link_cell, next_cell, abort_cell, abort_next;
logic [N_Q*DESC_ID_W-1:0] queue_heads;
logic [N_Q*DESC_INFO_W-1:0] head_info;
desc_id_t queue_head, queue_next;
dispatch_t dispatch;
logic dispatch_ready, m_valid, m_ready, idle;
beat_t m_beat;
cell_return_t cell_return;
tx_done_t tx_done;
`define PARAMS .DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES), \
    .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES), \
    .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY), .TX_FIFO_DEPTH(TX_FIFO_DEPTH)
tm_packet_ram_api #(`PARAMS) ram (.clk, .write_req, .read_req, .response);
tm_metadata_api #(`PARAMS) metadata (.clk, .cell_write, .queue_write, .info_write,
    .tx_cell(link_cell), .tx_next(next_cell), .abort_cell, .abort_next,
    .queue_heads, .head_info, .queue_head, .queue_next);
tm_tx_api #(`PARAMS) tx (.clk, .rst_n, .dispatch, .dispatch_ready, .read_req,
    .response, .link_cell, .next_cell, .m_valid, .m_ready, .m_beat,
    .cell_return, .tx_done, .idle);
`undef PARAMS

function automatic cell_id_t chain_cell(input int ordinal);
    return cell_id_t'((ordinal*5+3)%N_CELL);
endfunction
function automatic logic [63:0] pattern(input int ordinal, input int salt);
    logic [63:0] value;
    for (int b=0; b<8; b++) value[b*8 +: 8]=8'(ordinal*8+b+salt);
    return value;
endfunction
function automatic logic [63:0] packet_user(input int length);
    output_user_t user_value;
    user_value='0;
    user_value.qid=8'(N_Q-1);
    user_value.length=16'(length);
    user_value.tag=16'habcd;
    user_value.source=8'(N_RX-1);
    return user_value;
endfunction

int edge_number=0, dispatch_edge, first_valid_edge, previous_accept;
int expected_length=0, expected_salt=0, sent=0, read_ordinal=0, credits=0;
int full_pending_hits=0, triple_hits=0, cells_freed=0, packets_done=0;
int max_first_valid=0, max_continuous_gap=0;
bit packet_live=0, held=0, continuous=0;
beat_t held_beat;
logic [63:0] memory_model [N_CELL*CELL_WORDS];
logic [MEM_RD_LATENCY-1:0] due_valid='0;
logic [63:0] due_data [MEM_RD_LATENCY];
bit captured [N_CELL];

// Sample actual requests/output at the API edge, independently of TX state.
always @(posedge clk) begin
    edge_number++;
    if (edge_number>MEM_RD_LATENCY) begin
        assert (response.valid==due_valid[MEM_RD_LATENCY-1]) else $fatal(1,"RAM latency");
        if (response.valid) assert (response.data==due_data[MEM_RD_LATENCY-1])
            else $fatal(1,"RAM data");
    end
    for (int i=MEM_RD_LATENCY-1; i>0; i--) begin
        due_valid[i]=due_valid[i-1];
        due_data[i]=due_data[i-1];
    end
    due_valid[0]=read_req.valid;
    if (read_req.valid) due_data[0]=memory_model[read_req.addr];
    if (write_req.valid) begin
        assert (!(read_req.valid && write_req.addr==read_req.addr)) else $fatal(1,"collision");
        memory_model[write_req.addr]=write_req.data;
    end
    if (!rst_n) begin
        assert (!m_valid && !read_req.valid && !cell_return.valid && !tx_done.valid && !dispatch_ready)
            else $fatal(1,"reset controls");
        packet_live=0;
        held=0;
        sent=0;
        read_ordinal=0;
        credits=0;
        foreach (captured[c]) captured[c]=0;
    end else begin
        if (dispatch.valid) begin
            assert (dispatch_ready && !packet_live) else $fatal(1,"dispatch");
            packet_live=1;
            dispatch_edge=edge_number;
            first_valid_edge=-1;
            previous_accept=-1;
            sent=0;
            read_ordinal=0;
            foreach (captured[c]) captured[c]=0;
        end
        if (held) assert (m_valid && m_beat==held_beat) else $fatal(1,"stalled fields");
        held=m_valid && !m_ready;
        held_beat=m_beat;
        if (read_req.valid) begin
            assert (packet_live) else $fatal(1,"read without packet");
            assert (int'(read_req.addr)==int'(chain_cell(read_ordinal/CELL_WORDS))*CELL_WORDS+read_ordinal%CELL_WORDS)
                else $fatal(1,"read order");
            if (read_ordinal%CELL_WORDS==0 && (read_ordinal/CELL_WORDS+1)*CELL_BYTES<expected_length) begin
                assert (next_cell==chain_cell(read_ordinal/CELL_WORDS+1)) else $fatal(1,"next link");
                captured[chain_cell(read_ordinal/CELL_WORDS)]=1;
            end
            read_ordinal++;
        end
        if (m_valid && first_valid_edge<0) begin
            first_valid_edge=edge_number;
            if (first_valid_edge-dispatch_edge>max_first_valid)
                max_first_valid=first_valid_edge-dispatch_edge;
            assert (first_valid_edge-dispatch_edge<=MEM_RD_LATENCY+4) else $fatal(1,"first valid");
        end
        if (m_valid && m_ready) begin : check_output
            int left;
            bit final_word, boundary;
            logic [7:0] keep_mask;
            logic [63:0] expected_data;
            assert (packet_live) else $fatal(1,"output without packet");
            left=expected_length-sent*8;
            final_word=left<=8;
            boundary=final_word || sent%CELL_WORDS==CELL_WORDS-1;
            keep_mask=left>=8 ? 8'hff : 8'((1<<left)-1);
            expected_data=pattern(sent,expected_salt);
            for (int b=0; b<8; b++) if (keep_mask[b])
                assert (m_beat.data[b*8 +: 8]==expected_data[b*8 +: 8]) else $fatal(1,"output byte");
            assert (m_beat.keep==keep_mask && m_beat.last==final_word && m_beat.user==packet_user(expected_length))
                else $fatal(1,"framing/user");
            assert (cell_return.valid==boundary && tx_done.valid==final_word) else $fatal(1,"retirement edge");
            if (boundary) begin
                assert (cell_return.id==chain_cell(sent/CELL_WORDS) && !cell_return.abort_source &&
                        cell_return.desc==desc_id_t'(2) && cell_return.qid==qid_t'(N_Q-1))
                    else $fatal(1,"return owner");
                if (!final_word) assert (captured[cell_return.id]) else $fatal(1,"uncaptured link");
                cells_freed++;
            end
            if (continuous && previous_accept>=0) begin
                if (edge_number-previous_accept>max_continuous_gap)
                    max_continuous_gap=edge_number-previous_accept;
                assert (edge_number==previous_accept+1) else $fatal(1,"within-packet bubble");
            end
            previous_accept=edge_number;
            sent++;
            if (final_word) begin
                assert (tx_done.desc==desc_id_t'(2) && tx_done.qid==qid_t'(N_Q-1) && tx_done.length==16'(expected_length))
                    else $fatal(1,"completion fields");
                packet_live=0;
                packets_done++;
            end
        end else assert (!cell_return.valid && !tx_done.valid) else $fatal(1,"early return");
        credits+=int'(read_req.valid)-int'(m_valid && m_ready);
        assert (credits>=0 && credits<=TX_FIFO_DEPTH) else $fatal(1,"credit overflow");
        if (credits==TX_FIFO_DEPTH && !m_ready && read_req.valid) full_pending_hits++;
        if (read_req.valid && response.valid && m_valid && m_ready) triple_hits++;
    end
end

task automatic cycle;
    @(posedge clk);
    #1;
    @(negedge clk);
endtask

task automatic reset_tx;
    rst_n=0;
    dispatch='0;
    write_req='0;
    cell_write='0;
    info_write='0;
    queue_write='0;
    m_ready=0;
    cycle(); cycle();
    rst_n=1;
    cycle();
    assert (idle && dispatch_ready) else $fatal(1,"reset not idle");
endtask

task automatic load_packet(input int length, input int salt);
    expected_length=length;
    expected_salt=salt;
    for (int c=0; c<(length+CELL_BYTES-1)/CELL_BYTES-1; c++) begin
        cell_write='{valid:1'b1,id:chain_cell(c),next_id:chain_cell(c+1)};
        cycle();
    end
    cell_write='0;
    for (int w=0; w<(length+7)/8; w++) begin
        write_req='{valid:1'b1,addr:ADDR_W'(int'(chain_cell(w/CELL_WORDS))*CELL_WORDS+w%CELL_WORDS),data:pattern(w,salt)};
        cycle();
    end
    write_req='0;
    info_write='0;
    info_write.valid=1;
    info_write.id=desc_id_t'(2);
    info_write.info='{head:chain_cell(0),ncell:cell_count_t'((length+CELL_BYTES-1)/CELL_BYTES),
        length:16'(length),qid:qid_t'(N_Q-1),tag:16'habcd,source:port_id_t'(N_RX-1)};
    queue_heads='0;
    for (int q=0; q<N_Q; q++) queue_heads[q*DESC_ID_W +: DESC_ID_W]=desc_id_t'(2);
    cycle();
    for (int q=0; q<N_Q; q++)
        assert (head_info[q*DESC_INFO_W +: DESC_INFO_W]==info_write.info) else $fatal(1,"head info mux");
    info_write.valid=0;
endtask

task automatic start_packet;
    assert (dispatch_ready) else $fatal(1,"busy before start");
    dispatch='{valid:1'b1,qid:qid_t'(N_Q-1),desc:desc_id_t'(2),info:info_write.info};
    cycle();
    dispatch='0;
endtask

task automatic send_packet(input int length, input int salt, input bit stall);
    int start_done, steps;
    bit reuse;
    cell_id_t reuse_id;
    continuous=!stall;
    load_packet(length,salt);
    m_ready=!stall;
    start_done=packets_done;
    start_packet();
    if (stall) repeat (TX_FIFO_DEPTH+MEM_RD_LATENCY+4) cycle();
    steps=0;
    while (packets_done==start_done && steps<2000) begin
        // Independent repeatable stalls include cell and final-beat holds.
        m_ready=!stall || (steps%11>=4 && steps%7!=0);
        #1;
        reuse=cell_return.valid && !tx_done.valid;
        reuse_id=cell_return.id;
        cycle();
        write_req='0;
        cell_write='0;
        if (reuse) begin
            // First legal following edge: overwrite returned payload/link
            // while the previous packet still owns later buffered cells.
            write_req='{valid:1'b1,addr:ADDR_W'(int'(reuse_id)*CELL_WORDS),data:64'hfeedfacecafef00d};
            cell_write='{valid:1'b1,id:reuse_id,next_id:reuse_id};
        end
        steps++;
    end
    assert (packets_done==start_done+1) else $fatal(1,"TX timeout");
    write_req='0;
    cell_write='0;
    m_ready=0;
    assert (idle && dispatch_ready) else $fatal(1,"not idle after EOF");
    cycle();
endtask

initial begin
    write_req='0; cell_write='0; queue_write='0; info_write='0;
    dispatch='0; abort_cell='0; queue_head='0; queue_heads='0; m_ready=0;
    reset_tx();
    queue_write='{valid:1'b1,id:desc_id_t'(1),next_id:desc_id_t'(3)};
    queue_head=desc_id_t'(1);
    cycle();
    queue_write='0;
    assert (queue_next==desc_id_t'(3)) else $fatal(1,"P03 link child");
    cell_write='{valid:1'b1,id:cell_id_t'(0),next_id:cell_id_t'(7)};
    abort_cell=cell_id_t'(0);
    cycle();
    cell_write='0;
    assert (abort_next==cell_id_t'(7)) else $fatal(1,"abort link mux");
    // Exact keeps and boundaries, repeated descriptor/tag/physical IDs.
    for (int length=1; length<=9; length++) send_packet(length,19+length,1);
    send_packet(CELL_BYTES-1,41,1);
    send_packet(CELL_BYTES,43,1);
    send_packet(CELL_BYTES+1,47,1);
    send_packet(MAX_PACKET_BYTES-1,71,1);
    send_packet(MAX_PACKET_BYTES,83,0);
    // Pending read reset without resetting RAM or its response pipeline.
    load_packet(MAX_PACKET_BYTES,101);
    start_packet();
    cycle();
    reset_tx();
    send_packet(9,153,0);
    // Full FIFO reset; then reset while the last beat is stalled.
    load_packet(MAX_PACKET_BYTES,171);
    start_packet();
    repeat (TX_FIFO_DEPTH+MEM_RD_LATENCY+3) cycle();
    reset_tx();
    load_packet(1,191);
    start_packet();
    repeat (MEM_RD_LATENCY+4) cycle();
    assert (m_valid && m_beat.last) else $fatal(1,"missing stalled EOF");
    reset_tx();
    send_packet(MAX_PACKET_BYTES,211,1);
    assert (full_pending_hits>0 && triple_hits>0) else $fatal(1,"missing pressure case");
    $display("TM_DESIGNER_MEMORY_TX_PASS packets=%0d cells=%0d full_pending=%0d triple=%0d latency=%0d depth=%0d first_valid=%0d continuous_gap=%0d",
        packets_done,cells_freed,full_pending_hits,triple_hits,MEM_RD_LATENCY,TX_FIFO_DEPTH,
        max_first_valid,max_continuous_gap);
    $finish;
end
initial begin
    #200000;
    $fatal(1,"watchdog");
end
endmodule
