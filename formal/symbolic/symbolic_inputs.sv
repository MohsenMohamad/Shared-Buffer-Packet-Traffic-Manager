// Copy this input/assumption recipe into new harnesses. Neither port is driven
// from DUT state. Only the witness is held; stimulus and later reset are free.
module symbolic_inputs #(parameter integer W=4)
    (input clk, rst_n, input [W-1:0] witness, stimulus);
    logic f_history_valid=0;
    always @(posedge clk) begin
        f_history_valid <= 1;
`ifndef OMIT_STABILITY
        if(f_history_valid) assume(witness==$past(witness));
`endif
    end
    // Qualification monitors are separate from the reusable assumption above.
`include "symbolic_checks.svh"
endmodule
