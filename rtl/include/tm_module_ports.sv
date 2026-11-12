// Remaining declaration-only component APIs. Storage APIs are implemented separately.

module tm_rx_arb_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input logic [N_RX-1:0] head_valid,
    input logic [N_RX-1:0] eligible,
    input logic [N_RX*BEAT_W-1:0] heads,
    input logic [N_RX-1:0] sop,
    output service_t service,
    output logic [N_RX-1:0] pop
);
`include "tm_validate.svh"
endmodule

module tm_admission_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input logic [N_RX-1:0] head_valid,
    input logic [N_RX*BEAT_W-1:0] heads,
    input service_t service,
    input config_t cfg,
    input live_t live,
    input cell_id_t available_cell,
    input desc_id_t available_desc,
    input abort_done_t abort_done,
    output logic [N_RX-1:0] eligible,
    output logic [N_RX-1:0] sop,
    output admission_t admit,
    output cell_alloc_t cell_alloc,
    output cell_link_write_t cell_link_write,
    output desc_write_t desc_write,
    output ram_write_t payload_write,
    output commit_t commit,
    output abort_mark_t abort_mark,
    output logic [N_RX*STATUS_W-1:0] status,
    output logic contexts_idle
);
`include "tm_validate.svh"
endmodule



module tm_resource_accounting_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input admission_t admit,
    input cell_alloc_t allocate,
    input cell_return_t release_cell,
    input abort_done_t abort_done,
    output cell_count_t assigned,
    output cell_count_t physical_free,
    output cell_count_t unreserved,
    output cell_count_t reserved_free,
    output logic [N_Q*CELL_COUNT_W-1:0] owned,
    output logic invariant_error
);
`include "tm_validate.svh"
endmodule

module tm_metadata_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input cell_link_write_t cell_write,
    input desc_link_write_t queue_write,
    input desc_write_t info_write,
    input cell_id_t tx_cell,
    input cell_id_t abort_cell,
    output cell_id_t tx_next,
    output cell_id_t abort_next,
    input logic [N_Q*DESC_ID_W-1:0] queue_heads,
    output logic [N_Q*DESC_INFO_W-1:0] head_info,
    input desc_id_t queue_head,
    output desc_id_t queue_next
);
`include "tm_validate.svh"
endmodule

module tm_drr_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input config_t cfg,
    input logic [N_Q*DESC_ID_W-1:0] heads,
    input logic [N_Q*DESC_COUNT_W-1:0] counts,
    input logic [N_Q*DESC_INFO_W-1:0] head_info,
    input commit_t commit,
    input logic tx_ready,
    input tx_done_t tx_done,
    output dispatch_t dispatch,
    output logic [N_Q*DEFICIT_W-1:0] deficits
);
`include "tm_validate.svh"
endmodule

module tm_packet_ram_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input ram_write_t write_req,
    input ram_read_t read_req,
    output ram_response_t response
);
`include "tm_validate.svh"
endmodule

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
endmodule

module tm_abort_reclaim_api import tm_fixed::*; #(
`include "tm_parameters.svh"
,
`define TM_ANSI_TYPES
`include "tm_types.svh"
`undef TM_ANSI_TYPES
) (
    input logic clk,
    input logic rst_n,
    input abort_mark_t abort_mark,
    input logic tx_cell_return_valid,
    output cell_id_t link_cell,
    input cell_id_t next_cell,
    output cell_return_t cell_return,
    output abort_done_t abort_done,
    output logic idle
);
`include "tm_validate.svh"
endmodule
