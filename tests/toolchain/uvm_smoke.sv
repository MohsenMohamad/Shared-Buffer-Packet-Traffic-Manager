`timescale 1ns/1ps
// Simulator capability fixture; independent of the traffic-manager RTL.
interface tm_cap_if(input logic clk);
    logic rst_n,s_valid,s_ready,m_valid,m_ready;
    logic [31:0] s_data,m_data;
endinterface

module tm_cap_pipe(tm_cap_if v);
    assign v.s_ready=!v.m_valid || v.m_ready;
    always @(posedge v.clk or negedge v.rst_n)
        if(!v.rst_n) begin v.m_valid<=0;v.m_data<=0;end
        else if(v.s_ready) begin
            v.m_valid<=v.s_valid;
            if(v.s_valid) v.m_data<=v.s_data;
        end
        else if($test$plusargs("MUTATION_HOLD") && v.m_valid && !v.m_ready)
            v.m_data<=v.m_data+1;
    property hold_output;
        @(posedge v.clk) disable iff(!v.rst_n)
        v.m_valid && !v.m_ready |=> v.m_valid && $stable(v.m_data);
    endproperty
    a_hold: assert property(hold_output)
        else $fatal(1,"TM_CAP_STABILITY_FAIL");
endmodule

package tm_cap_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    class tm_cap_item extends uvm_sequence_item;
        `uvm_object_utils(tm_cap_item)
        rand bit [31:0] data;
        rand int unsigned qid,len;
        constraint legal { qid inside {[0:3]}; len inside {[1:128]}; }
        function new(string name="item");super.new(name);endfunction
    endclass
    class tm_cap_test extends uvm_test;
        `uvm_component_utils(tm_cap_test)
        virtual tm_cap_if v;
        covergroup cg with function sample(int qid,int len);
            option.per_instance=1;
            q:coverpoint qid { bins queues[]={[0:3]}; }
            l:coverpoint len { bins short_pkt={[1:8]};bins mid_pkt={[9:64]};bins long_pkt={[65:128]}; }
            ql:cross q,l;
        endgroup
        function new(string name,uvm_component parent);super.new(name,parent);cg=new;endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if(!uvm_config_db#(virtual tm_cap_if)::get(this,"","vif",v))
                `uvm_fatal("PROBE","missing interface")
        endfunction
        task run_phase(uvm_phase phase);
            tm_cap_item x;
            int random_result;
            bit [31:0] signature=0;
            phase.raise_objection(this);
            v.rst_n=0;v.s_valid=0;v.s_data=0;v.m_ready=0;
            repeat(4) @(negedge v.clk);
            v.rst_n=1;
            x=tm_cap_item::type_id::create("unsat");
            random_result=x.randomize() with { qid == 99; };
            if(random_result != 0)
                `uvm_fatal("PROBE","unsatisfiable constraints accepted")
            `uvm_info("PROBE","TM_CAP_UNSAT_PASS",UVM_NONE)
            repeat(64) begin
                x=tm_cap_item::type_id::create("x");
                if(x.randomize()!=1) `uvm_fatal("PROBE","randomization failed")
                if(!(x.qid inside {[0:3]}) || !(x.len inside {[1:128]}))
                    `uvm_fatal("PROBE","constraint result outside legal range")
                signature=(signature<<5) ^ (signature>>27) ^ x.data ^ x.qid ^ x.len;
                v.s_valid=1;v.s_data=x.data;v.m_ready=0;
                do @(posedge v.clk); while(!v.s_ready);
                @(negedge v.clk);v.s_valid=0;
                repeat(3) @(negedge v.clk);
                if(v.m_valid!==1 || v.m_data!==x.data)
                    `uvm_fatal("PROBE","end-to-end data check failed")
                cg.sample(x.qid,x.len);
                v.m_ready=1;
                @(posedge v.clk);
                @(negedge v.clk);
            end
            `uvm_info("PROBE",$sformatf("TM_UVM_SMOKE_PASS transactions=64 digest=%08x coverage=%0.2f",signature,cg.get_inst_coverage()),UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass
endpackage

module tm_uvm_capabilities;
    import uvm_pkg::*;
    import tm_cap_pkg::*;
    logic clk=0;
    always #5 clk=~clk;
    tm_cap_if v(clk);
    tm_cap_pipe dut(v);
    initial begin
        uvm_config_db#(virtual tm_cap_if)::set(null,"uvm_test_top","vif",v);
        run_test("tm_cap_test");
    end
    initial if($test$plusargs("TRACE")) begin
        $dumpfile("wave.vcd"); $dumpvars(0,tm_uvm_capabilities);
    end
    initial begin #100000; $fatal(1,"TM_CAP_TIMEOUT");end
endmodule
