// Production external declaration only; no datapath implementation.
module tm_top #(
`include "tm_parameters.svh"
) (clk, rst_n, s_axis_tvalid, s_axis_tready, s_axis_tdata, s_axis_tkeep, s_axis_tlast, s_axis_tuser, m_axis_tvalid, m_axis_tready, m_axis_tdata, m_axis_tkeep, m_axis_tlast, m_axis_tuser, rx_status_valid, rx_status_code, rx_status_tag, rx_status_len, rx_status_qid, s_axil_awvalid, s_axil_awready, s_axil_awaddr, s_axil_awprot, s_axil_arvalid, s_axil_arready, s_axil_araddr, s_axil_arprot, s_axil_wvalid, s_axil_wready, s_axil_wdata, s_axil_wstrb, s_axil_bvalid, s_axil_bready, s_axil_bresp, s_axil_rvalid, s_axil_rready, s_axil_rdata, s_axil_rresp);
`include "tm_types.svh"
input logic clk, rst_n;
input logic [N_RX-1:0] s_axis_tvalid;
output logic [N_RX-1:0] s_axis_tready;
input logic [N_RX*DATA_W-1:0] s_axis_tdata;
input logic [N_RX*(DATA_W/8)-1:0] s_axis_tkeep;
input logic [N_RX-1:0] s_axis_tlast;
input logic [N_RX*64-1:0] s_axis_tuser;
output logic m_axis_tvalid;
input logic m_axis_tready;
output logic [DATA_W-1:0] m_axis_tdata;
output logic [DATA_W/8-1:0] m_axis_tkeep;
output logic m_axis_tlast;
output logic [63:0] m_axis_tuser;
output logic [N_RX-1:0] rx_status_valid;
output logic [N_RX*4-1:0] rx_status_code;
output logic [N_RX*16-1:0] rx_status_tag, rx_status_len;
output logic [N_RX*8-1:0] rx_status_qid;
input logic s_axil_awvalid;
output logic s_axil_awready;
input logic [31:0] s_axil_awaddr;
input logic [2:0] s_axil_awprot;
input logic s_axil_arvalid;
output logic s_axil_arready;
input logic [31:0] s_axil_araddr;
input logic [2:0] s_axil_arprot;
input logic s_axil_wvalid;
output logic s_axil_wready;
input logic [31:0] s_axil_wdata;
input logic [3:0] s_axil_wstrb;
output logic s_axil_bvalid;
input logic s_axil_bready;
output logic [1:0] s_axil_bresp;
output logic s_axil_rvalid;
input logic s_axil_rready;
output logic [31:0] s_axil_rdata;
output logic [1:0] s_axil_rresp;
`include "tm_validate.svh"
endmodule
