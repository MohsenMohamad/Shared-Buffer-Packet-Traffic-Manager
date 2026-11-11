// Independent passive model. Requests originate exclusively from bus
// handshakes; event inputs originate from the declared component fixture.
class tm_csr_model extends uvm_component;
    `uvm_component_utils(tm_csr_model)
    virtual tm_csr_fixture_if f;
    virtual tm_axil_if bus;
    bit run,wait_mode,sticky,aw,w,ar,b_sent,r_sent;
    bit [31:0] addr,data,read_addr,expected_data;
    bit [3:0] strb;
    axil_resp_t expected_b,expected_r;
    int limits[N_Q],quantum[N_Q],high[N_Q],shadow_high[N_Q];
    longint unsigned g[10],qstats[N_Q][5],sg[10],sq[N_Q][5];
    int cycle,aw_cycle,w_cycle,aw_age,w_age,read_age,write_age;
    int checked_reads,checked_writes,snapshots,clears,rollovers,collisions,reset_pending;
    int b_stalls,r_stalls,overlaps,logfile;
    bit write_stalled,write_overlap;
    bit [31:0] prior_rdata;
    axil_resp_t prior_bresp,prior_rresp;
    bit prior_bstall,prior_rstall;
    covergroup bus_coverage with function sample(int order,bit stalled,bit overlap);
        arrival_order: coverpoint order {bins w_first={0};bins simultaneous={1};bins aw_first={2};}
        b_stall: coverpoint stalled;
        concurrent_read: coverpoint overlap;
        ordering: cross arrival_order,b_stall,concurrent_read;
    endgroup
    function new(string name,uvm_component parent);
        super.new(name,parent);bus_coverage=new;logfile=$fopen("transactions.jsonl","w");reset_model();
    endfunction
    function void reset_model();
        run=0;wait_mode=0;sticky=0;aw=0;w=0;ar=0;b_sent=0;r_sent=0;
        aw_age=0;w_age=0;read_age=0;write_age=0;prior_bstall=0;prior_rstall=0;
        foreach(limits[q]) begin limits[q]=N_CELL;quantum[q]=MAX_PACKET_BYTES;high[q]=0;shadow_high[q]=0;end
        foreach(g[k]) begin g[k]=0;sg[k]=0;end
        foreach(qstats[q,k]) begin qstats[q][k]=0;sq[q][k]=0;end
    endfunction
    function bit decode(bit [31:0] address,output int word_addr,output int q);
        word_addr=int'(address & 32'hfffffffc);q=-1;
        if(address>=32'h400 && address<32'h400+32'(64*N_Q)) q=int'((address-32'h400)/64);
        return (address<32'h038 || (address>=32'h100 && address<32'h150) || q>=0);
    endfunction
    function bit [31:0] value(int a,int q);
        if(q>=0) begin
            case(a%64)
                0:return 32'(limits[q]);4:return 32'(quantum[q]);
                8:return 32'(f.live.owned[q*CELL_COUNT_W+:CELL_COUNT_W]);
                12:return 32'(f.live.queued[q*DESC_COUNT_W+:DESC_COUNT_W]);
                16:return 32'(f.live.deficit[q*DEFICIT_W+:DEFICIT_W]);
                20:return 32'(shadow_high[q]);
                default:return 32'(sq[q][(a%64-24)/8] >> ((a%8)*8));
            endcase
        end
        if(a>=256 && a<336) return 32'(sg[(a-256)/8] >> ((a%8)*8));
        case(a)
            0:return 'h544d0100;4:return 'h10000;
            8:return {8'(CELL_BYTES),8'd8,8'(N_Q),8'(N_RX)};
            12:return {16'(N_DESC),16'(N_CELL)};
            16:return 32'(run);
            20:return {28'b0,(sticky || f.live.invariant_error),f.initialized,f.live.idle,run};
            32:return 32'(wait_mode);36:return 32'(f.live.unreserved);
            40:return 32'(f.live.reserved_free);44:return 32'(f.live.free_desc);
            48:return 32'(SCHED_MODE);52:return 32'(MAX_PACKET_BYTES);
            default:return 0;
        endcase
    endfunction
    function axil_resp_t predict_write(output bit snapshot,output bit clear);
        int a,q;
        bit [31:0] merged,mask;
        snapshot=0;clear=0;
        if(!decode(addr,a,q)) return DECERR;
        if(addr%4!=0) return SLVERR;
        if(strb==0) return OKAY;
        mask=0;for(int lane=0;lane<4;lane++) if(strb[lane]) mask|=32'hff<<(lane*8);
        merged=(value(a,q)&~mask)|(data&mask);
        if(q>=0 && (a%64==0 || a%64==4)) begin
            if(run || !f.live.idle) return SLVERR;
            if(a%64==0) begin
                if(merged<1 || merged>32'(N_CELL)) return SLVERR;
                limits[q]=int'(merged);
            end else begin
                if(merged<64 || merged>4096) return SLVERR;
                quantum[q]=int'(merged);
            end
            return OKAY;
        end
        case(a)
            16:begin if(!merged[0] && !f.live.idle) return SLVERR;run=merged[0];end
            24:snapshot=merged[0];
            28:begin
                if(merged[0] && (run || !f.live.idle)) return SLVERR;
                clear=merged[0];
            end
            32:begin
                if(run || !f.live.idle || merged>1) return SLVERR;
                wait_mode=merged[0];
            end
            default:return SLVERR;
        endcase
        return OKAY;
    endfunction
    function void add_global(int k,longint unsigned delta);
        longint unsigned next_value=g[k]+delta;
        if(CSR_COUNTER_W<64) next_value&=(64'h1<<CSR_COUNTER_W)-1;
        if(next_value<g[k]) rollovers++;
        g[k]=next_value;
    endfunction
    function void add_queue(int q,int k,longint unsigned delta);
        if(q<0 || q>=N_Q) `uvm_fatal("CSR_EVENT_QID","invalid fixture qid")
        qstats[q][k]+=delta;
        if(CSR_COUNTER_W<64) qstats[q][k]&=(64'h1<<CSR_COUNTER_W)-1;
    endfunction
    function void statistics_step(bit snapshot,bit clear,bit previous_run);
        trace_t e=f.events;
        int owned[N_Q];
        if(clear) begin
            foreach(g[k]) begin g[k]=0;sg[k]=0;end
            foreach(qstats[q,k]) begin qstats[q][k]=0;sq[q][k]=0;end
            foreach(high[q]) begin high[q]=0;shadow_high[q]=0;end
            clears++;return;
        end
        if(snapshot) begin
            foreach(g[k]) sg[k]=g[k];
            foreach(qstats[q,k]) sq[q][k]=qstats[q][k];
            foreach(high[q]) shadow_high[q]=high[q];
            snapshots++;
            if(e!='0 || f.output_fire || f.input_stalled!=0 || f.output_stalled) collisions++;
        end
        foreach(owned[q]) owned[q]=int'(f.live.owned[q*CELL_COUNT_W+:CELL_COUNT_W]);
        if(e.rx_service.valid && e.rx_service.sop) add_global(0,1);
        if(e.admit.valid) begin
            if(e.admit.accept) begin
                add_global(1,1);add_queue(int'(e.admit.qid),0,1);owned[int'(e.admit.qid)]+=int'(e.admit.ncell);
            end else case(e.admit.reason)
                BAD_QID,BAD_LENGTH:add_global(4,1);
                QUEUE_LIMIT,NO_DESCRIPTOR,NO_CELLS:begin add_global(3,1);add_queue(int'(e.admit.qid),1,1);end
                default:`uvm_fatal("CSR_EVENT_REASON","invalid rejection fixture")
            endcase
        end
        if(e.commit.valid) add_global(2,1);
        if(e.abort_mark.valid) begin add_global(4,1);add_queue(int'(e.abort_mark.qid),4,1);end
        if(e.tx_done.valid) begin add_global(5,1);add_queue(int'(e.tx_done.qid),2,1);end
        if(f.output_fire) begin
            for(int lane=0;lane<8;lane++) if(f.output_beat.keep[lane]) begin add_global(6,1);add_queue(int'(f.output_beat.user[7:0]),3,1);end
        end
        if(previous_run) add_global(7,1);
        if(f.input_stalled!=0) add_global(8,1);
        if(f.output_stalled) add_global(9,1);
        if(e.cell_free.valid && !e.cell_free.abort_source) owned[int'(e.cell_free.qid)]--;
        if(e.abort_done.valid) owned[int'(e.abort_done.qid)]-=int'(e.abort_done.ncell);
        foreach(owned[q]) if(owned[q]>high[q]) high[q]=owned[q];
    endfunction
    function void compare_state();
        if(f.cfg.run!=run || f.cfg.wait_mode!=wait_mode || f.cfg.initialized!=f.initialized) `uvm_fatal("CSR_CONFIG","configuration mismatch")
        foreach(limits[q]) begin
            if(f.cfg.cell_limit[q*CELL_COUNT_W+:CELL_COUNT_W]!=CELL_COUNT_W'(limits[q]) ||
                f.cfg.quantum[q*13+:13]!=13'(quantum[q])) `uvm_fatal("CSR_CONFIG","queue configuration mismatch")
            if(f.live_stats.high_water[q*CELL_COUNT_W+:CELL_COUNT_W]!=CELL_COUNT_W'(high[q]) ||
                f.shadow_stats.high_water[q*CELL_COUNT_W+:CELL_COUNT_W]!=CELL_COUNT_W'(shadow_high[q])) `uvm_fatal("CSR_HIGH_WATER","high-water mismatch")
        end
        foreach(g[k]) if(f.live_stats.global_counts[k*64+:64]!=g[k] || f.shadow_stats.global_counts[k*64+:64]!=sg[k])
            `uvm_fatal("CSR_GLOBAL_STATS",$sformatf("counter %0d expected live=%0d shadow=%0d actual=%0d/%0d",k,g[k],sg[k],f.live_stats.global_counts[k*64+:64],f.shadow_stats.global_counts[k*64+:64]))
        foreach(qstats[q,k]) if(f.live_stats.queue_counts[(q*5+k)*64+:64]!=qstats[q][k] || f.shadow_stats.queue_counts[(q*5+k)*64+:64]!=sq[q][k]) `uvm_fatal("CSR_QUEUE_STATS","queue counter mismatch")
    endfunction
    task run_phase(uvm_phase phase);
        bit snapshot,clear,previous_run;
        int a,q,order;
        forever begin
            @(posedge f.clk);cycle++;
            if(!f.rst_n) begin
                if(aw || w || ar || bus.rsp.bvalid || bus.rsp.rvalid) reset_pending++;
                reset_model();
                if(bus.rsp.bvalid || bus.rsp.rvalid || bus.rsp.awready || bus.rsp.wready || bus.rsp.arready) `uvm_fatal("CSR_RESET","bus active in reset")
                continue;
            end
            compare_state();
            if(prior_bstall && (!bus.rsp.bvalid || bus.rsp.bresp!=prior_bresp)) `uvm_fatal("CSR_B_HOLD","B changed while stalled")
            if(prior_rstall && (!bus.rsp.rvalid || bus.rsp.rdata!=prior_rdata || bus.rsp.rresp!=prior_rresp)) `uvm_fatal("CSR_R_HOLD","R changed while stalled")
            prior_bstall=bus.rsp.bvalid && !bus.req.bready;prior_bresp=bus.rsp.bresp;
            prior_rstall=bus.rsp.rvalid && !bus.req.rready;prior_rdata=bus.rsp.rdata;prior_rresp=bus.rsp.rresp;
            if(bus.rsp.bvalid && (!b_sent || bus.rsp.bresp!=expected_b)) `uvm_fatal("CSR_WRITE_RESPONSE","unexpected B response")
            if(bus.rsp.rvalid && (!r_sent || bus.rsp.rdata!=expected_data || bus.rsp.rresp!=expected_r)) `uvm_fatal("CSR_READ_RESPONSE",$sformatf("addr=%h expected=%h/%d actual=%h/%d",read_addr,expected_data,expected_r,bus.rsp.rdata,bus.rsp.rresp))
            if(aw && !w) begin aw_age++;if(aw_age>40) `uvm_fatal("CSR_AW_W_INDEPENDENCE","W never accepted after AW") end
            if(w && !aw) begin w_age++;if(w_age>40) `uvm_fatal("CSR_AW_W_INDEPENDENCE","AW never accepted after W") end
            if((bus.req.awvalid && !aw && !b_sent && !bus.rsp.awready) ||
               (bus.req.wvalid && !w && !b_sent && !bus.rsp.wready)) begin
                write_age++;if(write_age>3) `uvm_fatal("CSR_AW_W_INDEPENDENCE","independent channel refused while peer absent")
            end else write_age=0;
            if((b_sent && !bus.rsp.bvalid) || (r_sent && !bus.rsp.rvalid)) begin read_age++;if(read_age>3) `uvm_fatal("CSR_RESPONSE_LATENCY","response late") end else read_age=0;
            if(bus.rsp.bvalid && !bus.req.bready) begin b_stalls++;write_stalled=1;end
            if(bus.rsp.rvalid && !bus.req.rready) r_stalls++;
            if((aw || w || bus.req.awvalid || bus.req.wvalid) && (ar || bus.req.arvalid)) write_overlap=1;
            snapshot=0;clear=0;previous_run=run;
            // Read prediction precedes all model writes/snapshots on this edge.
            if(ar && !r_sent) begin
                expected_data=0;expected_r=OKAY;
                if(!decode(read_addr,a,q)) expected_r=DECERR;
                else if(read_addr%4!=0) expected_r=SLVERR;
                else expected_data=value(a,q);
                r_sent=1;
            end
            if(aw && w && !b_sent) begin expected_b=predict_write(snapshot,clear);b_sent=1;end
            if(f.command.snapshot!=snapshot || f.command.clear!=clear) `uvm_fatal("CSR_COMMAND","command missing, duplicated or executed on wrong edge")
            statistics_step(snapshot,clear,previous_run);sticky|=f.live.invariant_error;
            if(bus.req.awvalid && bus.rsp.awready) begin
                if(aw || b_sent) `uvm_fatal("CSR_OUTSTANDING","extra AW accepted")
                aw=1;addr=bus.req.awaddr;aw_cycle=cycle;aw_age=0;
            end
            if(bus.req.wvalid && bus.rsp.wready) begin
                if(w || b_sent) `uvm_fatal("CSR_OUTSTANDING","extra W accepted")
                w=1;data=bus.req.wdata;strb=bus.req.wstrb;w_cycle=cycle;w_age=0;
            end
            if(bus.req.arvalid && bus.rsp.arready) begin
                if(ar) `uvm_fatal("CSR_OUTSTANDING","extra AR accepted")
                ar=1;read_addr=bus.req.araddr;
            end
            if(bus.rsp.bvalid && bus.req.bready) begin
                order=(aw_cycle<w_cycle)?2:((aw_cycle>w_cycle)?0:1);
                bus_coverage.sample(order,write_stalled,write_overlap);
                overlaps+=int'(write_overlap);write_stalled=0;write_overlap=0;
                $fdisplay(logfile,"{\"cycle\":%0d,\"write\":true,\"addr\":%0d,\"data\":%0d,\"strb\":%0d,\"resp\":%0d,\"order\":%0d}",cycle,addr,data,strb,bus.rsp.bresp,order);
                aw=0;w=0;b_sent=0;checked_writes++;
            end
            if(bus.rsp.rvalid && bus.req.rready) begin
                $fdisplay(logfile,"{\"cycle\":%0d,\"write\":false,\"addr\":%0d,\"data\":%0d,\"resp\":%0d}",cycle,read_addr,bus.rsp.rdata,bus.rsp.rresp);
                ar=0;r_sent=0;checked_reads++;
            end
        end
    endtask
endclass
