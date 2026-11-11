class tm_axil_item extends uvm_sequence_item;
    `uvm_object_utils(tm_axil_item)
    bit write;
    bit [31:0] addr,data;
    bit [3:0] strb=15;
    axil_resp_t response;
    int aw_delay=0,w_delay=0,response_stall=0;
    int epoch;
    function new(string name="axil_item"); super.new(name); endfunction
endclass

class tm_axil_driver extends uvm_driver #(tm_axil_item);
    `uvm_component_utils(tm_axil_driver)
    virtual tm_axil_if vif;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    mailbox #(tm_axil_item) writes=new, reads=new;
    int epoch=0;
    task drive_write(tm_axil_item x);
        if(x.epoch!=epoch) begin x.response=SLVERR;seq_item_port.put_response(x);return;end
        while(!vif.rst_n) @(negedge vif.clk);
        fork
            begin
                for(int i=0;i<x.aw_delay && x.epoch==epoch;i++) @(negedge vif.clk);
                @(negedge vif.clk); vif.req.awaddr=x.addr; vif.req.awvalid=(x.epoch==epoch && vif.rst_n);
                do @(posedge vif.clk); while(x.epoch==epoch && vif.rst_n && !vif.rsp.awready);
                @(negedge vif.clk); vif.req.awvalid=0;
            end
            begin
                for(int i=0;i<x.w_delay && x.epoch==epoch;i++) @(negedge vif.clk);
                @(negedge vif.clk); vif.req.wdata=x.data; vif.req.wstrb=x.strb; vif.req.wvalid=(x.epoch==epoch && vif.rst_n);
                do @(posedge vif.clk); while(x.epoch==epoch && vif.rst_n && !vif.rsp.wready);
                @(negedge vif.clk); vif.req.wvalid=0;
            end
        join
        for(int i=0;i<x.response_stall && x.epoch==epoch;i++) @(negedge vif.clk);
        vif.req.bready=(x.epoch==epoch && vif.rst_n);
        do @(posedge vif.clk); while(x.epoch==epoch && vif.rst_n && !vif.rsp.bvalid);
        x.response=(x.epoch==epoch && vif.rst_n)?vif.rsp.bresp:SLVERR;
        @(negedge vif.clk); vif.req.bready=0;
        seq_item_port.put_response(x);
    endtask
    task drive_read(tm_axil_item x);
        if(x.epoch!=epoch) begin x.response=SLVERR;seq_item_port.put_response(x);return;end
        while(!vif.rst_n) @(negedge vif.clk);
        @(negedge vif.clk); vif.req.araddr=x.addr; vif.req.arvalid=(x.epoch==epoch && vif.rst_n);
        do @(posedge vif.clk); while(x.epoch==epoch && vif.rst_n && !vif.rsp.arready);
        @(negedge vif.clk); vif.req.arvalid=0;
        for(int i=0;i<x.response_stall && x.epoch==epoch;i++) @(negedge vif.clk);
        vif.req.rready=(x.epoch==epoch && vif.rst_n);
        do @(posedge vif.clk); while(x.epoch==epoch && vif.rst_n && !vif.rsp.rvalid);
        x.data=vif.rsp.rdata;x.response=(x.epoch==epoch && vif.rst_n)?vif.rsp.rresp:SLVERR;
        @(negedge vif.clk); vif.req.rready=0;
        seq_item_port.put_response(x);
    endtask
    task run_phase(uvm_phase phase);
        vif.req='0;
        fork
            forever begin
                @(negedge vif.rst_n);epoch++;
                vif.req.awvalid=0;vif.req.wvalid=0;vif.req.arvalid=0;vif.req.bready=0;vif.req.rready=0;
            end
            forever begin
                tm_axil_item x;
                seq_item_port.get_next_item(x);
                x.epoch=epoch;
                if(x.write) writes.put(x);else reads.put(x);
                seq_item_port.item_done();
            end
            forever begin tm_axil_item x;writes.get(x);drive_write(x);end
            forever begin tm_axil_item x;reads.get(x);drive_read(x);end
        join
    endtask

endclass

