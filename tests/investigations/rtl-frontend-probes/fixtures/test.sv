module test_case #(
    parameter integer N_Q=2, N_CELL=16, N_DESC=8, N_RX=1, DEPTH=2,
    parameter integer CW=$clog2(N_CELL+1), SW=640+N_Q*320+N_Q*CW
)(output logic done);
logic clk=0;
always #5 clk=~clk;
logic rst_n=0,enable=1,s_valid=0,m_ready=0,s_ready,m_valid,empty,cfg_run;
logic [136:0] s_bits=0,m_bits;
logic [110:0] req_bits;
logic [40:0] rsp_bits;
logic [2:0] event_kind=0;
logic [7:0] event_qid=0;
logic [15:0] event_ncell=0;
logic [1:0] cmd_bits=0;
logic [N_Q*CW-1:0] owned=0;
logic [SW-1:0] stats_bits,shadow_bits;
logic [CW-1:0] last_limit;
// Independent harness record definitions for field access, matching the contract.
typedef struct packed {logic awvalid;logic[31:0]awaddr;logic[2:0]awprot;
logic wvalid;logic[31:0]wdata;logic[3:0]wstrb;logic bready;
logic arvalid;logic[31:0]araddr;logic[2:0]arprot;logic rready;} request_t;
typedef struct packed {logic awready,wready,bvalid;logic[1:0]bresp;
logic arready,rvalid;logic[31:0]rdata;logic[1:0]rresp;} response_t;
request_t req;
response_t rsp;
assign req_bits=req;
assign rsp=rsp_bits;
probe_unit #(.N_Q(N_Q),.N_CELL(N_CELL),.N_DESC(N_DESC),.N_RX(N_RX),
    .CELL_BYTES(16),.MAX_PACKET_BYTES(128),.RX_FIFO_DEPTH(DEPTH)) dut(.*);
task automatic tick;
    @(posedge clk); #1;
endtask
task automatic drive;
    @(negedge clk);
endtask
task automatic check(input logic condition,input string message);
    assert(condition) else $fatal(1,"PROBE_FAIL N_Q=%0d %s",N_Q,message);
endtask
task automatic read_csr(input logic[31:0] address,input logic[31:0] expected,input logic[1:0] response);
    drive();req.arvalid=1;req.araddr=address;
    tick();check(!rsp.arready,"AR captured");
    drive();req.arvalid=0;
    tick();check(rsp.rvalid && rsp.rdata==expected && rsp.rresp==response,"read value/response");
    tick();check(rsp.rvalid && rsp.rdata==expected,"R held under stall");
    drive();req.rready=1;tick();drive();req.rready=0;
endtask
initial begin
    done=0;req='0;
    tick();tick();drive();rst_n=1;tick();
    check(last_limit==CW'(N_CELL),"parameter-local cell limit reset");
    check(empty && !m_valid && s_ready,"reset FIFO");
    // Whole beat data, malformed keep and user bits survive stalled delivery.
    drive();s_bits={64'h123456789abcdef0,8'h55,1'b1,64'h1020304050607080};s_valid=1;
    check(!m_valid,"no fallthrough");tick();
    drive();s_valid=0;tick();
    check(m_valid && m_bits==s_bits,"held FIFO beat layout");
    tick();check(m_valid && m_bits==s_bits,"second stalled edge");
    // Simultaneous replacement while occupied.
    drive();m_ready=1;s_valid=1;s_bits={64'hfedcba9876543210,8'h81,1'b0,64'hffeeddccbbaa0099};tick();
    drive();s_valid=0;m_ready=0;tick();check(m_bits==s_bits,"simultaneous push/pop");
    drive();m_ready=1;tick();drive();m_ready=0;check(empty,"drain");
    // AW arrives without W. B must await W; B and a concurrent R can stall.
    drive();req.awvalid=1;req.awaddr=32'h400+32'((N_Q-1)*64);tick();
    drive();req.awvalid=0;tick();tick();check(!rsp.bvalid,"AW does not execute alone");
    drive();req.wvalid=1;req.wdata=3;req.wstrb=1;tick();
    drive();req.wvalid=0;tick();check(rsp.bvalid && rsp.bresp==0 && last_limit==3,"independent AW/W write");
    read_csr(32'h400+32'((N_Q-1)*64),3,0);
    check(rsp.bvalid,"B held during read");
    drive();req.bready=1;tick();drive();req.bready=0;
    // W before AW; byte strobe zero leaves configuration unchanged.
    req.wvalid=1;req.wdata=7;req.wstrb=0;tick();drive();req.wvalid=0;tick();
    drive();req.awvalid=1;req.awaddr=32'h400+32'((N_Q-1)*64);tick();drive();req.awvalid=0;tick();
    check(rsp.bvalid && rsp.bresp==0 && last_limit==3,"W-first zero-strobe write");
    drive();req.bready=1;tick();drive();req.bready=0;
    read_csr(32'h008,{8'd16,8'd8,8'(N_Q),8'(N_RX)},0);
    read_csr(32'h400+32'(N_Q*64),0,3);
    // Last queue lane is different for the two simultaneous configurations.
    drive();event_kind=1;event_qid=8'(N_Q-1);event_ncell=2;cmd_bits=2'b10;tick();
    check(shadow_bits==0,"snapshot captures pre-update stats");
    check(stats_bits[N_Q*CW+N_Q*320+64 +:64]==1,"global admitted");
    check(stats_bits[N_Q*CW+(N_Q-1)*320 +:64]==1,"last queue admitted lane");
    check(stats_bits[(N_Q-1)*CW +:CW]==2,"post-update high-water");
    drive();event_kind=2;cmd_bits=0;tick();
    check(stats_bits[N_Q*CW+(N_Q-1)*320+64 +:64]==1,"resource drop enum");
    drive();event_kind=3;s_bits={64'h0,8'h55,1'b1,{56'h0,8'(N_Q-1)}};tick();
    check(stats_bits[N_Q*CW+(N_Q-1)*320+3*64 +:64]==4,"TX keep popcount/lane");
    drive();event_kind=0;cmd_bits=2'b10;tick();
    check(shadow_bits==stats_bits,"snapshot without event");
    read_csr(32'h400+32'((N_Q-1)*64)+32'd24,1,0);
    drive();cmd_bits=2'b01;tick();check(stats_bits==0 && shadow_bits==0,"disabled idle clear");
    drive();cmd_bits=0;rst_n=0;tick();check(!m_valid && !s_ready,"reset suppression");
    $display("PROBE_CASE_PASS N_Q=%0d N_CELL=%0d N_RX=%0d DEPTH=%0d STATS_W=%0d",N_Q,N_CELL,N_RX,DEPTH,SW);
    done=1;
end
endmodule
module test;
wire a,b;
test_case #(.N_Q(2),.N_CELL(16),.N_DESC(8),.N_RX(1),.DEPTH(2)) u_small(a);
test_case #(.N_Q(4),.N_CELL(32),.N_DESC(16),.N_RX(2),.DEPTH(4)) u_large(b);
initial begin wait(a && b);$display("PROBE_PASS two independent configurations");$finish;end
initial begin #5000;$fatal(1,"PROBE_TIMEOUT");end
endmodule
