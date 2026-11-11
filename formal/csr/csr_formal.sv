module csr_formal(input clk);
localparam integer DATA_W=64,N_RX=1,N_Q=2,CELL_BYTES=16,N_CELL=16,N_DESC=8,
    MAX_PACKET_BYTES=128,RX_FIFO_DEPTH=2,MEM_RD_LATENCY=1,TX_FIFO_DEPTH=4,
    SCHED_MODE=1,QUANTUM_DEFAULT=128,TRACE_ENABLE=1,CELL_ID_W=4,
    DESC_ID_W=3,CELL_COUNT_W=5,DESC_COUNT_W=4,DEFICIT_W=13;
`include "tm_types.svh"
(* anyseq *) logic rst_n,initialized;
(* anyseq *) axil_request_t bus_req;
(* anyseq *) live_t live;
(* anyseq *) statistics_t live_stats,shadow_stats;
axil_response_t bus_rsp;
logic [1:0] startup=0;
logic past_valid=0;
always @(posedge clk) begin
    past_valid<=1;
    if(startup<2) begin assume(!rst_n);startup<=startup+1;end
    // Legal AXI sources hold valid and payload through a stall. Reset cancels
    // the obligation. All response-ready, live/config/event inputs are arbitrary.
    if(past_valid && rst_n && $past(rst_n)) begin
        if($past(bus_req.awvalid && !bus_rsp.awready)) begin
            assume(bus_req.awvalid);assume({bus_req.awaddr,bus_req.awprot}==$past({bus_req.awaddr,bus_req.awprot}));
        end
        if($past(bus_req.wvalid && !bus_rsp.wready)) begin
            assume(bus_req.wvalid);assume({bus_req.wdata,bus_req.wstrb}==$past({bus_req.wdata,bus_req.wstrb}));
        end
        if($past(bus_req.arvalid && !bus_rsp.arready)) begin
            assume(bus_req.arvalid);assume({bus_req.araddr,bus_req.arprot}==$past({bus_req.araddr,bus_req.arprot}));
        end
    end
end
tm_axil_regs_api #(.N_RX(1),.N_Q(2),.CELL_BYTES(16),.N_CELL(16),.N_DESC(8),.MAX_PACKET_BYTES(128)) dut(
    .clk(clk),.rst_n(rst_n),.initialized(initialized),.bus_req(bus_req),.bus_rsp(bus_rsp),
    .live(live),.live_stats(live_stats),.shadow_stats(shadow_stats));
endmodule
