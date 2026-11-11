module probe_unit #(
`include "tm_parameters.svh"
) (
    input logic clk, input logic rst_n,
    input logic enable, input logic s_valid, input logic [136:0] s_bits,
    output logic s_ready, output logic m_valid, output logic [136:0] m_bits,
    input logic m_ready, output logic empty,
    input logic [110:0] req_bits, output logic [40:0] rsp_bits,
    input logic [2:0] event_kind, input logic [7:0] event_qid,
    input logic [15:0] event_ncell, input logic [1:0] cmd_bits,
    input logic [N_Q*CELL_COUNT_W-1:0] owned,
    output logic [10*64+N_Q*5*64+N_Q*CELL_COUNT_W-1:0] stats_bits,
    output logic [10*64+N_Q*5*64+N_Q*CELL_COUNT_W-1:0] shadow_bits,
    output logic [CELL_COUNT_W-1:0] last_limit,
    output logic cfg_run
);
`include "tm_local_types.svh"
beat_t s_beat, m_beat;
axil_request_t req;
axil_response_t rsp;
trace_t events;
live_t live;
statistics_t stats, shadow;
config_t cfg;
stats_command_t cmd, csr_cmd;
assign s_beat=s_bits;
assign m_bits=m_beat;
assign req=req_bits;
assign rsp_bits=rsp;
assign cmd=cmd_bits;
assign stats_bits=stats;
assign shadow_bits=shadow;
assign last_limit=cfg.cell_limit[(N_Q-1)*CELL_COUNT_W +: CELL_COUNT_W];
assign cfg_run=cfg.run;
always_comb begin
    live='0;
    live.idle=1;
    live.owned=owned;
    events='0;
    events.admit.valid=(event_kind==1 || event_kind==2);
    events.admit.accept=(event_kind==1);
    events.admit.qid=event_qid;
    events.admit.ncell=CELL_COUNT_W'(event_ncell);
    events.admit.reason=(event_kind==2) ? NO_CELLS : COMMITTED;
    events.tx_done.valid=(event_kind==3);
    events.tx_done.qid=Q_ID_W'(event_qid);
    events.cell_free.valid=(event_kind==4);
    events.cell_free.qid=Q_ID_W'(event_qid);
    events.abort_done.valid=(event_kind==5);
    events.abort_done.qid=Q_ID_W'(event_qid);
    events.abort_done.ncell=CELL_COUNT_W'(event_ncell);
end
tm_axis_rx_fifo_api #(`include "connections.svh") fifo(
    .clk(clk),.rst_n(rst_n),.enable(enable),.s_valid(s_valid),.s_beat(s_beat),
    .s_ready(s_ready),.m_valid(m_valid),.m_beat(m_beat),.m_ready(m_ready),.empty(empty));
tm_statistics_api #(`include "connections.svh") statistics(
    .clk(clk),.rst_n(rst_n),.events(events),.input_stalled({N_RX{1'b0}}),
    .output_stalled(1'b0),.output_fire(event_kind==3),.output_beat(s_beat),
    .run(cfg.run),.live(live),.command(cmd),.live_stats(stats),.shadow_stats(shadow));
tm_axil_regs_api #(`include "connections.svh") regs(
    .clk(clk),.rst_n(rst_n),.initialized(1'b1),.bus_req(req),.bus_rsp(rsp),
    .live(live),.live_stats(stats),.shadow_stats(shadow),.cfg(cfg),.stats_command(csr_cmd));
endmodule
