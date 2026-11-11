module symbolic_attributes(input clk);
    (* anyseq *) logic [3:0] arbitrary;
    (* anyconst *) logic fixed_bit;
    logic past_valid=0;
    always @(posedge clk) begin
        past_valid<=1;
        if(past_valid) a_constant: assert(fixed_bit==$past(fixed_bit));
        c_zero: cover(arbitrary==0);
        c_ones: cover(arbitrary==15);
        c_change: cover(past_valid && arbitrary!=$past(arbitrary));
    end
endmodule
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
module symbolic_ports(input clk,rst_n,enable,input [3:0] arbitrary);
    logic [1:0] startup=0;
    logic past_valid=0;
    logic [3:0] value;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)value<=0;
        else if(enable)
`ifdef MUTATE
            value<=arbitrary^4'b0001;
`else
            value<=arbitrary;
`endif
    always @(posedge clk) begin
        past_valid<=1;
        if(startup<2)begin assume(!rst_n);startup<=startup+1;end
        if(past_valid && $past(rst_n) && rst_n && $past(enable))
            a_capture: assert(value==$past(arbitrary));
        c_zero: cover(past_valid && rst_n && enable && arbitrary==0);
        c_ones: cover(past_valid && rst_n && enable && arbitrary==15);
        c_later_reset: cover(past_valid && startup==2 && !rst_n && $past(rst_n && enable));
    end
endmodule
