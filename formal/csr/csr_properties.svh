// Production protocol monitor. It remembers accepted payloads independently
// of the slave's holds. No assumption couples AW to W or constrains B/R stalls.
logic f_past_valid=0;
logic f_aw=0,f_w=0,f_ar=0;
logic [31:0] f_awaddr,f_wdata,f_araddr;
logic [3:0] f_wstrb;
logic [2:0] f_write_age=0,f_read_age=0;
logic [5:0] f_aw_wait=0,f_w_wait=0,f_b_wait=0,f_r_wait=0;
always @(posedge clk) begin
    f_past_valid<=1;
    if (!rst_n) begin
        f_aw<=0;f_w<=0;f_ar<=0;f_write_age<=0;f_read_age<=0;
        f_aw_wait<=0;f_w_wait<=0;f_b_wait<=0;f_r_wait<=0;
        a_reset_outputs: assert(!bus_rsp.awready && !bus_rsp.wready && !bus_rsp.arready && !bus_rsp.bvalid && !bus_rsp.rvalid);
    end else begin
        // This availability obligation checks independent capture even if the
        // other channel never arrives. It does not require response fairness.
        a_aw_independent: assert(bus_rsp.awready == !f_aw);
        a_w_independent: assert(bus_rsp.wready == !f_w);
        a_ar_available: assert(bus_rsp.arready == !f_ar);
        if(f_aw) a_aw_hold: assert(have_aw && awaddr==f_awaddr);
        if(f_w) a_w_hold: assert(have_w && wdata==f_wdata && wstrb==f_wstrb);
        if(f_ar) a_ar_hold: assert(have_ar && araddr==f_araddr);
        a_b_causality: assert(!bus_rsp.bvalid || (f_aw && f_w));
        a_r_causality: assert(!bus_rsp.rvalid || f_ar);
        a_write_latency: assert(f_write_age<=3);
        a_read_latency: assert(f_read_age<=3);
        if(f_aw && f_w && !bus_rsp.bvalid) f_write_age<=f_write_age+1;else f_write_age<=0;
        if(f_ar && !bus_rsp.rvalid) f_read_age<=f_read_age+1;else f_read_age<=0;
        if(bus_req.awvalid && bus_rsp.awready) begin f_aw<=1;f_awaddr<=bus_req.awaddr;end
        if(bus_req.wvalid && bus_rsp.wready) begin f_w<=1;f_wdata<=bus_req.wdata;f_wstrb<=bus_req.wstrb;end
        if(bus_req.arvalid && bus_rsp.arready) begin f_ar<=1;f_araddr<=bus_req.araddr;end
        if(bus_rsp.bvalid && bus_req.bready) begin f_aw<=0;f_w<=0;end
        if(bus_rsp.rvalid && bus_req.rready) f_ar<=0;
        if(f_aw && !f_w && f_aw_wait<40) f_aw_wait<=f_aw_wait+1;else if(!f_aw) f_aw_wait<=0;
        if(f_w && !f_aw && f_w_wait<40) f_w_wait<=f_w_wait+1;else if(!f_w) f_w_wait<=0;
        if(bus_rsp.bvalid && !bus_req.bready && f_b_wait<40) f_b_wait<=f_b_wait+1;else f_b_wait<=0;
        if(bus_rsp.rvalid && !bus_req.rready && f_r_wait<40) f_r_wait<=f_r_wait+1;else f_r_wait<=0;
        c_aw_first: cover(f_aw_wait>=8 && bus_req.wvalid && bus_rsp.wready);
        c_w_first: cover(f_w_wait>=8 && bus_req.awvalid && bus_rsp.awready);
        c_same_edge: cover(bus_req.awvalid && bus_rsp.awready && bus_req.wvalid && bus_rsp.wready);
        c_stalled_responses: cover(f_b_wait>=5 && f_r_wait>=5);
        c_read_write_overlap: cover(read_execute && write_execute);
        c_busy_disable: cover(write_execute && write_word==32'h10 && wstrb[0] && !wdata[0] && !live.idle && write_response==SLVERR);
        c_snapshot: cover(stats_command.snapshot);
    end
    if(f_past_valid && rst_n && $past(rst_n)) begin
        if($past(bus_rsp.bvalid && !bus_req.bready)) begin
            a_b_stable: assert(bus_rsp.bvalid && bus_rsp.bresp==$past(bus_rsp.bresp));
        end
        if($past(bus_rsp.rvalid && !bus_req.rready)) begin
            a_r_stable: assert(bus_rsp.rvalid && {bus_rsp.rdata,bus_rsp.rresp}==$past({bus_rsp.rdata,bus_rsp.rresp}));
        end
        if($past(write_execute && write_response!=OKAY)) begin
            a_rejected_atomic: assert({run_q,wait_q,limits,quanta}==$past({run_q,wait_q,limits,quanta}));
        end
        if($past(write_execute)) begin
            a_one_b_response: assert(bus_rsp.bvalid && bus_rsp.bresp==$past(write_response));
        end
        if($past(read_execute)) begin
            a_one_r_response: assert(bus_rsp.rvalid && {bus_rsp.rdata,bus_rsp.rresp}==$past({read_value,read_response}));
        end
        if($past(invariant_q)) a_sticky_error: assert(invariant_q);
    end
end
