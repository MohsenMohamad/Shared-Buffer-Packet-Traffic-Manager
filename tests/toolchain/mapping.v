// Small sequential cell-mapping/timing fixture, independent of production RTL.
module mapping(input clk, input a, input b, output reg y);
    always @(posedge clk) y <= a ^ b;
endmodule
