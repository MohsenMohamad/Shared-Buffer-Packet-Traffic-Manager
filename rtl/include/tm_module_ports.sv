// Remaining declaration-only component APIs. Storage APIs are implemented separately.

module tm_rx_arb_api #(
`include "tm_parameters.svh"
) (clk, rst_n, head_valid, eligible, heads, sop, service, pop);
`include "tm_types.svh"
input logic clk, rst_n;
input logic [N_RX-1:0] head_valid, eligible;
input logic [N_RX*BEAT_W-1:0] heads;
input logic [N_RX-1:0] sop;
output service_t service;
output logic [N_RX-1:0] pop;
`include "tm_validate.svh"
endmodule

module tm_admission_api #(
`include "tm_parameters.svh"
) (clk, rst_n, head_valid, heads, service, cfg, live, available_cell, available_desc, abort_done, eligible, sop, admit, cell_alloc, cell_link_write, desc_write, payload_write, commit, abort_mark, status, contexts_idle);
`include "tm_types.svh"
input logic clk, rst_n;
input logic [N_RX-1:0] head_valid;
input logic [N_RX*BEAT_W-1:0] heads;
input service_t service;
input config_t cfg;
input live_t live;
input cell_id_t available_cell;
input desc_id_t available_desc;
input abort_done_t abort_done;
output logic [N_RX-1:0] eligible, sop;
output admission_t admit;
output cell_alloc_t cell_alloc;
output cell_link_write_t cell_link_write;
output desc_write_t desc_write;
output ram_write_t payload_write;
output commit_t commit;
output abort_mark_t abort_mark;
output logic [N_RX*STATUS_W-1:0] status;
output logic contexts_idle;
`include "tm_validate.svh"
endmodule



module tm_resource_accounting_api #(
`include "tm_parameters.svh"
) (clk, rst_n, admit, allocate, release_cell, abort_done, assigned, physical_free, unreserved, reserved_free, owned, invariant_error);
`include "tm_types.svh"
input logic clk, rst_n;
input admission_t admit;
input cell_alloc_t allocate;
input cell_return_t release_cell;
input abort_done_t abort_done;
output cell_count_t assigned, physical_free, unreserved, reserved_free;
output logic [N_Q*CELL_COUNT_W-1:0] owned;
output logic invariant_error;
`include "tm_validate.svh"
endmodule

module tm_metadata_api #(
`include "tm_parameters.svh"
) (clk, cell_write, queue_write, info_write, tx_cell, abort_cell, tx_next, abort_next, queue_heads, head_info, queue_head, queue_next);
`include "tm_types.svh"
input logic clk;
input cell_link_write_t cell_write;
input desc_link_write_t queue_write;
input desc_write_t info_write;
input cell_id_t tx_cell, abort_cell;
output cell_id_t tx_next, abort_next;
input logic [N_Q*DESC_ID_W-1:0] queue_heads;
output logic [N_Q*DESC_INFO_W-1:0] head_info;
input desc_id_t queue_head;
output desc_id_t queue_next;
`include "tm_validate.svh"
endmodule

module tm_queue_ctrl_api #(
`include "tm_parameters.svh"
) (clk, rst_n, commit, dispatch, old_head_next, heads, tails, counts, next_write, invariant_error);
`include "tm_types.svh"
input logic clk, rst_n;
input commit_t commit;
input dispatch_t dispatch;
input desc_id_t old_head_next;
output logic [N_Q*DESC_ID_W-1:0] heads, tails;
output logic [N_Q*DESC_COUNT_W-1:0] counts;
output desc_link_write_t next_write;
output logic invariant_error;
`include "tm_validate.svh"
endmodule

module tm_drr_api #(
`include "tm_parameters.svh"
) (clk, rst_n, cfg, heads, counts, head_info, commit, tx_ready, tx_done, dispatch, deficits);
`include "tm_types.svh"
input logic clk, rst_n;
input config_t cfg;
input logic [N_Q*DESC_ID_W-1:0] heads;
input logic [N_Q*DESC_COUNT_W-1:0] counts;
input logic [N_Q*DESC_INFO_W-1:0] head_info;
input commit_t commit;
input logic tx_ready;
input tx_done_t tx_done;
output dispatch_t dispatch;
output logic [N_Q*DEFICIT_W-1:0] deficits;
`include "tm_validate.svh"
endmodule

module tm_packet_ram_api #(
`include "tm_parameters.svh"
) (clk, write_req, read_req, response);
`include "tm_types.svh"
input logic clk;
input ram_write_t write_req;
input ram_read_t read_req;
output ram_response_t response;
`include "tm_validate.svh"
endmodule

module tm_tx_api #(
`include "tm_parameters.svh"
) (clk, rst_n, dispatch, dispatch_ready, read_req, response, link_cell, next_cell, m_valid, m_beat, m_ready, cell_return, tx_done, idle);
`include "tm_types.svh"
input logic clk, rst_n;
input dispatch_t dispatch;
output logic dispatch_ready;
output ram_read_t read_req;
input ram_response_t response;
output cell_id_t link_cell;
input cell_id_t next_cell;
output logic m_valid;
output beat_t m_beat;
input logic m_ready;
output cell_return_t cell_return;
output tx_done_t tx_done;
output logic idle;
`include "tm_validate.svh"
endmodule

module tm_abort_reclaim_api #(
`include "tm_parameters.svh"
) (clk, rst_n, abort_mark, tx_cell_return_valid, link_cell, next_cell, cell_return, abort_done, idle);
`include "tm_types.svh"
input logic clk, rst_n;
input abort_mark_t abort_mark;
input logic tx_cell_return_valid;
output cell_id_t link_cell;
input cell_id_t next_cell;
output cell_return_t cell_return;
output abort_done_t abort_done;
output logic idle;
`include "tm_validate.svh"
endmodule

module tm_axil_regs_api #(
`include "tm_parameters.svh"
) (clk, rst_n, initialized, bus_req, bus_rsp, live, live_stats, shadow_stats, cfg, stats_command);
`include "tm_types.svh"
input logic clk, rst_n;
input axil_request_t bus_req;
output axil_response_t bus_rsp;
input live_t live;
input statistics_t live_stats, shadow_stats;
input logic initialized;
output config_t cfg;
output stats_command_t stats_command;
`include "tm_validate.svh"
endmodule

module tm_statistics_api #(
`include "tm_parameters.svh"
) (clk, rst_n, events, input_stalled, output_stalled, output_fire, output_beat, run, live, command, live_stats, shadow_stats);
`include "tm_types.svh"
input logic clk, rst_n;
input trace_t events;
input logic [N_RX-1:0] input_stalled;
input logic output_stalled, output_fire, run;
input beat_t output_beat;
input live_t live;
input stats_command_t command;
output statistics_t live_stats, shadow_stats;
`include "tm_validate.svh"
endmodule
