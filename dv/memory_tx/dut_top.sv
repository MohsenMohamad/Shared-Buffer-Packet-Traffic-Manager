// Public-interface binding only. Expectations live in the frozen Python oracle.
package memory_tx_dut_wires;
`include "wires.svh"
endpackage
module memory_tx_dut_top #(
`include "tm_parameters.svh"
)(
    input logic clk, rst_n, sink_ready,
    input logic [1792-1:0] stimulus,
    input logic [511:0] heads,
    input logic [31:0] abort_cell, queue_id, queue_value, queue_query,
    input logic queue_write_valid,
    output logic [1792-1:0] observed,
    output logic output_valid, dispatch_ready, idle,
    output logic [63:0] output_data, output_user,
    output logic [7:0] output_keep,
    output logic output_last,
    output logic [3071:0] head_fields,
    output logic [31:0] abort_next_value, queue_next_value
);
`include "tm_types.svh"
import memory_tx_dut_wires::*;
memory_actions_t drive, sample;
ram_write_t write_req;
ram_read_t read_req;
ram_response_t response;
cell_link_write_t cell_write;
desc_link_write_t queue_write;
desc_write_t info_write;
dispatch_t dispatch;
cell_return_t cell_return;
tx_done_t tx_done;
beat_t beat;
cell_id_t link_cell, next_cell, abort_next;
desc_id_t queue_next;
logic [N_Q*DESC_ID_W-1:0] queue_heads;
localparam int INFO_W=$bits(descriptor_t);
logic [N_Q*INFO_W-1:0] head_info;
descriptor_t selected_info;
assign drive=stimulus;
assign observed=sample;
assign write_req='{valid:1'(drive.write_v),addr:ADDR_W'(drive.write_addr),data:drive.write_data};
assign cell_write='{valid:1'(drive.link_v),id:cell_id_t'(drive.link_cell),next_id:cell_id_t'(drive.link_next)};
assign queue_write='{valid:queue_write_valid,id:desc_id_t'(queue_id),next_id:desc_id_t'(queue_value)};
assign info_write.valid=1'(drive.info_v);
assign info_write.id=desc_id_t'(drive.info_desc);
assign info_write.info='{head:cell_id_t'(drive.info_head),ncell:cell_count_t'(drive.info_ncell),
    length:16'(drive.info_length),qid:qid_t'(drive.info_qid),tag:16'(drive.info_tag),source:port_id_t'(drive.info_source)};
assign selected_info=descriptor_t'(head_info[0 +: INFO_W]);
assign dispatch='{valid:1'(drive.dispatch_v),qid:qid_t'(drive.dispatch_info_qid),desc:desc_id_t'(drive.dispatch_desc),info:selected_info};
assign output_valid=tx_valid;
logic tx_valid;
assign output_data=beat.data;
assign output_user=beat.user;
assign output_keep=beat.keep;
assign output_last=beat.last;
assign abort_next_value=32'(abort_next);
assign queue_next_value=32'(queue_next);
for(genvar q=0;q<N_Q;q++)begin
    assign queue_heads[q*DESC_ID_W +: DESC_ID_W]=DESC_ID_W'(heads[q*32 +: 32]);
end
always_comb begin
    head_fields='0;
    for(int q=0;q<N_Q;q++)begin
        descriptor_t info;
        info=descriptor_t'(head_info[q*INFO_W +: INFO_W]);
        head_fields[q*192 +: 192]={32'(info.head),32'(info.ncell),32'(info.length),32'(info.qid),32'(info.tag),32'(info.source)};
    end
    sample=drive;
    sample.read_v=32'(read_req.valid); sample.read_addr=32'(read_req.addr);
    sample.response_v=32'(response.valid); sample.response_data=response.data;
    sample.query_v=32'(rst_n && !idle); sample.query_cell=32'(link_cell); sample.query_next=32'(next_cell);
    sample.free_v=32'(cell_return.valid); sample.free_cell=32'(cell_return.id);
    sample.done_v=32'(tx_done.valid); sample.done_desc=32'(tx_done.desc);
    if(drive.dispatch_v!=0 || drive.commit_v!=0)begin
        sample.dispatch_info_v=drive.dispatch_v;
        sample.dispatch_info_desc=drive.dispatch_desc;
        sample.dispatch_info_head=32'(selected_info.head); sample.dispatch_info_ncell=32'(selected_info.ncell);
        sample.dispatch_info_length=32'(selected_info.length); sample.dispatch_info_qid=32'(selected_info.qid);
        sample.dispatch_info_tag=32'(selected_info.tag); sample.dispatch_info_source=32'(selected_info.source);
        sample.commit_info_v=drive.commit_v; sample.commit_info_desc=drive.commit_desc;
        sample.commit_info_head=32'(selected_info.head); sample.commit_info_ncell=32'(selected_info.ncell);
        sample.commit_info_length=32'(selected_info.length); sample.commit_info_qid=32'(selected_info.qid);
        sample.commit_info_tag=32'(selected_info.tag); sample.commit_info_source=32'(selected_info.source);
    end
end
tm_packet_ram_api #(.DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES), .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY), .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .SCHED_MODE(SCHED_MODE), .QUANTUM_DEFAULT(QUANTUM_DEFAULT), .TRACE_ENABLE(TRACE_ENABLE), .CELL_ID_W(CELL_ID_W), .DESC_ID_W(DESC_ID_W), .CELL_COUNT_W(CELL_COUNT_W), .DESC_COUNT_W(DESC_COUNT_W), .DEFICIT_W(DEFICIT_W)) ram(.clk,.write_req,.read_req,.response);
tm_metadata_api #(.DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES), .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY), .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .SCHED_MODE(SCHED_MODE), .QUANTUM_DEFAULT(QUANTUM_DEFAULT), .TRACE_ENABLE(TRACE_ENABLE), .CELL_ID_W(CELL_ID_W), .DESC_ID_W(DESC_ID_W), .CELL_COUNT_W(CELL_COUNT_W), .DESC_COUNT_W(DESC_COUNT_W), .DEFICIT_W(DEFICIT_W)) metadata(.clk,.cell_write,.queue_write,.info_write,
    .tx_cell(link_cell),.abort_cell(cell_id_t'(abort_cell)),.tx_next(next_cell),.abort_next,
    .queue_heads,.head_info,.queue_head(desc_id_t'(queue_query)),.queue_next);
tm_tx_api #(.DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES), .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY), .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .SCHED_MODE(SCHED_MODE), .QUANTUM_DEFAULT(QUANTUM_DEFAULT), .TRACE_ENABLE(TRACE_ENABLE), .CELL_ID_W(CELL_ID_W), .DESC_ID_W(DESC_ID_W), .CELL_COUNT_W(CELL_COUNT_W), .DESC_COUNT_W(DESC_COUNT_W), .DEFICIT_W(DEFICIT_W)) tx(.clk,.rst_n,.dispatch,.dispatch_ready,.read_req,.response,
    .link_cell,.next_cell,.m_valid(tx_valid),.m_beat(beat),.m_ready(sink_ready),.cell_return,.tx_done,.idle);
endmodule
