// RTL-owned smoke. Public ports only; no independent verification dependencies.
module tm_memory_tx_smoke import tm_fixed::*; #(
    parameter integer DATA_W=64, N_RX=2, N_Q=4, CELL_BYTES=16,
    N_CELL=32, N_DESC=16, MAX_PACKET_BYTES=256,
    RX_FIFO_DEPTH=2, MEM_RD_LATENCY=1, TX_FIFO_DEPTH=4,
    SCHED_MODE=1, QUANTUM_DEFAULT=MAX_PACKET_BYTES, TRACE_ENABLE=1,
    CELL_ID_W=$clog2(N_CELL), DESC_ID_W=$clog2(N_DESC),
    CELL_COUNT_W=$clog2(N_CELL+1), DESC_COUNT_W=$clog2(N_DESC+1),
    DEFICIT_W=$clog2(4096+MAX_PACKET_BYTES)
);
`include "tm_types.svh"
localparam integer CELL_WORDS=CELL_BYTES/8;
logic clk=0, rst_n=0;
always #5 clk=~clk;
ram_write_t write_req;
ram_read_t read_req;
ram_response_t response;
dispatch_t dispatch;
logic dispatch_ready, m_valid, m_ready, idle;
beat_t m_beat;
cell_return_t cell_return;
tx_done_t tx_done;
cell_id_t link_cell, next_cell, abort_cell, abort_next;
cell_link_write_t cell_write;
desc_link_write_t queue_write;
desc_write_t info_write;
logic [N_Q*DESC_ID_W-1:0] queue_heads;
logic [N_Q*DESC_INFO_W-1:0] head_info;
desc_id_t queue_head, queue_next;
`define PARAMS .DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES), \
 .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES), \
 .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY), \
 .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .SCHED_MODE(SCHED_MODE), \
 .QUANTUM_DEFAULT(QUANTUM_DEFAULT), .TRACE_ENABLE(TRACE_ENABLE)
