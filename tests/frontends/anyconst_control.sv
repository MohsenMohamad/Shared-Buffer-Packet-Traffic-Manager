// Diagnostic rejected control only. Slang accepts this decoration but does not
// create native symbolic cells. It must never enter the production source set.
module anyconst_control #(parameter integer W=4)(input clk, rst_n,
                                                input [W-1:0] stimulus);
    (* anyconst *) logic [W-1:0] witness;
    logic f_history_valid=0;
    always @(posedge clk) f_history_valid<=1;
`include "symbolic_checks.svh"
endmodule
