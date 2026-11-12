module uvm_dpi_probe;
    import uvm_pkg::*;
    // Expose only the probed HDL variable to VPI, not every UVM implementation detail.
    logic [31:0] target /* verilator public_flat_rw */ =32'h12345678;
    uvm_hdl_data_t value;
    initial begin
        #1;
        assert(uvm_re_match("/^packet_[0-9]+$/", "packet_42")==0) else $fatal(1,"DPI_REGEX_POSITIVE");
        assert(uvm_re_match("/^packet_[0-9]+$/", "packet_bad")!=0) else $fatal(1,"DPI_REGEX_NEGATIVE");
        assert(uvm_hdl_check_path("uvm_dpi_probe.target")!=0) else $fatal(1,"DPI_PATH");
        assert(uvm_hdl_read("uvm_dpi_probe.target",value)!=0 && value[31:0]==32'h12345678) else $fatal(1,"DPI_READ");
        assert(uvm_hdl_deposit("uvm_dpi_probe.target",uvm_hdl_data_t'(32'hbeef1024))!=0) else $fatal(1,"DPI_DEPOSIT");
        #1;
        assert(target==32'hbeef1024) else $fatal(1,"DPI_DEPOSIT_EFFECT");
        $display("TM_UVM_DPI_PASS regex=positive,negative hdl=path,read,deposit");$finish;
    end
endmodule
