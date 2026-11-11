class tm_csr_access extends uvm_sequence #(tm_axil_item);
    `uvm_object_utils(tm_csr_access)
    bit write;
    bit [31:0] address,data;
    bit [3:0] strb=15;
    int aw_delay,w_delay,stall;
    axil_resp_t expected=OKAY;
    function new(string name="csr_access");super.new(name);endfunction
    task body();
        tm_axil_item x=new,response;
        x.write=write;x.addr=address;x.data=data;x.strb=strb;
        x.aw_delay=aw_delay;x.w_delay=w_delay;x.response_stall=stall;
        start_item(x);finish_item(x);get_response(response);
        if(response.response!=expected) `uvm_fatal("CSR_ACCESS",$sformatf("address=%h response=%0d expected=%0d",address,response.response,expected))
        data=response.data;
    endtask
endclass

class tm_csr_test extends uvm_test;
    `uvm_component_utils(tm_csr_test)
    virtual tm_csr_fixture_if f;
    virtual tm_axil_if bus;
    tm_axil_agent agent;
    tm_csr_model model;
    tm_register_block registers;
    tm_axil_adapter adapter;
    uvm_reg_predictor #(tm_axil_item) predictor;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual tm_csr_fixture_if)::get(this,"","fixture",f) ||
           !uvm_config_db#(virtual tm_axil_if)::get(this,"","bus",bus)) `uvm_fatal("CONFIG","CSR interfaces missing")
        uvm_config_db#(virtual tm_axil_if)::set(this,"agent","vif",bus);
        agent=tm_axil_agent::type_id::create("agent",this);
        model=tm_csr_model::type_id::create("model",this);model.f=f;model.bus=bus;
        registers=new;registers.build();adapter=new;predictor=new("predictor",this);
    endfunction
    function void connect_phase(uvm_phase phase);
        registers.default_map.set_sequencer(agent.sequencer,adapter);
        registers.default_map.set_auto_predict(0);
        predictor.map=registers.default_map;predictor.adapter=adapter;
        agent.monitor.transactions.connect(predictor.bus_in);
    endfunction
    task access(bit write,bit [31:0] address,bit [31:0] data=0,bit [3:0] strb=15,
        axil_resp_t expected=OKAY,int order=1,int stall=0,int separation=7);
        tm_csr_access seq=new;
        seq.write=write;seq.address=address;seq.data=data;seq.strb=strb;seq.expected=expected;
        seq.aw_delay=(order==0)?separation:0;seq.w_delay=(order==2)?separation:0;seq.stall=stall;
        seq.start(agent.sequencer);
    endtask
    task reset_dut();
        @(negedge f.clk);f.rst_n=0;f.events='0;f.busy=0;
        f.input_stalled=0;f.output_stalled=0;f.output_fire=0;f.output_beat='0;f.invariant_error=0;
        repeat(3) @(negedge f.clk);
        f.rst_n=1;repeat(3) @(negedge f.clk);
    endtask
    task pulse(trace_t events,bit output_fire=0,bit [7:0] keep=0,int q=0);
        @(negedge f.clk);f.events=events;f.output_fire=output_fire;
        f.output_beat='0;f.output_beat.keep=keep;f.output_beat.user[7:0]=8'(q);f.output_beat.last=output_fire;
        @(negedge f.clk);f.events='0;f.output_fire=0;f.output_beat='0;
    endtask
    task packet(int q,int nbytes=7);
        trace_t e='0;
        e.rx_service.valid=1;e.rx_service.sop=1;e.admit.valid=1;e.admit.accept=1;
        e.rx_service.beat.keep=8'((1<<nbytes)-1);e.rx_service.beat.last=1;
        e.rx_service.beat.user={24'b0,16'b0,16'(nbytes),8'(q)};
        e.admit.length=16'(nbytes);
        e.admit.qid=8'(q);e.admit.ncell=CELL_COUNT_W'(1);e.cell_alloc.valid=1;
        e.commit.valid=1;e.commit.qid=Q_ID_W'(q);
        pulse(e);
        e='0;e.dispatch.valid=1;e.dispatch.qid=Q_ID_W'(q);pulse(e);
        e='0;e.cell_free.valid=1;e.cell_free.qid=Q_ID_W'(q);
        e.tx_done.valid=1;e.tx_done.qid=Q_ID_W'(q);e.tx_done.length=16'(nbytes);
        pulse(e,1,8'((1<<nbytes)-1),q);
    endtask
    task pending_reset(int phase_kind);
        // Raw directed channel control is confined to the idle UVM driver's
        // reset probe; the passive model/agent still observe every handshake.
        @(negedge f.clk);
        bus.req.awaddr='h10;bus.req.wdata=1;bus.req.wstrb=15;bus.req.araddr='h14;
        bus.req.awvalid=(phase_kind!=1);bus.req.wvalid=(phase_kind!=0);
        bus.req.arvalid=(phase_kind>=2);bus.req.bready=0;bus.req.rready=0;
        @(posedge f.clk);
        @(negedge f.clk);bus.req.awvalid=0;bus.req.wvalid=0;bus.req.arvalid=0;
        if(phase_kind>=2) repeat(3) @(negedge f.clk);
        reset_dut();bus.req='0;
        repeat(4) @(negedge f.clk);
        access(0,'h10);access(0,'h100);
    endtask
    task outstanding_probe();
        bit aw_done,w_done,ar_done;
        @(negedge f.clk);
        bus.req.awvalid=1;bus.req.awaddr='h10;bus.req.wvalid=1;bus.req.wdata=0;bus.req.wstrb=15;
        bus.req.arvalid=1;bus.req.araddr='h10;bus.req.bready=0;bus.req.rready=0;
        @(posedge f.clk);
        @(negedge f.clk);bus.req.awvalid=0;bus.req.wvalid=0;bus.req.arvalid=0;
        repeat(3) @(negedge f.clk);
        bus.req.awvalid=1;bus.req.awaddr='h20;bus.req.wvalid=1;bus.req.wdata=1;
        bus.req.arvalid=1;bus.req.araddr='h20;
        repeat(8) begin
            @(posedge f.clk);
            if(bus.rsp.awready || bus.rsp.wready || bus.rsp.arready) `uvm_fatal("CSR_OUTSTANDING","accepted new request before response retirement")
        end
        @(negedge f.clk);bus.req.bready=1;bus.req.rready=1;
        aw_done=0;w_done=0;ar_done=0;
        while(!aw_done || !w_done || !ar_done) begin
            @(posedge f.clk);
            aw_done|=bus.req.awvalid && bus.rsp.awready;
            w_done|=bus.req.wvalid && bus.rsp.wready;
            ar_done|=bus.req.arvalid && bus.rsp.arready;
            @(negedge f.clk);
            if(aw_done) bus.req.awvalid=0;
            if(w_done) bus.req.wvalid=0;
            if(ar_done) bus.req.arvalid=0;
        end
        repeat(5) @(negedge f.clk);
        bus.req='0;
    endtask
    task snapshot_collision();
        // Schedule from accepted AW/W, independently of the DUT command or
        // statistic outputs. The following edge executes the held command.
        fork
            access(1,'h18,1,15,OKAY,1,8);
            begin
                trace_t collision='0;
                bit aw_seen=0,w_seen=0;
                while(!aw_seen || !w_seen) begin
                    @(posedge f.clk);
                    aw_seen|=bus.req.awvalid && bus.rsp.awready;
                    w_seen|=bus.req.wvalid && bus.rsp.wready;
                end
                collision.rx_service.valid=1;collision.rx_service.sop=1;
                collision.admit.valid=1;collision.admit.accept=1;collision.admit.ncell=3;
                @(negedge f.clk);f.events=collision;
                @(negedge f.clk);f.events='0;
            end
        join
        access(0,'h108);access(0,'h10c);access(0,'h414);
        begin
            trace_t cleanup='0;
            cleanup.abort_mark.valid=1;cleanup.abort_mark.reserved=3;pulse(cleanup);
            cleanup='0;cleanup.abort_done.valid=1;cleanup.abort_done.ncell=3;pulse(cleanup);
        end
        access(1,'h18,1);access(0,'h414);
    endtask
    task abort_release_collision();
        trace_t e='0;
        e.admit.valid=1;e.admit.accept=1;e.admit.ncell=2;pulse(e);
        e='0;e.cell_alloc.valid=1;pulse(e);
        e='0;e.abort_mark.valid=1;e.abort_mark.allocated=1;e.abort_mark.reserved=2;pulse(e);
        // A physical abort return preserves H. A new reservation on this edge
        // must still raise high-water from two to three.
        e='0;e.cell_free.valid=1;e.cell_free.abort_source=1;
        e.admit.valid=1;e.admit.accept=1;e.admit.ncell=1;e.admit.desc=1;pulse(e);
        e='0;e.abort_done.valid=1;e.abort_done.ncell=2;pulse(e);
        e='0;e.abort_mark.valid=1;e.abort_mark.desc=1;e.abort_mark.reserved=1;pulse(e);
        // New admission and completion merge before high-water comparison;
        // there is no transient four-cell peak from applying admission first.
        e='0;e.admit.valid=1;e.admit.accept=1;e.admit.ncell=3;
        e.abort_done.valid=1;e.abort_done.desc=1;e.abort_done.ncell=1;pulse(e);
        e='0;e.abort_mark.valid=1;e.abort_mark.reserved=3;pulse(e);
        e='0;e.abort_done.valid=1;e.abort_done.ncell=3;pulse(e);
    endtask
    task run_phase(uvm_phase phase);
        uvm_status_e status;
        uvm_reg_data_t data;
        trace_t e;
        int q;
        phase.raise_objection(this);
        f.rst_n=0;f.events='0;f.busy=0;f.input_stalled=0;f.output_stalled=0;f.output_fire=0;f.output_beat='0;f.invariant_error=0;
        reset_dut();
        outstanding_probe();access(1,'h20,0);
        // Deliberate arrival-order x response-stall x concurrent-read matrix.
        for(int order=0;order<3;order++) for(int stalled=0;stalled<2;stalled++) for(int overlap=0;overlap<2;overlap++) begin
            fork
                access(1,'h20,0,15,OKAY,order,(stalled!=0)?12:0,24);
                begin if(overlap!=0) access(0,'h14,0,15,OKAY,1,48);end
            join
        end
        // Exercise the production RAL frontdoor and passive predictor.
        foreach(registers.words[name]) if(name!="SNAPSHOT" && name!="CLEAR_STATS") begin
            registers.words[name].read(status,data,UVM_FRONTDOOR);
            if(status!=UVM_IS_OK) `uvm_fatal("CSR_RAL","mapped frontdoor read failed")
        end
        registers.words["CTRL"].write(status,1,UVM_FRONTDOOR);
        registers.words["CTRL"].mirror(status,UVM_CHECK,UVM_FRONTDOOR);
        if(status!=UVM_IS_OK) `uvm_fatal("CSR_RAL","control frontdoor mirror failed")
        access(1,'h10,0);
        // Every implemented word, queue and byte lane; no read clears state.
        for(int a=0;a<56;a+=4) begin
            access(0,32'(a));access(1,32'(a),'1,0);
            access(0,32'(a+1),0,15,SLVERR);access(1,32'(a+2),0,0,SLVERR);
        end
        access(0,'h18);access(0,'h1c);
        for(int a=256;a<336;a+=4) begin access(0,32'(a));access(1,32'(a),1,15,SLVERR);end
        for(int a=56;a<256;a+=4) begin access(0,32'(a),0,15,DECERR);access(1,32'(a),0,0,DECERR);end
        access(0,'h150,0,15,DECERR);access(1,'h3fc,0,15,DECERR);
        for(int invalid=N_Q;invalid<256;invalid++) begin
            access(0,32'('h400+64*invalid),0,15,DECERR);
            access(1,32'('h400+64*invalid+4),0,0,DECERR);
        end
        access(0,32'hfffffc01,0,15,DECERR);access(1,32'hfffffffc,0,0,DECERR);
        access(1,'h0,1,1,SLVERR);access(1,'h14,1,15,SLVERR);
        access(1,'h10,'hfffffffe); // CTRL reserved bits are ignored.
        access(1,'h20,2,15,SLVERR);access(1,'h20,1);access(1,'h20,0);
        for(q=0;q<N_Q;q++) begin
            for(int offset=0;offset<64;offset+=4) begin
                access(0,32'('h400+q*64+offset));
                access(1,32'('h400+q*64+offset),0,0);
                if(offset>=8) access(1,32'('h400+q*64+offset),1,15,SLVERR);
            end
            access(1,32'('h400+q*64),1);access(1,32'('h400+q*64),0,1,SLVERR);
            access(1,32'('h400+q*64),32'(N_CELL+1),15,SLVERR);
            access(1,32'('h400+q*64),32'(N_CELL));
            access(1,32'('h404+q*64),4096);
            // 0x1000 merged with only byte 0=64 becomes 0x1040: reject atomically.
            access(1,32'('h404+q*64),64,1,SLVERR);
            access(1,32'('h404+q*64),64);access(1,32'('h404+q*64),63,15,SLVERR);
            for(int lane=0;lane<4;lane++) begin
                access(1,32'('h404+q*64),(lane==0)?32'd0:32'hffffffff,4'(1<<lane),SLVERR);
                access(1,32'('h404+q*64),64,4'(1<<lane));
            end
            access(1,32'('h404+q*64),32'(MAX_PACKET_BYTES));
        end
        // Concurrent AR and write execute against the same old configuration.
        fork access(1,'h20,1);access(0,'h20);join
        access(0,'h20);access(1,'h20,0);
        access(1,'h10,1);
        access(1,'h20,1,15,SLVERR);access(1,'h400,1,15,SLVERR);access(1,'h404,64,15,SLVERR);
        access(1,'h1c,1,15,SLVERR);access(1,'h1c,0);access(1,'h1c,1,2);
        // Whole-system busy can coexist with zero queue counts/full resources.
        for(int context_bit=0;context_bit<6;context_bit++) begin
            @(negedge f.clk);f.busy=6'(1<<context_bit);
            access(0,'h14);access(1,'h10,0,15,SLVERR);access(0,'h10);
            access(1,'h10,0,0);access(1,'h10,0,2);
            access(1,'h400,0,0);access(1,'h14,'1,0);
        end
        @(negedge f.clk);f.busy=0;
        // A reservation also rejects disable without a committed queue.
        e='0;e.rx_service.valid=1;e.rx_service.sop=1;e.admit.valid=1;e.admit.accept=1;e.admit.ncell=2;
        pulse(e);access(1,'h10,0,15,SLVERR);access(0,'h24);access(0,'h28);access(0,'h408);
        e='0;e.abort_mark.valid=1;e.abort_mark.reserved=2;pulse(e);
        e='0;e.abort_done.valid=1;e.abort_done.ncell=2;pulse(e);
        // Each queue and reason, plus simultaneous distinct format events.
        for(q=0;q<N_Q;q++) begin
            packet(q);
            for(int reason=3;reason<=5;reason++) begin
                e='0;e.rx_service.valid=1;e.rx_service.sop=1;e.admit.valid=1;e.admit.qid=8'(q);e.admit.reason=status_code_t'(reason);pulse(e);
            end
        end
        e='0;e.admit.valid=1;e.admit.reason=BAD_QID;e.admit.qid=255;pulse(e);
        // Count one header format drop plus another packet's abort at one edge.
        e='0;e.admit.valid=1;e.admit.accept=1;e.admit.ncell=1;pulse(e);
        e='0;e.admit.valid=1;e.admit.reason=BAD_LENGTH;e.abort_mark.valid=1;pulse(e);
        e='0;e.abort_done.valid=1;e.abort_done.ncell=1;pulse(e);
        snapshot_collision();
        // Snapshot collides with deterministic events and samples multi-port
        // stalls once per cycle. It freezes shadow while live continues.
        fork
            access(1,'h18,1,15,OKAY,1,8);
            begin
                @(negedge f.clk);f.input_stalled='1;f.output_stalled=1;f.busy=6'b010001;
                repeat(20) @(negedge f.clk);
                f.input_stalled=0;f.output_stalled=0;f.busy=0;
            end
        join
        for(int k=19;k>=0;k--) access(0,32'('h100+k*4));
        access(1,'h18,1,2);access(1,'h18,0);access(1,'h18,1,0);
        // Peak captured on admission edge must survive a following release.
        fork access(1,'h18,1);access(0,'h100);join
        access(1,'h10,0);access(1,'h1c,1);
        @(negedge f.clk);f.busy=1;
        access(1,'h20,1,15,SLVERR);access(1,'h404,64,15,SLVERR);access(1,'h1c,1,15,SLVERR);
        @(negedge f.clk);f.busy=0;f.invariant_error=1;
        @(negedge f.clk);f.invariant_error=0;
        access(1,'h1c,1);access(0,'h14); // Clear cannot clear invariant sticky bit.
        access(1,'h10,1);
        abort_release_collision();
        // Reduced width runs wrap actual production counter arithmetic; ABI
        // remains 64 bits. Full-width runs use the same event sequence.
        for(int i=0;i<280;i++) begin
            q=int'($urandom_range(0,N_Q-1));packet(q,int'($urandom_range(1,8)));
            if(i%31==0) access(1,'h18,1,15,OKAY,i%3,i%5);
        end
        access(1,'h18,1);
        packet(0);
        fork
            access(0,'h108,0,15,OKAY,1,32);
            begin repeat(5) @(negedge f.clk);access(1,'h18,1);end
        join
        for(int k=0;k<20;k++) access(0,32'('h100+4*k));
        for(q=0;q<N_Q;q++) for(int offset=8;offset<64;offset+=4) access(0,32'('h400+q*64+offset));
        if(CSR_COUNTER_W<64 && model.rollovers==0) `uvm_fatal("CSR_ROLLOVER","rollover not exercised")
        for(int reset_phase=0;reset_phase<3;reset_phase++) pending_reset(reset_phase);
        access(0,'h14);access(0,'h10);access(0,'h100);
        repeat(4) @(negedge f.clk);
        if(model.snapshots<2 || model.collisions==0 || model.clears==0 || model.overlaps==0 || model.b_stalls==0 || model.r_stalls==0 || model.reset_pending<3)
            `uvm_fatal("CSR_COVERAGE","required lifecycle/protocol scenario missing")
        `uvm_info("CSR",$sformatf("TM_CSR_PASS reads=%0d writes=%0d snapshots=%0d collisions=%0d clears=%0d rollovers=%0d reset_pending=%0d",model.checked_reads,model.checked_writes,model.snapshots,model.collisions,model.clears,model.rollovers,model.reset_pending),UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass
