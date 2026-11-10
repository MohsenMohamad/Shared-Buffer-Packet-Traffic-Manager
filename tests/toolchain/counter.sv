// Capability fixture: enabled modulo-eight counter, no environment assumptions.
module counter(input clk, input enable);
    reg [2:0] count = 0;
    reg past_valid = 0;
    always @(posedge clk) begin
        past_valid <= 1;
        if (enable)
`ifdef MUTATE
            count <= count + 3'd2;
`else
            count <= count + 3'd1;
`endif
        if (past_valid) begin
            if ($past(enable))
                a_step: assert(count == 3'($past(count) + 3'd1));
            else
                a_hold: assert(count == $past(count));
            c_wrap: cover($past(count) == 7 && count == 0);
        end
    end
endmodule