class tm_axil_monitor extends uvm_monitor;
    `uvm_component_utils(tm_axil_monitor)
    virtual tm_axil_if vif;
    uvm_analysis_port #(tm_sample) samples;
    uvm_analysis_port #(tm_axil_item) transactions;
    tm_stamp stamp;
    bit have_aw,have_w,have_ar;
    bit [31:0] read_addr;
    int write_age,read_age;
    bit [31:0] addr,data;
    bit [3:0] strb;
    function new(string name,uvm_component parent);
        super.new(name,parent); samples=new("samples",this); transactions=new("transactions",this); stamp=new;
    endfunction
    task run_phase(uvm_phase phase);
        tm_sample s;
        tm_axil_item t;
        forever begin
            @(posedge vif.clk);
            s=new; s.source=N_RX+1; stamp.apply(s,!vif.rst_n);
            s.batch.bus_req=vif.req; s.batch.bus_rsp=vif.rsp; samples.write(s);
            if(!vif.rst_n) begin have_aw=0; have_w=0; have_ar=0; write_age=0;read_age=0; end
            else begin
                if(have_aw && have_w && !vif.rsp.bvalid) write_age++; else write_age=0;
                if(have_ar && !vif.rsp.rvalid) read_age++;else read_age=0;
                if(write_age>3 || read_age>3) `uvm_fatal("AXIL_LATENCY","response exceeded three core cycles")
                if(vif.req.arvalid && vif.rsp.arready) begin
                    if(have_ar) `uvm_fatal("AXIL_DUP_AR","second outstanding read")
                    have_ar=1;read_addr=vif.req.araddr;
                end
                if(vif.req.awvalid && vif.rsp.awready) begin
                    if(have_aw) `uvm_fatal("AXIL_DUP_AW","second outstanding address")
                    have_aw=1; addr=vif.req.awaddr;
                end
                if(vif.req.wvalid && vif.rsp.wready) begin
                    if(have_w) `uvm_fatal("AXIL_DUP_W","second outstanding data")
                    have_w=1; data=vif.req.wdata; strb=vif.req.wstrb;
                end
                if(vif.rsp.bvalid && vif.req.bready) begin
                    if(!have_aw || !have_w) `uvm_fatal("AXIL_CAUSALITY","response without AW/W")
                    t=new; t.write=1; t.addr=addr; t.data=data; t.strb=strb; t.response=vif.rsp.bresp;
                    transactions.write(t); have_aw=0; have_w=0;
                end
                if(vif.rsp.rvalid && vif.req.rready) begin
                    if(!have_ar) `uvm_fatal("AXIL_CAUSALITY","R response without AR")
                    t=new; t.addr=read_addr; t.data=vif.rsp.rdata; t.response=vif.rsp.rresp;
                    transactions.write(t);have_ar=0;
                end
            end
        end
    endtask
endclass

class tm_axil_adapter extends uvm_reg_adapter;
    `uvm_object_utils(tm_axil_adapter)
    function new(string name="adapter"); super.new(name); supports_byte_enable=1; provides_responses=1; endfunction
    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        tm_axil_item x=new;
        x.write=(rw.kind==UVM_WRITE); x.addr=32'(rw.addr); x.data=32'(rw.data); x.strb=4'(rw.byte_en);
        // Exercise independent channel order on actual RAL frontdoor accesses.
        x.aw_delay=(rw.data[0]?4:0); x.w_delay=(rw.data[0]?0:4); x.response_stall=3;
        return x;
    endfunction
    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        tm_axil_item x;
        if(!$cast(x,bus_item)) `uvm_fatal("RAL_CAST","wrong bus transaction")
        rw.kind=x.write?UVM_WRITE:UVM_READ; rw.addr=uvm_reg_addr_t'(x.addr); rw.data=uvm_reg_data_t'(x.data); rw.byte_en=uvm_reg_byte_en_t'(x.strb);
        rw.status=x.response==OKAY?UVM_IS_OK:UVM_NOT_OK;
    endfunction
endclass

class tm_config_reg extends uvm_reg;
    `uvm_object_utils(tm_config_reg)
    uvm_reg_field value;
    function new(string name="config_reg"); super.new(name,32,UVM_NO_COVERAGE); endfunction
    function void build();
        value=uvm_reg_field::type_id::create("value"); value.configure(this,32,0,"RW",0,0,1,0,0);
    endfunction
endclass

