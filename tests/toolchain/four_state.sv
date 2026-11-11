// Portable requirement reproducer, intentionally outside the two-state G0 suite.
module four_state;
    logic [3:0] value = 4'bxxxx;
    initial begin
        #1;
        assert ($isunknown(value)) else $fatal(1, "TM_FOUR_STATE_UNSUPPORTED");
        $display("TM_FOUR_STATE_PASS");
        $finish;
    end
endmodule
