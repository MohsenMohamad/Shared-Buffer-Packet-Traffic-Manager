`timescale 1ns/1ps
module tm_csr_top;
    import uvm_pkg::*;
    import tm_bench_pkg::*;
    import tm_csr_pkg::*;
    bit clk=0;
    always #5 clk=~clk;
    tm_csr_fixture_if f(clk);
    tm_axil_if bus(clk,f.rst_n);
    tm_csr_fixture fixture(clk,bus,f);
    initial begin
        tm_report_server server;
        server=new;
        uvm_report_server::set_server(server);
        uvm_config_db#(virtual tm_csr_fixture_if)::set(null,"uvm_test_top","fixture",f);
        uvm_config_db#(virtual tm_axil_if)::set(null,"uvm_test_top","bus",bus);
        run_test("tm_csr_test");
    end
    initial if($test$plusargs("TRACE")) begin $dumpfile("wave.vcd");$dumpvars(0,tm_csr_top);end
    final begin
        `ifdef VERILATOR
        $write("TM_CSR_COVERAGE\n");
        `endif
    end
    initial begin #2000000;$fatal(1,"TM_CSR_TIMEOUT");end
endmodule
