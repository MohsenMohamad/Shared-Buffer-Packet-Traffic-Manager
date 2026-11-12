// Startup reset only. History is initialized once, never reset with the DUT.
logic [1:0] startup=0;
logic seen_active=0;
always @(posedge clk) begin
    if(startup<2) begin assume(!rst_n); startup<=startup+1; end
    if(rst_n) seen_active<=1;
`ifdef CHANGE_COVER
    c_witness_change: cover(f_history_valid && witness!=$past(witness));
`elsif REACH_COVERS
    c_witness_zero: cover(f_history_valid && rst_n && witness=={W{1'b0}});
    c_witness_ones: cover(f_history_valid && rst_n && witness=={W{1'b1}});
    c_stimulus_change: cover(f_history_valid && rst_n && stimulus!=$past(stimulus));
    c_later_reset: cover(seen_active && !rst_n && $past(rst_n) &&
                         witness==$past(witness) && stimulus!=$past(stimulus));
`else
    if(f_history_valid) a_constant: assert(witness==$past(witness));
    if(f_history_valid && $past(rst_n) && !rst_n)
        a_reset_constant: assert(witness==$past(witness));
`endif
end
