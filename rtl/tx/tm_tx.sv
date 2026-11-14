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
localparam integer CREDIT_W=$clog2(TX_FIFO_DEPTH+1);
typedef struct packed {
    cell_id_t cell_id;
    logic cell_last;
    logic packet_last;
    logic [7:0] keep;
} read_tag_t;
typedef struct packed {
    beat_t beat;
    cell_id_t cell_id;
    logic cell_last;
} fifo_entry_t;

logic active;
dispatch_t packet;
cell_id_t fetch_cell;
logic [WORD_OFF_W-1:0] fetch_word;
logic [15:0] fetch_bytes;
cell_count_t fetch_cells;
logic [MEM_RD_LATENCY-1:0] pending_valid;
read_tag_t pending_tag [MEM_RD_LATENCY];
read_tag_t issue_tag;
fifo_entry_t fifo [TX_FIFO_DEPTH];
fifo_entry_t arriving, retiring;
logic [PTR_W-1:0] rd_ptr, wr_ptr;
logic [CREDIT_W-1:0] buffered, outstanding;
integer buffered_next, outstanding_next, reserved_after_retire;
logic issue, arrive, retire;
output_user_t user_fields;

function automatic logic [PTR_W-1:0] advance(input logic [PTR_W-1:0] ptr);
    return int'(ptr)==TX_FIFO_DEPTH-1 ? '0 : ptr+PTR_W'(1);
endfunction

assign idle = !active && buffered==0 && outstanding==0;
assign dispatch_ready = rst_n && idle;
assign m_valid = rst_n && buffered!=0;
assign retiring = fifo[rd_ptr];
assign m_beat = retiring.beat;
assign retire = m_valid && m_ready;
assign link_cell = fetch_cell;
assign arrive = rst_n && pending_valid[MEM_RD_LATENCY-1] && response.valid;

// One merged credit equation, evaluated before issue:
// B' = B + response - retire; O' = O + issue - response;
// B'+O' = B+O+issue-retire. Arrival converts a reserved slot to data;
// only external retirement releases a slot. A full FIFO may issue on a pop.
always_comb begin
    reserved_after_retire = int'(buffered)+int'(outstanding)-int'(retire);
    issue = rst_n && active && fetch_bytes!=0 &&
        reserved_after_retire<TX_FIFO_DEPTH;
    buffered_next = int'(buffered)+int'(arrive)-int'(retire);
    outstanding_next = int'(outstanding)+int'(issue)-int'(arrive);
end
always_comb begin
    read_req = '0;
    read_req.valid = issue;
    read_req.addr = ADDR_W'(int'(fetch_cell)*CELL_WORDS+int'(fetch_word));
    issue_tag = '0;
    issue_tag.cell_id = fetch_cell;
    issue_tag.packet_last = fetch_bytes<=16'd8;
    issue_tag.cell_last = issue_tag.packet_last || int'(fetch_word)==CELL_WORDS-1;
    issue_tag.keep = fetch_bytes>=16'd8 ? 8'hff : 8'((9'd1<<fetch_bytes)-9'd1);
    user_fields = '{reserved:'0, source:8'(packet.info.source),
        tag:packet.info.tag, length:packet.info.length, qid:8'(packet.qid)};
    arriving = '0;
    arriving.beat = '{data:response.data, keep:pending_tag[MEM_RD_LATENCY-1].keep,
        last:pending_tag[MEM_RD_LATENCY-1].packet_last, user:user_fields};
    arriving.cell_id = pending_tag[MEM_RD_LATENCY-1].cell_id;
    arriving.cell_last = pending_tag[MEM_RD_LATENCY-1].cell_last;
    cell_return = '0;
    cell_return.valid = retire && retiring.cell_last;
    cell_return.id = retiring.cell_id;
    cell_return.qid = packet.qid;
    cell_return.desc = packet.desc;
    tx_done = '0;
    tx_done.valid = retire && retiring.beat.last;
    tx_done.desc = packet.desc;
    tx_done.qid = packet.qid;
    tx_done.length = packet.info.length;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active <= 1'b0;
        packet <= '0;
        fetch_cell <= '0;
        fetch_word <= '0;
        fetch_bytes <= '0;
        fetch_cells <= '0;
        pending_valid <= '0;
        buffered <= '0;
        outstanding <= '0;
        rd_ptr <= '0;
        wr_ptr <= '0;
    end else begin
        buffered <= CREDIT_W'(buffered_next);
        outstanding <= CREDIT_W'(outstanding_next);
        pending_valid[0] <= issue;
        for (int stage=1; stage<MEM_RD_LATENCY; stage++)
            pending_valid[stage] <= pending_valid[stage-1];
        if (arrive) wr_ptr <= advance(wr_ptr);
        if (retire) rd_ptr <= advance(rd_ptr);
        if (tx_done.valid) active <= 1'b0;
        if (dispatch.valid && dispatch_ready) begin
            active <= 1'b1;
            packet <= dispatch;
            fetch_cell <= dispatch.info.head;
            fetch_word <= '0;
            fetch_bytes <= dispatch.info.length;
            fetch_cells <= dispatch.info.ncell;
        end else if (issue) begin
            fetch_bytes <= issue_tag.packet_last ? '0 : fetch_bytes-16'd8;
            if (issue_tag.cell_last) begin
                fetch_word <= '0;
                fetch_cells <= fetch_cells-cell_count_t'(1);
                // Capture next before this cell can retire/reenter the pool.
                // Never traverse the tail's stale link.
                if (!issue_tag.packet_last) fetch_cell <= next_cell;
            end else fetch_word <= fetch_word+WORD_OFF_W'(1);
        end
    end
