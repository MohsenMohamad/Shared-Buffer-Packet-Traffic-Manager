`timescale 1ns/1ps
module tm_foundation_top;
    import uvm_pkg::*;
    import tm_bench_types::*;
    import tm_bench_pkg::*;
    bit clk=0;
    always #5 clk=~clk;
    tm_observe_if obs(clk);
    tm_stream_if rx[N_RX](clk,obs.rst_n);
    tm_stream_if tx(clk,obs.rst_n);
    tm_axil_if bus(clk,obs.rst_n);
    a_reset_outputs: assert property (@(posedge clk) !obs.rst_n |-> !tx.valid && !bus.rsp.bvalid && !bus.rsp.rvalid)
        else $fatal(1,"TM_RESET_OUTPUT");
    tm_foundation_fixture fixture(clk,rx,tx,bus,obs);
    for(genvar p=0;p<N_RX;p++) begin : g_config
        initial uvm_config_db#(virtual tm_stream_if)::set(null,$sformatf("uvm_test_top.env.rx%0d",p),"vif",rx[p]);
    end
    initial begin
        tm_report_server server=new;
        uvm_report_server::set_server(server);
        uvm_config_db#(virtual tm_stream_if)::set(null,"uvm_test_top.env.tx","vif",tx);
        uvm_config_db#(virtual tm_axil_if)::set(null,"uvm_test_top.env.axil","vif",bus);
        uvm_config_db#(virtual tm_observe_if)::set(null,"uvm_test_top.env","observe",obs);
        run_test("tm_foundation_test");
    end
    initial if($test$plusargs("TRACE")) begin $dumpfile("wave.vcd");$dumpvars(0,tm_foundation_top);end
    initial begin #1000000;$fatal(1,"TM_FOUNDATION_TIMEOUT");end
endmodule
