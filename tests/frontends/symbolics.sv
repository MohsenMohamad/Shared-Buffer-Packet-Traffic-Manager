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