end
// Data/tag arrays have no reset; the resettable valid bits/counts own validity.
always_ff @(posedge clk) begin
    if (issue) pending_tag[0] <= issue_tag;
    for (int stage=1; stage<MEM_RD_LATENCY; stage++)
        if (rst_n && pending_valid[stage-1]) pending_tag[stage] <= pending_tag[stage-1];
    if (arrive) fifo[wr_ptr] <= arriving;
end

`ifndef SYNTHESIS
logic held;
beat_t held_beat;
integer retired_cells;
logic [N_CELL-1:0] retired_ids;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        held <= 1'b0;
        held_beat <= '0;
        retired_cells <= 0;
        retired_ids <= '0;
    end else begin
        assert (buffered_next>=0 && outstanding_next>=0 &&
            buffered_next+outstanding_next<=TX_FIFO_DEPTH)
            else $fatal(1, "TX buffered plus outstanding credit violation");
        assert (int'(outstanding)==$countones(pending_valid));
        if (pending_valid[MEM_RD_LATENCY-1]) assert (response.valid)
            else $fatal(1, "TX missing fixed-latency response");
        // Untagged responses can be old-epoch pipeline residue and are ignored.
        if (arrive) assert (active && (int'(buffered)<TX_FIFO_DEPTH || retire));
        if (held) assert (m_valid && m_beat==held_beat)
            else $fatal(1, "TX stalled output changed");
        held <= m_valid && !m_ready;
        held_beat <= m_beat;
        if (dispatch.valid) begin
            assert (dispatch_ready);
            assert (dispatch.info.length>0 && int'(dispatch.info.length)<=MAX_PACKET_BYTES);
            assert (int'(dispatch.info.ncell)==(int'(dispatch.info.length)+CELL_BYTES-1)/CELL_BYTES);
            assert (dispatch.qid==dispatch.info.qid && int'(dispatch.qid)<N_Q);
            assert (int'(dispatch.desc)<N_DESC && int'(dispatch.info.head)<N_CELL);
            retired_cells <= 0;
            retired_ids <= '0;
        end
        if (issue) begin
            assert (fetch_cells!=0 && int'(fetch_cell)<N_CELL);
            assert (!retired_ids[fetch_cell]);
            assert (!(cell_return.valid && cell_return.id==fetch_cell));
            if (issue_tag.cell_last && !issue_tag.packet_last)
                assert (fetch_cells>1 && int'(next_cell)<N_CELL);
            if (issue_tag.packet_last) assert (fetch_cells==1);
        end
        if (cell_return.valid) begin
            assert (retire && active && !cell_return.abort_source);
            assert (retired_cells<int'(packet.info.ncell));
            assert (!retired_ids[cell_return.id]);
            retired_ids[cell_return.id] <= 1'b1;
            retired_cells <= retired_cells+1;
        end
        if (tx_done.valid) begin
            assert (cell_return.valid && retired_cells+1==int'(packet.info.ncell));
            assert (fetch_bytes==0 && outstanding==0 && buffered==1);
        end
    end
end
`endif
endmodule
