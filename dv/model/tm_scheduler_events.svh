// Component-boundary observations. Packet expectations are rebuilt from the
// sampled publication API; sequence packet objects never enter the checker.
class tm_scheduler_event_monitor extends uvm_component;
    `uvm_component_utils(tm_scheduler_event_monitor)
    virtual tm_scheduler_if vif;
    function new(string name, uvm_component parent);
        super.new(name,parent);
    endfunction
    function void sample(output monitor_batch_t batch, output tm_frame frame);
        batch = '0;
        batch.policy.commit = vif.commit;
        batch.policy.dispatch = vif.dispatch;
        batch.policy.tx_done = vif.tx_done;
        batch.policy.cell_free = vif.cell_free;
        batch.output_sample = vif.output_sample;
        frame = null;
        if(vif.commit.valid) begin
            frame = new;
            frame.desc = int'(vif.commit.desc);
            frame.qid = int'(vif.commit.qid);
            frame.length = int'(vif.commit.info.length);
            frame.source = int'(vif.commit.info.source);
            frame.tag = int'(vif.commit.info.tag);
            frame.descriptor = vif.commit.info;
        end
    endfunction
endclass
