module symbolic_functions(input clk);
    wire [3:0] arbitrary=$anyseq;
    wire fixed_bit=$anyconst;
    logic past_valid=0;
    always @(posedge clk) begin
        past_valid<=1;
        if(past_valid) a_constant: assert(fixed_bit==$past(fixed_bit));
        c_zero: cover(arbitrary==0);
        c_ones: cover(arbitrary==15);
        c_change: cover(past_valid && arbitrary!=$past(arbitrary));
    end
endmodule
