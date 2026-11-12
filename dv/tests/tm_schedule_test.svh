// Isolated policy/timing probes; packet contents in the full bench still come
// exclusively from monitored and independently validated service/commit data.
class tm_schedule_test extends uvm_test;
    `uvm_component_utils(tm_schedule_test)
    tm_schedule_checker model;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        model = tm_schedule_checker::type_id::create("model", this);
        model.quantum = 64;
    endfunction
    function tm_frame packet(int desc, int length);
        tm_frame frame = new;
        frame.desc = desc;
        frame.length = length;
        frame.descriptor = '0;
        frame.descriptor.length = 16'(length);
        frame.descriptor.ncell = CELL_COUNT_W'((length+CELL_BYTES-1)/CELL_BYTES);
        return frame;
    endfunction
    function void step(dispatch_t dispatch='0, tm_frame commit_frame=null);
        monitor_batch_t batch = '0;
        batch.policy.dispatch = dispatch;
        model.apply(batch, commit_frame);
    endfunction
    function dispatch_t grant(tm_frame frame);
        return '{1, Q_ID_W'(frame.qid), DESC_ID_W'(frame.desc), frame.descriptor};
    endfunction
    function void finish_packet(tm_frame frame);
        monitor_batch_t batch;
        int remaining;
        for(int offset=0; offset<frame.length; offset+=8) begin
            batch = '0;
            remaining = frame.length-offset;
            batch.output_sample = '{1, 1, '0};
            batch.output_sample.beat.keep = 8'((1 << (remaining >= 8 ? 8 : remaining))-1);
            batch.output_sample.beat.last = remaining <= 8;
            batch.output_sample.beat.user = {16'b0, 8'(frame.source), 16'(frame.tag), 16'(frame.length), 8'(frame.qid)};
            if((offset+8)%CELL_BYTES == 0 || remaining <= 8)
                batch.policy.cell_free = '{1, CELL_ID_W'(0), 0, Q_ID_W'(frame.qid), DESC_ID_W'(frame.desc)};
            if(remaining <= 8) batch.policy.tx_done = '{1, DESC_ID_W'(frame.desc), Q_ID_W'(frame.qid), 16'(frame.length)};
            model.apply(batch, null);
        end
    endfunction
    task run_phase(uvm_phase phase);
        tm_frame first = packet(0, 65);
        tm_frame second = packet(1, 1);
        int frozen_deficit, frozen_cursor;
        phase.raise_objection(this);
        if($test$plusargs("MUT_SCHED_BYPASS")) begin
            // No pre-state head; a simultaneous commit cannot fund dispatch.
            step(grant(first), first);
        end
        step('0, first);
        // Cursor advanced on the empty commit edge. The first nonempty visit
        // adds 64, which cannot yet pay for 65 bytes.
        repeat(N_Q-1) step();
        if($test$plusargs("MUT_SCHED_CREDIT")) step(grant(first));
        step();
        if(model.deficit[0] != 64) `uvm_fatal("SCHEDULE_PROBE", "visit credit did not carry")
        repeat(N_Q-1) step();
        if($test$plusargs("MUT_SCHED_MISSING")) step();
        if($test$plusargs("MUT_SCHED_HEAD")) step(grant(second));
        // Last-pop plus same-queue commit must retain the remaining 63 bytes.
        step(grant(first), second);
        if(model.deficit[0] != 63 || !model.visit || model.queues[0].frames.size() != 1)
            `uvm_fatal("SCHEDULE_PROBE", "merged replacement lost visit credit or new head")
        frozen_deficit = model.deficit[0];
        frozen_cursor = model.cursor;
        if($test$plusargs("MUT_SCHED_BUSY")) step(grant(second));
        repeat(5) step();
        if(model.deficit[0] != frozen_deficit || model.cursor != frozen_cursor)
            `uvm_fatal("SCHEDULE_PROBE", "TX stall changed policy state")
        finish_packet(first);
        step(grant(second)); // Same visit, no additional quantum.
        if(model.deficit[0] != 0 || model.visit)
            `uvm_fatal("SCHEDULE_PROBE", "true-empty transition retained credit")
        finish_packet(second);
        model.drained();
        `uvm_info("SCHEDULE", "TM_SCHEDULE_PASS carry=1 merged=1 freeze=1 empty=1", UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass
