// Neighbor legality is checked before scheduling policy. Ownership comes only
// from accepted boundary events, independently of the scheduler's FSM.
class tm_scheduler_input_checker extends uvm_component;
    `uvm_component_utils(tm_scheduler_input_checker)
    bit queued[N_DESC], owned, history;
    dispatch_t owner;
    config_t previous;
    function new(string name, uvm_component parent);
        super.new(name,parent);
        flush();
    endfunction
    function void flush();
        foreach(queued[d]) queued[d]=0;
        owned=0; owner='0; history=0; previous='0;
    endfunction
    function void check(monitor_batch_t b, config_t cfg);
        trace_t t=b.policy;
        bit empty=1;
        foreach(queued[d]) if(queued[d]) empty=0;
        if(t.tx_done.valid && (!owned || t.tx_done.desc!=owner.desc ||
           t.tx_done.qid!=owner.qid || t.tx_done.length!=owner.info.length))
            `uvm_fatal("SCHED_INPUT_DONE","completion does not match an owned dispatched packet")
        if(t.commit.valid && (int'(t.commit.desc)>=N_DESC || queued[t.commit.desc] ||
           (owned && t.commit.desc==owner.desc)))
            `uvm_fatal("SCHED_INPUT_COMMIT","publication reuses a queued or TX-owned descriptor")
        if(history && (cfg.quantum!=previous.quantum || cfg.cell_limit!=previous.cell_limit || cfg.wait_mode!=previous.wait_mode) &&
           (cfg.run || previous.run || owned || !empty))
            `uvm_fatal("SCHED_INPUT_CONFIG","configuration changed without disabled idle boundary")
        if(cfg.run) for(int q=0;q<N_Q;q++)
            if(cfg.quantum[q*13+:13]<64 || cfg.quantum[q*13+:13]>4096)
                `uvm_fatal("SCHED_INPUT_CONFIG","running quantum outside the register contract")
        if(t.dispatch.valid) queued[t.dispatch.desc]=0;
        if(t.commit.valid) queued[t.commit.desc]=1;
        if(t.tx_done.valid) owned=0;
        if(t.dispatch.valid) begin owned=1; owner=t.dispatch; end
        previous=cfg; history=1;
    endfunction
endclass
