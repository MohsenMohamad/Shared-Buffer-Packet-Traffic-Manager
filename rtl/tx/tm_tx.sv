module tm_tx_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input dispatch_t dispatch,
    output logic dispatch_ready,
    output ram_read_t read_req,
    input ram_response_t response,
    output cell_id_t link_cell,
    input cell_id_t next_cell,
    output logic m_valid,
    output beat_t m_beat,
    input logic m_ready,
    output cell_return_t cell_return,
    output tx_done_t tx_done,
    output logic idle
);
`include "tm_validate.svh"
localparam integer CELL_WORDS=CELL_BYTES/8;
localparam integer PTR_W=(TX_FIFO_DEPTH>1 ? $clog2(TX_FIFO_DEPTH) : 1);
localparam integer COUNT_W=$clog2(TX_FIFO_DEPTH+1);
typedef struct packed {
    cell_id_t cell_id;
    logic cell_end;
    logic last;
    logic [7:0] keep;
} read_tag_t;
typedef struct packed {
    beat_t beat;
    cell_id_t cell_id;
    logic cell_end;
} entry_t;

logic active;
dispatch_t packet;
cell_id_t read_cell, captured_next;
logic [WORD_OFF_W-1:0] read_word;
logic [15:0] bytes_to_read;
read_tag_t tags [MEM_RD_LATENCY];
logic [MEM_RD_LATENCY-1:0] tag_valid;
entry_t fifo [TX_FIFO_DEPTH];
logic [PTR_W-1:0] rd_ptr, wr_ptr;
logic [COUNT_W-1:0] buffered, outstanding;
logic [COUNT_W:0] buffered_next, outstanding_next, credits_after_retire;
logic issue, arrival, retire;
read_tag_t issued_tag;
entry_t response_entry;
output_user_t user_fields;

function automatic logic [PTR_W-1:0] advance(input logic [PTR_W-1:0] ptr);
    return int'(ptr)==TX_FIFO_DEPTH-1 ? '0 : ptr+PTR_W'(1);
endfunction

assign idle = !active && buffered==0 && outstanding==0;
assign dispatch_ready = rst_n && idle;
assign m_valid = rst_n && buffered!=0;
assign m_beat = fifo[rd_ptr].beat;
assign retire = m_valid && m_ready;
assign link_cell = read_cell;
// Invalidated tags discard physical RAM responses from the previous epoch.
// Both the tag and data path advance unconditionally at identical latency.
assign arrival = rst_n && tag_valid[MEM_RD_LATENCY-1] && response.valid;

always_comb begin
    // Reserve for every issued read. Arrival transfers one reservation from
    // outstanding to buffered; it never creates a free slot. Sink retirement
    // can fund this edge's issue, including at exact capacity.
    credits_after_retire = {1'b0,buffered}+{1'b0,outstanding}-(COUNT_W+1)'(retire);
    issue = rst_n && active && bytes_to_read!=0 &&
            credits_after_retire<(COUNT_W+1)'(TX_FIFO_DEPTH);
    buffered_next = {1'b0,buffered}+(COUNT_W+1)'(arrival)-(COUNT_W+1)'(retire);
    outstanding_next = {1'b0,outstanding}+(COUNT_W+1)'(issue)-(COUNT_W+1)'(arrival);

    read_req = '0;
    read_req.valid = issue;
    read_req.addr = ADDR_W'(int'(read_cell)*CELL_WORDS+int'(read_word));
    issued_tag.cell_id = read_cell;
    issued_tag.last = bytes_to_read<=16'd8;
    issued_tag.cell_end = issued_tag.last || int'(read_word)==CELL_WORDS-1;
    issued_tag.keep = bytes_to_read>=16'd8 ? 8'hff :
                      8'((9'd1 << bytes_to_read[3:0])-9'd1);

    user_fields = '0;
    user_fields.qid = 8'(packet.qid);
    user_fields.length = packet.info.length;
    user_fields.tag = packet.info.tag;
    user_fields.source = 8'(packet.info.source);
    response_entry = '0;
    response_entry.beat.data = response.data;
    response_entry.beat.keep = tags[MEM_RD_LATENCY-1].keep;
    response_entry.beat.last = tags[MEM_RD_LATENCY-1].last;
    response_entry.beat.user = user_fields;
    response_entry.cell_id = tags[MEM_RD_LATENCY-1].cell_id;
    response_entry.cell_end = tags[MEM_RD_LATENCY-1].cell_end;

    // Only the externally accepted FIFO head can release an owner. The
    // prefetch cursor may already be several cells ahead of this entry.
    cell_return = '0;
    cell_return.valid = retire && fifo[rd_ptr].cell_end;
    cell_return.id = fifo[rd_ptr].cell_id;
    cell_return.qid = packet.qid;
    cell_return.desc = packet.desc;
    tx_done = '0;
    tx_done.valid = retire && m_beat.last;
    tx_done.desc = packet.desc;
    tx_done.qid = packet.qid;
    tx_done.length = packet.info.length;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active <= 1'b0;
        packet <= '0;
        read_cell <= '0;
        captured_next <= '0;
        read_word <= '0;
        bytes_to_read <= '0;
        tag_valid <= '0;
        rd_ptr <= '0;
        wr_ptr <= '0;
        buffered <= '0;
        outstanding <= '0;
    end else begin
        buffered <= COUNT_W'(buffered_next);
        outstanding <= COUNT_W'(outstanding_next);
        tag_valid[0] <= issue;
        for (int i=1; i<MEM_RD_LATENCY; i++) tag_valid[i] <= tag_valid[i-1];
        if (retire) rd_ptr <= advance(rd_ptr);
        if (arrival) wr_ptr <= advance(wr_ptr);
        if (tx_done.valid) active <= 1'b0;
        if (dispatch.valid && dispatch_ready) begin
            active <= 1'b1;
            packet <= dispatch;
            read_cell <= dispatch.info.head;
            read_word <= '0;
            bytes_to_read <= dispatch.info.length;
        end
        if (issue) begin
            bytes_to_read <= issued_tag.last ? 16'd0 : bytes_to_read-16'd8;
            // CELL_WORDS>=2: capture on the first read, before the cell's
            // last read/response/retirement. Never capture a stale tail link.
            if (read_word==0 && bytes_to_read>16'(CELL_BYTES)) captured_next <= next_cell;
            if (int'(read_word)==CELL_WORDS-1) begin
                read_word <= '0;
                if (!issued_tag.last) read_cell <= captured_next;
            end else read_word <= read_word+WORD_OFF_W'(1);
        end
    end
end

// Unreset storage: tag_valid and buffered alone establish current-epoch
// validity. Reset never clears payload, link arrays or FIFO/tag data arrays.
always_ff @(posedge clk) begin
    tags[0] <= issued_tag;
    for (int i=1; i<MEM_RD_LATENCY; i++) tags[i] <= tags[i-1];
    if (arrival) fifo[wr_ptr] <= response_entry;
end

always @(posedge clk) if (rst_n) begin
    assert (int'(buffered)+int'(outstanding)<=TX_FIFO_DEPTH);
    assert (int'(buffered_next)+int'(outstanding_next)<=TX_FIFO_DEPTH);
    assert (int'(outstanding)==$countones(tag_valid));
    if (tag_valid[MEM_RD_LATENCY-1]) assert (response.valid);
    if (arrival) assert (int'(buffered)<TX_FIFO_DEPTH || retire);
    if (dispatch.valid) begin
        assert (dispatch_ready);
        assert (dispatch.info.length>0 && int'(dispatch.info.length)<=MAX_PACKET_BYTES);
        assert (int'(dispatch.info.ncell)==(int'(dispatch.info.length)+CELL_BYTES-1)/CELL_BYTES);
        assert (dispatch.qid==dispatch.info.qid);
        assert (int'(dispatch.info.head)<N_CELL && int'(dispatch.desc)<N_DESC);
    end
    if (issue) assert (int'(read_cell)<N_CELL);
    if (tx_done.valid) begin
        assert (cell_return.valid);
        assert (buffered==1 && outstanding==0 && bytes_to_read==0);
    end
end

`ifndef SYNTHESIS
// Designer check of the full record, including unused final data lanes.
logic stalled;
beat_t stalled_beat;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stalled <= 1'b0;
        stalled_beat <= '0;
    end else begin
        if (stalled) assert (m_valid && m_beat==stalled_beat);
        stalled <= m_valid && !m_ready;
        stalled_beat <= m_beat;
    end
end
`endif
endmodule