class tm_fixture_register_block extends uvm_reg_block;
    `uvm_object_utils(tm_fixture_register_block)
    tm_config_reg control;
    function new(string name="registers"); super.new(name,UVM_NO_COVERAGE); endfunction
    function void build();
        control=tm_config_reg::type_id::create("control"); control.configure(this); control.build();
        default_map=create_map("frontdoor",0,4,UVM_LITTLE_ENDIAN);
        default_map.add_reg(control,'h0,"RW"); lock_model();
    endfunction
endclass

class tm_axil_agent extends uvm_agent;
    `uvm_component_utils(tm_axil_agent)
    virtual tm_axil_if vif;
    tm_axil_driver driver;
    tm_axil_monitor monitor;
    uvm_sequencer #(tm_axil_item) sequencer;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual tm_axil_if)::get(this,"","vif",vif)) `uvm_fatal("CONFIG","AXIL vif missing")
        monitor=tm_axil_monitor::type_id::create("monitor",this); monitor.vif=vif;
        if(is_active==UVM_ACTIVE) begin
            driver=tm_axil_driver::type_id::create("driver",this); driver.vif=vif;
            sequencer=new("sequencer",this);
        end
    endfunction
    function void connect_phase(uvm_phase phase);
        if(is_active==UVM_ACTIVE) driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

// Production map declaration for P06/P09 hookup; never claim fixture accesses
// exercise the production slave. Each entry still uses this agent's frontdoor.
class tm_word_reg extends uvm_reg;
    `uvm_object_utils(tm_word_reg)
    uvm_reg_field value;
    function new(string name="word");super.new(name,32,UVM_NO_COVERAGE);endfunction
    function void build(string access,uvm_reg_data_t reset_value,int width=32,bit live=0);
        value=uvm_reg_field::type_id::create("value");
        value.configure(this,width,0,access,live,reset_value,1,0,0);
        if(live) value.set_compare(UVM_NO_CHECK);
    endfunction
endclass
class tm_register_block extends uvm_reg_block;
    `uvm_object_utils(tm_register_block)
    tm_word_reg words[string];
    function new(string name="tm_registers");super.new(name,UVM_NO_COVERAGE);endfunction
    function void add_word(string name,uvm_reg_addr_t addr,string access,uvm_reg_data_t reset_value=0,int width=32,bit live=0);
        tm_word_reg word=tm_word_reg::type_id::create(name);
        word.configure(this);word.build(access,reset_value,width,live);
        words[name]=word;default_map.add_reg(word,addr,access);
    endfunction
    function void build();
        default_map=create_map("frontdoor",0,4,UVM_LITTLE_ENDIAN);
        add_word("ID",'h000,"RO",'h544d0100);
        add_word("VERSION",'h004,"RO",'h00010000);
        add_word("CAP0",'h008,"RO",uvm_reg_data_t'({8'(CELL_BYTES),8'd8,8'(N_Q),8'(N_RX)}));
        add_word("CAP1",'h00c,"RO",uvm_reg_data_t'({16'(N_DESC),16'(N_CELL)}));
        add_word("CTRL",'h010,"RW",0,1);
        add_word("STATUS",'h014,"RO",2,4,1);
        add_word("SNAPSHOT",'h018,"WO",0,1);
        add_word("CLEAR_STATS",'h01c,"WO",0,1);
        add_word("ADMISSION_MODE",'h020,"RW",0,1);
        add_word("FREE_CREDIT",'h024,"RO",uvm_reg_data_t'( N_CELL ),32,1);
        add_word("RESERVED_FREE",'h028,"RO",0,32,1);
        add_word("FREE_DESC",'h02c,"RO",uvm_reg_data_t'( N_DESC ),32,1);
        add_word("SCHED_MODE",'h030,"RO",uvm_reg_data_t'( SCHED_MODE ));
        add_word("MAX_LENGTH",'h034,"RO",uvm_reg_data_t'( MAX_PACKET_BYTES ));
        for(int k=0;k<20;k++) add_word($sformatf("GLOBAL_%0d",k),'h100+uvm_reg_addr_t'(4*k),"RO",0,32,1);
        for(int q=0;q<N_Q;q++) begin
            add_word($sformatf("Q%0d_LIMIT",q),'h400+uvm_reg_addr_t'(64*q),"RW",uvm_reg_data_t'( N_CELL ));
            add_word($sformatf("Q%0d_QUANTUM",q),'h404+uvm_reg_addr_t'(64*q),"RW",uvm_reg_data_t'( MAX_PACKET_BYTES ));
            for(int k=2;k<16;k++) add_word($sformatf("Q%0d_WORD%0d",q,k),'h400+uvm_reg_addr_t'(64*q+4*k),"RO",0,32,1);
        end
        lock_model();reset();
    endfunction
endclass
