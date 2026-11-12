class tm_frame;
    int epoch, source, ordinal, qid, length, tag, desc, ncell, serviced, allocated, head;
    descriptor_t descriptor;
    bit complete, survives, delivered, aborted, committed;
    byte unsigned bytes[$];
    function new();
        epoch = 0;
        source = 0;
        ordinal = 0;
        qid = 0;
        length = 0;
        tag = 0;
        desc = 0;
        ncell = 0;
        serviced = 0;
        allocated = 0;
        head = 0;
        descriptor = '0;
        complete = 0;
        survives = 0;
        delivered = 0;
        aborted = 0;
        committed = 0;
    endfunction
    function string key();
        return $sformatf("%0d:%0d:%0d", epoch, source, ordinal);
    endfunction
endclass
class tm_beat_fifo;
    beat_t beats[$];
endclass
class tm_frame_queue;
    tm_frame frames[$];
endclass
// Black-box payload model. No trace event supplies expected bytes or success.
class tm_byte_checker extends uvm_component;
    `uvm_component_utils(tm_byte_checker)
    tm_frame frames[$], capture[N_RX], output_frame;
    int ordinals[N_RX], output_offset, delivered, total_captured;
    function new(string name, uvm_component parent);
        super.new(name, parent);
        delivered = 0;
        total_captured = 0;
        flush();
    endfunction
    function void flush();
        frames.delete();
        foreach(capture[p]) begin
            capture[p] = null;
            ordinals[p] = 0;
        end
        output_frame = null;
        output_offset = 0;
    endfunction
    function void apply(monitor_batch_t b);
        if(b.reset_asserted) begin
            flush();
            return;
        end
        collect_captures_and_statuses(b);
        check_output_transfer(b);
    endfunction
    function void collect_captures_and_statuses(monitor_batch_t b);
        stream_sample_t s;
        status_t st;
        tm_frame f;
        for(int p = 0;p<N_RX;p++) begin
            s = stream_sample_t'(b.captures[p*(BEAT_W+2)+:BEAT_W+2]);
            if(s.valid && s.ready) begin
                if(capture[p]==null) begin
                    f = new;
                    f.source = p;
                    f.epoch = int'(b.epoch);
                    f.ordinal = ordinals[p]++;
                    f.qid = int'(s.beat.user[7:0]);
                    f.length = int'(s.beat.user[23:8]);
                    f.tag = int'(s.beat.user[39:24]);
                    frames.push_back(f);
                    capture[p] = f;
                    total_captured++;
                end
                f = capture[p];
                for(int lane = 0;lane<8;lane++) if(s.beat.keep[lane]) f.bytes.push_back(s.beat.data[lane*8+:8]);
                if(s.beat.last) begin
                    f.complete = 1;
                    capture[p] = null;
                end
            end
            st = status_t'(b.statuses[p*STATUS_W+:STATUS_W]);
            if(st.valid) begin
                f = null;
                foreach(frames[i]) if(frames[i].source==p && !frames[i].survives && !frames[i].aborted && f==null) f = frames[i];
                if(f==null)
                    `uvm_fatal("BYTE_STATUS","status has no captured frame")
                if({st.qid, st.length, st.tag}!={8'(f.qid), 16'(f.length), 16'(f.tag)})
                    `uvm_fatal("BYTE_STATUS","status metadata mismatch")
                if(st.code==COMMITTED) begin
                    if(!f.complete || f.bytes.size()!=f.length)
                        `uvm_fatal("BYTE_STATUS","commit status without complete legal capture")
                    f.survives = 1;
                end else f.aborted = 1;
            end
        end
    endfunction
    function void check_output_transfer(monitor_batch_t b);
        stream_sample_t s;
        tm_frame f;
        int source, qid;
        s = b.output_sample;
        if(s.valid && s.ready) begin
            source = int'(s.beat.user[47:40]);
            qid = int'(s.beat.user[7:0]);
            if(output_frame==null) begin
                // Oldest surviving frame for this source and queue, regardless of tag.
                foreach(frames[i]) if(frames[i].source==source && frames[i].qid==qid && frames[i].survives && !frames[i].delivered && output_frame==null) output_frame = frames[i];
                if(output_frame==null)
                    `uvm_fatal("BYTE_UNEXPECTED","duplicate, stale or uncommitted delivery")
            end
            f = output_frame;
            if(s.beat.user!={16'b0, 8'(f.source), 16'(f.tag), 16'(f.length), 8'(f.qid)})
                `uvm_fatal("BYTE_METADATA","output metadata changed")
            if(s.beat.keep!=8'((1<<((f.length-output_offset>=8)?8:f.length-output_offset))-1) || s.beat.last!=(f.length-output_offset<=8))
            `uvm_fatal("BYTE_FRAMING","output keep/last mismatch")
            for(int lane = 0;lane<8;lane++) if(s.beat.keep[lane]) begin
                if(output_offset>=f.bytes.size() || s.beat.data[lane*8+:8]!=f.bytes[output_offset])
                    `uvm_fatal("BYTE_CORRUPTION", $sformatf("payload mismatch key=%s offset=%0d", f.key(), output_offset))
                output_offset++;
            end
            if(s.beat.last) begin
                f.delivered = 1;
                delivered++;
                output_frame = null;
                output_offset = 0;
            end
        end
    endfunction
    function void drained();
        foreach(frames[i]) begin
            if(frames[i].survives && !frames[i].delivered)
                `uvm_fatal("BYTE_LOST","committed packet never delivered")
            if(!frames[i].survives && !frames[i].aborted)
                `uvm_fatal("BYTE_NO_STATUS","captured packet has no disposition")
        end
    endfunction
endclass
class tm_resource_delta;
    int unreserved_delta, reserved_delta, assigned_delta, descriptor_delta;
    int queue_delta[N_Q];
    function new();
        unreserved_delta = 0;
        reserved_delta = 0;
        assigned_delta = 0;
        descriptor_delta = 0;
        foreach(queue_delta[q]) queue_delta[q] = 0;
    endfunction
endclass
// Scalar credits and packet objects; physical IDs are checked only for ownership.
class tm_service_checker extends uvm_component;
    `uvm_component_utils(tm_service_checker)
    tm_beat_fifo fifo[N_RX];
    tm_frame current[N_RX], descriptors[int];
    int ordinals[N_RX];
    status_t due[N_RX];
    bit cell_owned[int];
    int cell_desc[int];
    int unreserved_cells = N_CELL, reserved_cells = 0, assigned_cells = 0, free_descriptors = N_DESC, queue_owned_cells[N_Q];
    int limits[N_Q];
    bit wait_mode = 0;
    bit blocked[N_RX];
    bit csr_pending;
    bit [31:0] csr_expected;
    int csr_checks;
    int services, admissions, commits, status_count, aborts;
    tm_frame committed_frame;
    function new(string name, uvm_component parent);
        super.new(name, parent);
        foreach(fifo[p]) fifo[p] = new;
        foreach(limits[q]) limits[q] = N_CELL;
        services = 0;
        admissions = 0;
        commits = 0;
        status_count = 0;
        aborts = 0;
        csr_checks = 0;
        flush();
    endfunction
    function void flush();
        foreach(fifo[p]) begin
            fifo[p].beats.delete();
            current[p] = null;
            ordinals[p] = 0;
            due[p] = '0;
            blocked[p] = 0;
        end
        descriptors.delete();
        cell_owned.delete();
        cell_desc.delete();
        csr_pending = 0;
        unreserved_cells = N_CELL;
        reserved_cells = 0;
        assigned_cells = 0;
        free_descriptors = N_DESC;
        foreach(queue_owned_cells[q]) queue_owned_cells[q] = 0;
    endfunction
    function descriptor_t info(tm_frame f);
        descriptor_t v = '0;
        v.head = CELL_ID_W'(f.head);
        v.ncell = CELL_COUNT_W'(f.ncell);
        v.length = 16'(f.length);
        v.qid = Q_ID_W'(f.qid);
        v.tag = 16'(f.tag);
        v.source = RX_ID_W'(f.source);
        return v;
    endfunction
    function void expect_status(tm_frame f, status_code_t code);
        due[f.source] = '{1, code, 16'(f.tag), 8'(f.qid), 16'(f.length)};
    endfunction
    function void apply(monitor_batch_t b, live_t live);
        tm_resource_delta delta = new;
        committed_frame = null;
        if(b.reset_asserted) begin
            flush();
            return;
        end
        check_resource_reads(b);
        check_prestate_owners(b.policy);
        check_live_resources(live);
        check_due_statuses(b);
        check_rx_service(b, delta);
        collect_releases(b, delta);
        collect_captured_beats(b);
        merge_credits_and_check(delta);
    endfunction
    function void check_resource_reads(monitor_batch_t b);
        if(csr_pending && b.bus_rsp.rvalid) begin
            if(b.bus_rsp.rresp!=OKAY || b.bus_rsp.rdata!=csr_expected)
                `uvm_fatal("CSR_RESOURCE","CSR read differs from independent AR-edge resource state")
            if(b.bus_req.rready) begin
                csr_pending = 0;
                csr_checks++;
            end
        end
        if(b.bus_req.arvalid && b.bus_rsp.arready) begin
            case(b.bus_req.araddr)
                'h024:begin
                    csr_pending = 1;
                    csr_expected = 32'(unreserved_cells);
                end
                'h028:begin
                    csr_pending = 1;
                    csr_expected = 32'(reserved_cells);
                end
                'h02c:begin
                    csr_pending = 1;
                    csr_expected = 32'(free_descriptors);
                end
                default:csr_pending = 0;
            endcase
        end
    endfunction
    function void check_prestate_owners(trace_t t);
        // A newly allocated ID cannot also be returned on this edge.
        if(t.cell_free.valid && (!cell_owned.exists(int'(t.cell_free.id)) ||
            (t.cell_alloc.valid && t.cell_alloc.id==t.cell_free.id)))
                `uvm_fatal("CELL_RETURN","return must have a pre-state owner")
        if(t.abort_done.valid && !descriptors.exists(int'(t.abort_done.desc)))
            `uvm_fatal("ABORT_DONE","completion must have a pre-state owner")
        if(t.tx_done.valid && !descriptors.exists(int'(t.tx_done.desc)))
            `uvm_fatal("TX_DONE","completion must have a pre-state owner")
    endfunction
    function void check_live_resources(live_t live);
        // Compare observations to independently reconstructed pre-state.
        if({live.unreserved, live.reserved_free, live.assigned, live.physical_free, live.free_desc}!=
            {CELL_COUNT_W'(unreserved_cells), CELL_COUNT_W'(reserved_cells), CELL_COUNT_W'(assigned_cells), CELL_COUNT_W'(N_CELL-assigned_cells), DESC_COUNT_W'(free_descriptors)})
        `uvm_fatal("RESOURCE_LIVE","live resources disagree with model")
        foreach(queue_owned_cells[q]) if(live.owned[q*CELL_COUNT_W+:CELL_COUNT_W]!=CELL_COUNT_W'(queue_owned_cells[q]))
            `uvm_fatal("RESOURCE_H","queue budget mismatch")
    endfunction
    function void check_due_statuses(monitor_batch_t b);
        status_t st;
        for(int port = 0;port<N_RX;port++) begin
            st = status_t'(b.statuses[port*STATUS_W+:STATUS_W]);
            if(st!=due[port])
                `uvm_fatal("STATUS_CAUSALITY", $sformatf("wrong/missing status port=%0d expected=%h got=%h", port, due[port], st))
            if(st.valid) begin
                status_count++;
                blocked[port] = 0;
            end
            due[port] = '0;
        end
    endfunction
    function void check_rx_service(monitor_batch_t b, tm_resource_delta delta);
        trace_t t = b.policy;
        beat_t beat;
        tm_frame f;
        int source, remaining_bytes;
        bit malformed, needs_cell;
        // FIFO and all admission credits still describe pre-state here.
        if(t.rx_service.valid) begin
            source = int'(t.rx_service.source);
            services++;
            if(source>=N_RX || fifo[source].beats.size()==0)
                `uvm_fatal("SERVICE_EMPTY","service cannot consume same-cycle capture")
            beat = fifo[source].beats.pop_front();
            if(beat!=t.rx_service.beat)
                `uvm_fatal("SERVICE_DATA","service differs from oldest captured beat")
            if(t.rx_service.sop!=(current[source]==null))
                `uvm_fatal("SERVICE_SOP","wrong frame boundary")
            check_admission(b, source, beat, delta);
            f = current[source];
            remaining_bytes = f.length-f.serviced;
            malformed = remaining_bytes<=0 ||
                beat.keep!=8'((1<<((remaining_bytes>=8)?8:remaining_bytes))-1) ||
                beat.last!=(remaining_bytes<=8);
            if(f.survives && !f.aborted) begin
                needs_cell = !malformed && (f.serviced%CELL_BYTES==0);
                if(t.cell_alloc.valid!=needs_cell)
                    `uvm_fatal("MATERIALIZATION","wrong cell allocation boundary")
                if(needs_cell) begin
                    if(int'(t.cell_alloc.id)>=N_CELL || t.cell_alloc.desc!=DESC_ID_W'(f.desc) || cell_owned.exists(int'(t.cell_alloc.id)))
                        `uvm_fatal("CELL_OWNERSHIP","cell allocated twice or to wrong descriptor")
                    cell_owned[int'(t.cell_alloc.id)] = 1;
                    cell_desc[int'(t.cell_alloc.id)] = f.desc;
                    if(f.allocated==0) f.head = int'(t.cell_alloc.id);
                    f.allocated++;
                    delta.assigned_delta++;
                    delta.reserved_delta--;
                end
                if(malformed) begin
                    if(!t.abort_mark.valid ||
                        t.abort_mark.source!=RX_ID_W'(f.source) ||
                        t.abort_mark.qid!=Q_ID_W'(f.qid) ||
                        (f.allocated>0 && t.abort_mark.head!=CELL_ID_W'(f.head)) ||
                        t.abort_mark.desc!=DESC_ID_W'(f.desc) ||
                        t.abort_mark.allocated!=CELL_COUNT_W'(f.allocated) ||
                        t.abort_mark.reserved!=CELL_COUNT_W'(f.ncell))
                        `uvm_fatal("ABORT_CAUSALITY","malformed service without matching abort")
                    f.aborted = 1;
                    aborts++;
                end else if(beat.last) begin
                    if(!t.commit.valid || t.commit.desc!=DESC_ID_W'(f.desc) || t.commit.qid!=Q_ID_W'(f.qid) || t.commit.info!=info(f))
                        `uvm_fatal("COMMIT_CAUSALITY","commit does not match serviced complete frame")
                    f.descriptor = info(f);
                    f.committed = 1;
                    committed_frame = f;
                    commits++;
                    expect_status(f, COMMITTED);
                end else if(t.commit.valid)
                    `uvm_fatal("COMMIT_CAUSALITY","early commit")
            end else if(t.commit.valid || t.cell_alloc.valid || t.abort_mark.valid)
                `uvm_fatal("SERVICE_REJECT","actions on rejected/draining packet")
            f.serviced+=8;
            if(beat.last) begin
                f.complete = 1;
                current[source] = null;
            end
        end else if(t.admit.valid || t.commit.valid || t.cell_alloc.valid || t.abort_mark.valid)
            `uvm_fatal("SERVICE_MISSING","architectural RX event without service")
    endfunction
    function void check_admission(monitor_batch_t b, int source, beat_t beat, tm_resource_delta delta);
        trace_t t = b.policy;
        tm_frame f;
        int required_cells, rejection_reason;
        if(current[source]==null) begin
            if(blocked[source])
                `uvm_fatal("SERVICE_STATUS","new SOP before previous disposition")
            blocked[source] = 1;
            f = new;
            f.source = source;
            f.ordinal = ordinals[source]++;
            f.epoch = int'(b.epoch);
            f.qid = int'(beat.user[7:0]);
            f.length = int'(beat.user[23:8]);
            f.tag = int'(beat.user[39:24]);
            required_cells = (f.length+CELL_BYTES-1)/CELL_BYTES;
            f.ncell = required_cells;
            rejection_reason = 0;
            if(f.qid>=N_Q) rejection_reason = 1;
            else if(f.length==0 || f.length>MAX_PACKET_BYTES) rejection_reason = 2;
            else if(queue_owned_cells[f.qid]+required_cells>limits[f.qid]) rejection_reason = 3;
            else if(free_descriptors==0) rejection_reason = 4;
            else if(unreserved_cells<required_cells) rejection_reason = 5;
            if(wait_mode && rejection_reason>=3 && required_cells<=limits[f.qid])
                `uvm_fatal("WAIT_SERVICE","temporary shortage was serviced in WAIT mode")
            if(!t.admit.valid ||
                t.admit.source!=RX_ID_W'(source) ||
                t.admit.qid!=8'(f.qid) ||
                t.admit.length!=16'(f.length) ||
                t.admit.tag!=16'(f.tag) ||
                t.admit.accept!=(rejection_reason==0) ||
                int'(t.admit.reason)!=rejection_reason)
            `uvm_fatal("ADMISSION_PREDICATE","admission/reason disagrees with observed header and pre-state credits")
            if(rejection_reason!=2 && rejection_reason!=1 && t.admit.ncell!=CELL_COUNT_W'(required_cells))
                `uvm_fatal("ADMISSION_SIZE","wrong reservation")
            f.survives = (rejection_reason==0);
            current[source] = f;
            if(f.survives) begin
                f.desc = int'(t.admit.desc);
                if(f.desc>=N_DESC || descriptors.exists(f.desc))
                    `uvm_fatal("DESC_OWNERSHIP","allocated live descriptor")
                descriptors[f.desc] = f;
                delta.unreserved_delta-=required_cells;
                delta.reserved_delta+=required_cells;
                delta.descriptor_delta--;
                delta.queue_delta[f.qid]+=required_cells;
                admissions++;
            end else expect_status(f, status_code_t'(rejection_reason));
        end else if(t.admit.valid)
            `uvm_fatal("ADMISSION_SOP","admit on non-SOP")
    endfunction
    function void collect_releases(monitor_batch_t b, tm_resource_delta delta);
        trace_t t = b.policy;
        tm_frame f;
        int returned_id;
        if(t.cell_free.valid) begin
            returned_id = int'(t.cell_free.id);
            if(!cell_owned.exists(returned_id) || cell_desc[returned_id]!=int'(t.cell_free.desc))
                `uvm_fatal("CELL_RETURN","free of unowned cell")
            f = descriptors[int'(t.cell_free.desc)];
            if(f==null || f.qid!=int'(t.cell_free.qid))
                `uvm_fatal("CELL_RETURN","return qid mismatch")
            if(t.cell_free.abort_source) begin
                if(!f.aborted)
                    `uvm_fatal("ABORT_RETURN","reclaim of non-aborted packet")
                delta.reserved_delta++;
            end else begin
                if(!b.output_sample.valid || !b.output_sample.ready || !f.committed)
                    `uvm_fatal("TX_RETURN","cell release without output handshake")
                delta.unreserved_delta++;
                delta.queue_delta[f.qid]--;
            end
            f.allocated--;
            cell_owned.delete(returned_id);
            cell_desc.delete(returned_id);
            delta.assigned_delta--;
        end
        if(t.abort_done.valid) begin
            returned_id = int'(t.abort_done.desc);
            if(!descriptors.exists(returned_id))
                `uvm_fatal("ABORT_DONE","completion of unknown descriptor")
            f = descriptors[returned_id];
            if(!f.aborted ||
                f.allocated!=0 ||
                t.abort_done.source!=RX_ID_W'(f.source) ||
                t.abort_done.qid!=Q_ID_W'(f.qid) ||
                t.abort_done.ncell!=CELL_COUNT_W'(f.ncell))
                `uvm_fatal("ABORT_DONE","cleanup before reclaim or wrong reservation")
            delta.unreserved_delta+=f.ncell;
            delta.reserved_delta-=f.ncell;
            delta.queue_delta[f.qid]-=f.ncell;
            delta.descriptor_delta++;
            expect_status(f, FRAME_ERROR);
            descriptors.delete(returned_id);
        end
        if(t.tx_done.valid) begin
            returned_id = int'(t.tx_done.desc);
            if(!descriptors.exists(returned_id))
                `uvm_fatal("TX_DONE","completion of unknown descriptor")
            f = descriptors[returned_id];
            if(!f.committed ||
                f.allocated!=0 ||
                !b.output_sample.valid ||
                !b.output_sample.ready ||
                !b.output_sample.beat.last ||
                t.tx_done.length!=16'(f.length) ||
                t.tx_done.qid!=Q_ID_W'(f.qid))
                `uvm_fatal("TX_DONE","completion without final delivery")
            delta.descriptor_delta++;
            descriptors.delete(returned_id);
        end
    endfunction
    function void collect_captured_beats(monitor_batch_t b);
        stream_sample_t s;
        // Capture comes after service: no registered-FIFO fall-through.
        for(int port = 0;port<N_RX;port++) begin
            s = stream_sample_t'(b.captures[port*(BEAT_W+2)+:BEAT_W+2]);
            if(s.valid && s.ready) fifo[port].beats.push_back(s.beat);
        end
    endfunction
    function void merge_credits_and_check(tm_resource_delta delta);
        int total_owned;
        // Reserve, materialize, TX return and abort completion merge once.
        unreserved_cells+=delta.unreserved_delta;
        reserved_cells+=delta.reserved_delta;
        assigned_cells+=delta.assigned_delta;
        free_descriptors+=delta.descriptor_delta;
        foreach(queue_owned_cells[q]) queue_owned_cells[q]+=delta.queue_delta[q];
        total_owned = 0;
        foreach(queue_owned_cells[q]) begin
            total_owned+=queue_owned_cells[q];
            if(queue_owned_cells[q]<0 || queue_owned_cells[q]>N_CELL)
                `uvm_fatal("RESOURCE_BOUNDS","H out of range")
        end
        if(unreserved_cells<0 ||
            reserved_cells<0 ||
            assigned_cells<0 ||
            free_descriptors<0 ||
            free_descriptors>N_DESC ||
            assigned_cells+unreserved_cells+reserved_cells!=N_CELL ||
            unreserved_cells+total_owned!=N_CELL)
            `uvm_fatal("RESOURCE_EQUATIONS","credit conservation failed")
    endfunction
    function void drained();
        foreach(fifo[p]) if(fifo[p].beats.size()!=0 || current[p]!=null || due[p].valid)
            `uvm_fatal("SERVICE_LOST","unaccounted service or status")
        if(descriptors.num()!=0 || unreserved_cells!=N_CELL || free_descriptors!=N_DESC || assigned_cells!=0 || reserved_cells!=0)
            `uvm_fatal("RESOURCE_LEAK","resources not restored")
    endfunction
endclass
class tm_schedule_checker extends uvm_component;
    `uvm_component_utils(tm_schedule_checker)
    tm_frame_queue queues[N_Q];
    tm_frame active;
    int cursor, deficit[N_Q], quantum = MAX_PACKET_BYTES, dispatches, offset;
    bit visit;
    function new(string name, uvm_component parent);
        super.new(name, parent);
        foreach(queues[q]) queues[q] = new;
        dispatches = 0;
        flush();
    endfunction
    function void flush();
        foreach(queues[q]) begin
            queues[q].frames.delete();
            deficit[q] = 0;
        end
        active = null;
        cursor = 0;
        visit = 0;
        offset = 0;
    endfunction
    function void apply(monitor_batch_t b, tm_frame committed_frame);
        tm_frame f;
        bit grant;
        int q, credit;
        trace_t t = b.policy;
        if(b.reset_asserted) begin
            flush();
            return;
        end
        grant = 0;
        q = cursor;
        credit = deficit[q];
        if(active==null && queues[q].frames.size()!=0) begin
            if(!visit) credit+=quantum;
            f = queues[q].frames[0];
            grant = (f.length<=credit);
        end
        check_dispatch(t, grant, q, f);
        merge_queue_changes(committed_frame, grant, q, credit, f);
        check_retirement(b, grant);
    endfunction
    function void check_dispatch(trace_t t, bit grant, int q, tm_frame f);
        if(t.dispatch.valid!=grant)
            `uvm_fatal("SCHEDULE_GRANT","missing or illegal pre-state dispatch")
        if(grant) begin
            if(t.dispatch.qid!=Q_ID_W'(q) || int'(t.dispatch.desc)!=f.desc || t.dispatch.info!=f.descriptor)
                `uvm_fatal("SCHEDULE_HEAD","dispatch does not match expected queue head")
        end
    endfunction
    function void merge_queue_changes(tm_frame committed_frame, bit grant, int q, int credit, tm_frame f);
        tm_frame removed;
        // Commit is appended only after deciding from the old head. Empty
        // closure uses the merged count, preserving last-pop/commit credit.
        if(grant) begin
            removed = queues[q].frames.pop_front();
            active = f;
            offset = 0;
            deficit[q] = credit-f.length;
            visit = 1;
            dispatches++;
        end else if(active==null) begin
            if(queues[q].frames.size()==0) deficit[q] = 0;
            else deficit[q] = credit;
            cursor = (q+1)%N_Q;
            visit = 0;
        end
        if(committed_frame!=null) queues[committed_frame.qid].frames.push_back(committed_frame);
        if(grant && queues[q].frames.size()==0) begin
            deficit[q] = 0;
            visit = 0;
            cursor = (q+1)%N_Q;
        end
    endfunction
    function void check_retirement(monitor_batch_t b, bit grant);
        trace_t t = b.policy;
        if(b.output_sample.valid && b.output_sample.ready) begin
            if(active==null || grant)
                `uvm_fatal("SCHEDULE_OUTPUT","output without previously dispatched packet")
            if(b.output_sample.beat.user!={16'b0, 8'(active.source), 16'(active.tag), 16'(active.length), 8'(active.qid)})
                `uvm_fatal("SCHEDULE_OUTPUT","output is not dispatched packet")
            if((t.cell_free.valid && t.cell_free.desc!=DESC_ID_W'(active.desc)) ||
                (t.tx_done.valid && t.tx_done.desc!=DESC_ID_W'(active.desc)))
                    `uvm_fatal("SCHEDULE_RETIRE","release of a different packet")
            offset+=$countones(b.output_sample.beat.keep);
            if(t.cell_free.valid!=((offset%CELL_BYTES==0)||b.output_sample.beat.last))
                `uvm_fatal("SCHEDULE_RETIRE","incorrect cell retirement boundary")
            if(t.tx_done.valid!=b.output_sample.beat.last)
                `uvm_fatal("SCHEDULE_DONE","missing or premature completion")
            if(b.output_sample.beat.last) active = null;
        end else if(t.tx_done.valid)
            `uvm_fatal("SCHEDULE_DONE","completion without output")
    endfunction
    function void drained();
        if(active!=null)
            `uvm_fatal("SCHEDULE_LOST","dispatched packet not completed")
        foreach(queues[q]) if(queues[q].frames.size()!=0)
            `uvm_fatal("SCHEDULE_LOST","committed queue not drained")
    endfunction
endclass