tm_packet_ram_api #(`PARAMS) ram (.*);
tm_metadata_api #(`PARAMS) metadata (.tx_cell(link_cell), .tx_next(next_cell), .*);
tm_tx_api #(`PARAMS) tx (.*);
`undef PARAMS

integer cycle=0, received=0, returned=0, expect_len=0, pattern=0;
integer issued=0, responded=0, first_cycle=-1, dispatch_cycle=0, previous_output=-1;
integer triple_events=0, full_stalls=0, packets=0;
integer max_first_latency=0, streamed_beats=0;
integer reuse_id=-1;
bit checking=0, require_stream=0, reuse_cells=0;
logic [63:0] expected_user;
integer seed_arg=17;
int unsigned rng;
logic [MEM_RD_LATENCY-1:0] expected_response_valid='0;
logic [63:0] expected_response_data [MEM_RD_LATENCY];
logic [63:0] memory_words [N_CELL*CELL_WORDS];
bit memory_started=0;
function automatic cell_id_t chain_cell(input integer index);
    return cell_id_t'((index*7+3)%N_CELL);
endfunction
function automatic logic [63:0] data_word(input integer base, input integer index);
    logic [63:0] value;
    for (int b=0; b<8; b++) value[b*8+:8]=8'(base+index*8+b);
    return value;
endfunction
// Sample before NBA: latency is measured between accepting edges, not #delays.
always @(posedge clk) begin
    cycle=cycle+1;
    if (memory_started) begin
        assert (response.valid==expected_response_valid[MEM_RD_LATENCY-1])
            else $fatal(1,"RAM response timing cycle=%0d",cycle);
        if (response.valid) assert (response.data==expected_response_data[MEM_RD_LATENCY-1])
            else $fatal(1,"RAM response bytes cycle=%0d",cycle);
    end
    for (int s=MEM_RD_LATENCY-1; s>0; s--) begin
        expected_response_valid[s]=expected_response_valid[s-1];
        expected_response_data[s]=expected_response_data[s-1];
    end
    expected_response_valid[0]=read_req.valid;
    if (read_req.valid) expected_response_data[0]=memory_words[read_req.addr];
    if (write_req.valid) memory_words[write_req.addr]=write_req.data;
    if (cycle>MEM_RD_LATENCY) memory_started=1;
    if (rst_n && checking) begin
        if (read_req.valid) issued=issued+1;
        if (response.valid) responded=responded+1;
        if (issued-received==TX_FIFO_DEPTH && !m_ready) full_stalls=full_stalls+1;
        if (read_req.valid && response.valid && m_valid && m_ready) triple_events=triple_events+1;
        assert (issued-received-int'(m_valid && m_ready)<=TX_FIFO_DEPTH) else $fatal(1,"public read credits exceeded");
        if (m_valid && first_cycle<0) begin
            first_cycle=cycle;
            if (first_cycle-dispatch_cycle>max_first_latency)
                max_first_latency=first_cycle-dispatch_cycle;
            assert (first_cycle-dispatch_cycle<=MEM_RD_LATENCY+4)
                else $fatal(1,"first-valid bound");
        end
        if (require_stream && previous_output>=0 && received*8<expect_len)
            assert (m_valid) else $fatal(1,"within-packet bubble");
        assert (cell_return.valid==(m_valid && m_ready &&
            ((received+1)*8>=expect_len || (received+1)%CELL_WORDS==0)))
            else $fatal(1,"cell return edge received=%0d",received);
        assert (tx_done.valid==(m_valid && m_ready && (received+1)*8>=expect_len))
            else $fatal(1,"packet completion edge");
        if (m_valid && m_ready) begin
            if (require_stream) streamed_beats++;
            for (int b=0;b<8;b++) if (received*8+b<expect_len)
                assert (m_beat.data[b*8+:8]==8'(pattern+received*8+b))
                    else $fatal(1,"TX bytes beat=%0d lane=%0d",received,b);
            assert (m_beat.keep==((expect_len-received*8>=8) ? 8'hff :
                8'((1<<(expect_len-received*8))-1))) else $fatal(1,"TX keep");
            assert (m_beat.last==((received+1)*8>=expect_len)) else $fatal(1,"TX last");
            assert (m_beat.user==expected_user) else $fatal(1,"TX user");
            if (cell_return.valid) begin
                assert (cell_return.id==chain_cell(returned)) else $fatal(1,"retired wrong cell");
                assert (cell_return.desc==dispatch.desc && cell_return.qid==dispatch.qid &&
                    !cell_return.abort_source) else $fatal(1,"return owner");
                if (reuse_cells) reuse_id=int'(cell_return.id);
                returned=returned+1;
            end
            if (tx_done.valid) assert (tx_done.desc==dispatch.desc &&
                tx_done.qid==dispatch.qid && int'(tx_done.length)==expect_len);
            previous_output=cycle;
            received=received+1;
        end
    end
    if (!rst_n) assert (!m_valid && !cell_return.valid && !tx_done.valid && !read_req.valid);
end

task automatic tick;
    @(posedge clk); #1; @(negedge clk);
endtask
// Reset never touches payload or metadata. Hold across two accepting edges.
task automatic reset_tx;
    checking=0; rst_n=0; dispatch.valid=0; m_ready=0;
    write_req='0; cell_write='0; info_write='0; queue_write='0;
    tick(); tick(); rst_n=1; tick();
    assert (idle && dispatch_ready && !m_valid);
endtask

task automatic load_packet(input integer length, input integer bytes_base);
    integer nwords, ncells;
    expect_len=length; pattern=bytes_base;
    nwords=(length+7)/8; ncells=(length+CELL_BYTES-1)/CELL_BYTES;
    for (int w=0; w<nwords; w++) begin
        write_req='{valid:1'b1, addr:ADDR_W'(int'(chain_cell(w/CELL_WORDS))*CELL_WORDS+w%CELL_WORDS),
            data:data_word(bytes_base,w)};
        cell_write='0;
        if (w%CELL_WORDS==0 && w/CELL_WORDS+1<ncells)
            cell_write='{valid:1'b1, id:chain_cell(w/CELL_WORDS), next_id:chain_cell(w/CELL_WORDS+1)};
        tick();
    end
    write_req='0; cell_write='0;
    dispatch='{valid:1'b0, qid:qid_t'(1), desc:desc_id_t'(2),
        info:'{head:chain_cell(0), ncell:cell_count_t'(ncells), length:16'(length),
        qid:qid_t'(1), tag:16'h55aa, source:port_id_t'(N_RX-1)}};
    info_write='{valid:1'b1, id:dispatch.desc, info:dispatch.info};
    queue_write='{valid:1'b1, id:desc_id_t'(2), next_id:desc_id_t'(3)};
    tick(); info_write='0; queue_write='0;
    queue_heads='0;
    for (int q=0;q<N_Q;q++) queue_heads[q*DESC_ID_W+:DESC_ID_W]=dispatch.desc;
    queue_head=dispatch.desc; abort_cell=chain_cell(0);
    #1;
    for (int q=0;q<N_Q;q++) assert (head_info[q*DESC_INFO_W+:DESC_INFO_W]==dispatch.info);
    assert (queue_next==desc_id_t'(3));
    if (ncells>1) assert (abort_next==chain_cell(1));
endtask

task automatic start_packet;
    received=0; returned=0; issued=0; responded=0;
    first_cycle=-1; previous_output=-1; checking=1; reuse_id=-1;
    expected_user={16'b0, 8'(N_RX-1),16'h55aa,16'(expect_len),8'd1};
    assert (dispatch_ready);
    dispatch.valid=1; dispatch_cycle=cycle+1; tick(); dispatch.valid=0;
endtask

task automatic finish_packet(input integer mode);
    integer guard_cycles;
    guard_cycles=0;
    while (!idle) begin
        // Long full stalls, periodic stalls and a held final transfer.
        rng=rng*32'd1664525+32'd1013904223;
        m_ready=(mode==0 || (guard_cycles>TX_FIFO_DEPTH+MEM_RD_LATENCY+6 && rng[31:29]!=0));
        if (mode!=0 && received==(expect_len-1)/8 && guard_cycles<100) m_ready=0;
        write_req='0; cell_write='0;
        if (reuse_id>=0) begin
            // Next edge after return: corrupt the old link and payload immediately.
            write_req='{valid:1'b1, addr:ADDR_W'(reuse_id*CELL_WORDS), data:64'hbad0bad1bad2bad3};
            cell_write='{valid:1'b1, id:cell_id_t'(reuse_id), next_id:cell_id_t'(reuse_id)};
            reuse_id=-1;
        end
        tick(); guard_cycles++;
        assert (guard_cycles<2000) else $fatal(1,"TX timeout");
    end
    checking=0; write_req='0; cell_write='0;
    assert (received==(expect_len+7)/8 && returned==(expect_len+CELL_BYTES-1)/CELL_BYTES);
    assert (issued==received && responded==received);
    packets++; tick();
endtask

initial begin
    write_req='0; dispatch='0; cell_write='0; queue_write='0; info_write='0;
    queue_heads='0; queue_head='0; abort_cell='0; m_ready=0;
    if ($value$plusargs("seed=%d",seed_arg)) begin end
    rng=32'(seed_arg);
    @(negedge clk); reset_tx();
    for (int length=1;length<=2*CELL_BYTES+8;length++) begin
        load_packet(length, length+17); require_stream=1; reuse_cells=1;
        start_packet(); finish_packet(0);
    end
    for (int length=MAX_PACKET_BYTES-7;length<=MAX_PACKET_BYTES;length++) begin
        load_packet(length, length+71); require_stream=1; reuse_cells=1;
        start_packet(); finish_packet(0);
    end
    load_packet(MAX_PACKET_BYTES,91); require_stream=0; reuse_cells=1;
    start_packet(); finish_packet(1);
    // Reset at dispatch, pending reads, FIFO-full pressure, cell/final holds.
    for (int boundary=0;boundary<6;boundary++) begin
        load_packet(MAX_PACKET_BYTES,33+boundary); require_stream=0; reuse_cells=0;
        start_packet(); m_ready=0;
        if (boundary<4) repeat (boundary==3 ? TX_FIFO_DEPTH+MEM_RD_LATENCY+3 : boundary) tick();
        else begin
            m_ready=1;
            while (received<(boundary==4 ? CELL_WORDS-1 : (MAX_PACKET_BYTES-1)/8)) tick();
            m_ready=0; repeat (MEM_RD_LATENCY+2) tick();
        end
        reset_tx();
        // Same descriptor/tag/cells with distinctive post-reset bytes.
        load_packet(CELL_BYTES+3,177+boundary); start_packet(); finish_packet(1);
    end
    assert (triple_events>0 && full_stalls>0) else $fatal(1,"missing designer pressure scenarios");
    $display("DESIGNER_SMOKE_PASS latency=%0d depth=%0d cells=%0d bytes=%0d packets=%0d triple=%0d full=%0d first=%0d streamed=%0d seed=%0d",
        MEM_RD_LATENCY,TX_FIFO_DEPTH,N_CELL,CELL_BYTES,packets,triple_events,full_stalls,
        max_first_latency,streamed_beats,seed_arg);
    $finish;
end
initial begin #10000000; $fatal(1,"designer smoke global timeout"); end
endmodule
