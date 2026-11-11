module synth_top(
input logic clk,rst_n,enable,s_valid,m_ready,
input logic [136:0] s_bits,input logic [110:0] req_bits,
input logic [2:0] event_kind,input logic [7:0] event_qid,
input logic [15:0] event_ncell,input logic [1:0] cmd_bits,
input logic [23:0] owned,
output logic [3233:0] stats_bits,shadow_bits,
output logic [81:0] rsp_bits,output logic [273:0] m_bits,
output logic [10:0] last_limit,
output logic [1:0] cfg_run,s_ready,m_valid,empty
);
probe_unit #(.N_Q(2),.N_CELL(16),.N_DESC(8),.N_RX(1),.CELL_BYTES(16),.MAX_PACKET_BYTES(128),.RX_FIFO_DEPTH(2)) u0(
.clk(clk),.rst_n(rst_n),.enable(enable),.s_valid(s_valid),.m_ready(m_ready),.s_bits(s_bits),.req_bits(req_bits),.event_kind(event_kind),.event_qid(event_qid),.event_ncell(event_ncell),.cmd_bits(cmd_bits),.owned(owned[9:0]),.stats_bits(stats_bits[0 +:1290]),.shadow_bits(shadow_bits[0 +:1290]),.rsp_bits(rsp_bits[0 +:41]),.m_bits(m_bits[0 +:137]),.last_limit(last_limit[0 +:5]),.cfg_run(cfg_run[0]),.s_ready(s_ready[0]),.m_valid(m_valid[0]),.empty(empty[0]));
probe_unit #(.N_Q(4),.N_CELL(32),.N_DESC(16),.N_RX(2),.CELL_BYTES(16),.MAX_PACKET_BYTES(128),.RX_FIFO_DEPTH(4)) u1(
.clk(clk),.rst_n(rst_n),.enable(enable),.s_valid(s_valid),.m_ready(m_ready),.s_bits(s_bits),.req_bits(req_bits),.event_kind(event_kind),.event_qid(event_qid),.event_ncell(event_ncell),.cmd_bits(cmd_bits),.owned(owned[23:0]),.stats_bits(stats_bits[1290 +:1944]),.shadow_bits(shadow_bits[1290 +:1944]),.rsp_bits(rsp_bits[41 +:41]),.m_bits(m_bits[137 +:137]),.last_limit(last_limit[5 +:6]),.cfg_run(cfg_run[1]),.s_ready(s_ready[1]),.m_valid(m_valid[1]),.empty(empty[1]));
endmodule
