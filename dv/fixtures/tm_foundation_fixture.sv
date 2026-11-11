`timescale 1ns/1ps
// Behavioral bench qualifier, not a traffic manager implementation.
package tm_fixture_types;
    import tm_bench_types::*;
    class packet;
        beat_t words[$];
        int cells[$];
        descriptor_t info;
        int desc,seen;
        bit rejected,bad;
        function new();info='0;desc=0;seen=0;rejected=0;bad=0;endfunction
    endclass
    class beat_queue;
        beat_t words[$];
    endclass
    class packet_queue;
        packet packets[$];
    endclass
endpackage

module tm_foundation_fixture(
    input logic clk,
    tm_stream_if rx[N_RX],tm_stream_if tx,
    tm_axil_if bus,tm_observe_if obs
);
    import tm_bench_types::*;
    import tm_fixture_types::*;
    beat_queue ingress[N_RX];
    packet_queue queues[N_Q];
    packet receiving[N_RX],active,cleaning;
    packet reserved[int];
    beat_t captures[N_RX];
    logic [N_RX-1:0] capture_valid,ready;
    status_t pending_status[N_RX];
    trace_t plan,events;
    int rr,cursor,deficit[N_Q],used_cells[N_CELL],used_desc[N_DESC];
    bit visit;
    int offset,cell_index,u,r,a,d,h[N_Q],cycle;
    int selected,selected_desc,selected_cell;
    packet selected_packet;
    bit grant,bad_beat,allocate;
    int next_credit;
    bit duplicate_sent;
    beat_t previous_last;
    int completed;
    int reset_count=0;
    bit was_reset=0,stale_sent=0;
    int quantum;
    for(genvar p=0;p<N_RX;p++) begin : g_capture
        assign captures[p]=rx[p].beat;
        assign capture_valid[p]=rx[p].valid && rx[p].ready;
        assign rx[p].ready=ready[p] && obs.rst_n;
    end
    // Output-dependent retirement is sampled at the same edge as the bus.
    always_comb begin
        events=plan;
        if(obs.rst_n && tx.valid && tx.ready && active!=null) begin
            if((offset+1)*8 % CELL_BYTES==0 || tx.beat.last) begin
                events.cell_free.valid=1;
                events.cell_free.id=CELL_ID_W'(active.cells[cell_index]);
                events.cell_free.desc=DESC_ID_W'(active.desc);
                events.cell_free.qid=active.info.qid;
            end
            if(tx.beat.last) events.tx_done='{1,DESC_ID_W'(active.desc),active.info.qid,active.info.length};
        end
        obs.trace_events=events;
        if($test$plusargs("MUT_SCHEDULE") && events.dispatch.valid) obs.trace_events.dispatch.info.length=events.dispatch.info.length+1;
        if($test$plusargs("MUT_SERVICE") && events.rx_service.valid) obs.trace_events.rx_service.beat.data[0]=!events.rx_service.beat.data[0];
        obs.live='0;
        obs.live.unreserved=CELL_COUNT_W'(u);obs.live.reserved_free=CELL_COUNT_W'(r);
        obs.live.assigned=CELL_COUNT_W'(a);obs.live.physical_free=CELL_COUNT_W'(N_CELL-a);obs.live.free_desc=DESC_COUNT_W'(d);
        for(int q=0;q<N_Q;q++) obs.live.owned[q*CELL_COUNT_W+:CELL_COUNT_W]=CELL_COUNT_W'(h[q]);
    end
    initial begin
        quantum=$test$plusargs("SMALL_QUANTUM")?64:MAX_PACKET_BYTES;
        foreach(ingress[p]) ingress[p]=new;
        foreach(queues[q]) queues[q]=new;
        plan='0;ready='0;tx.valid=0;tx.beat='0;obs.statuses='0;
    end
    // Form the next action from registered state, a half cycle before sampling.
    always @(negedge clk) begin : prepare
        packet p;
        beat_t beat;
        int len,q,n,reason,remaining,id;
        bit found;
        plan='0;ready='0;obs.statuses='0;tx.valid=0;tx.beat='0;
        selected=-1;selected_desc=-1;selected_cell=-1;selected_packet=null;
        grant=0;allocate=0;bad_beat=0;next_credit=0;
        if(obs.rst_n) begin
            for(int port=0;port<N_RX;port++) begin
                ready[port]=(ingress[port].words.size()<RX_FIFO_DEPTH && cycle%7!=0);
                obs.statuses[port*STATUS_W+:STATUS_W]=pending_status[port];
            end
            if($test$plusargs("MUT_STATUS")) begin
                for(int port=0;port<N_RX;port++) if(pending_status[port].valid) obs.statuses[port*STATUS_W+STATUS_W-2-:4]=4'(FRAME_ERROR);
            end
            if(active!=null && !$test$plusargs("MUT_LOST")) begin
                tx.valid=1;tx.beat=active.words[offset];
                tx.beat.user={16'b0,8'(active.info.source),active.info.tag,active.info.length,8'(active.info.qid)};
                if($test$plusargs("MUT_CORRUPT")) tx.beat.data[0]=!tx.beat.data[0];
            end else if(active==null && completed>0 && !duplicate_sent && $test$plusargs("MUT_DUPLICATE")) begin
                tx.valid=1;tx.beat=previous_last;
            end
            if($test$plusargs("MUT_STALE") && reset_count>1 && !stale_sent) begin tx.valid=1;tx.beat=previous_last;end
            // One queue inspected each free-TX cycle; quantum once per visit.
            if(active==null) begin
                if(queues[cursor].packets.size()!=0) begin
                    p=queues[cursor].packets[0];next_credit=deficit[cursor]+(visit?0:quantum);
                    grant=(int'(p.info.length)<=next_credit);
                    if(grant) plan.dispatch='{1,Q_ID_W'(cursor),DESC_ID_W'(p.desc),p.info};
                end
            end
            // Serialize cleanup in this fixture. Production concurrency is not claimed.
            if(cleaning!=null && active==null) begin
                p=cleaning;
                if(p.cells.size()!=0) plan.cell_free='{1,CELL_ID_W'(p.cells[0]),1,p.info.qid,DESC_ID_W'(p.desc)};
                if(p.cells.size()<=1) plan.abort_done='{1,p.info.source,DESC_ID_W'(p.desc),p.info.qid,p.info.ncell};
            end
            found=0;
            for(int k=0;k<N_RX;k++) begin
                id=(rr+k)%N_RX;
                if(!found && ingress[id].words.size()!=0 && !pending_status[id].valid && cleaning==null) begin selected=id;found=1;end
            end
            if(selected>=0) begin
                beat=ingress[selected].words[0];p=receiving[selected];
                plan.rx_service='{1,RX_ID_W'(selected),beat,p==null};
                if(p==null) begin
                    p=new;p.info.source=RX_ID_W'(selected);p.info.qid=Q_ID_W'(beat.user[7:0]);p.info.tag=beat.user[39:24];p.info.length=beat.user[23:8];
                    len=int'(beat.user[23:8]);q=int'(beat.user[7:0]);n=(len+CELL_BYTES-1)/CELL_BYTES;
                    p.info.ncell=CELL_COUNT_W'(n);reason=0;
                    if(q>=N_Q) reason=1;else if(len==0 || len>MAX_PACKET_BYTES) reason=2;
                    else if(h[q]+n>N_CELL) reason=3;else if(d==0) reason=4;else if(u<n) reason=5;
                    p.rejected=(reason!=0);
                    for(int di=N_DESC-1;di>=0;di--) if(used_desc[di]==0) selected_desc=di;
                    p.desc=selected_desc;
                    plan.admit='{1,RX_ID_W'(selected),8'(q),beat.user[39:24],16'(len),CELL_COUNT_W'(n),!p.rejected,status_code_t'(reason),DESC_ID_W'(selected_desc)};
                    if($test$plusargs("MUT_ADMISSION") && reason==0) begin plan.admit.accept=0;plan.admit.reason=NO_CELLS;end
                end
                selected_packet=p;remaining=int'(p.info.length)-p.seen;
                bad_beat=remaining<=0 || beat.keep!=8'((1<<((remaining>=8)?8:remaining))-1) || beat.last!=(remaining<=8);
                if(!p.rejected && !p.bad) begin
                    if(bad_beat) plan.abort_mark='{1,RX_ID_W'(selected),DESC_ID_W'(p.desc),p.info.qid,p.info.head,CELL_COUNT_W'(p.cells.size()),p.info.ncell};
                    else begin
                        allocate=(p.seen%CELL_BYTES==0);
                        if(allocate) begin
                            for(int ci=N_CELL-1;ci>=0;ci--) if(used_cells[ci]==0) selected_cell=ci;
                            plan.cell_alloc='{1,CELL_ID_W'(selected_cell),DESC_ID_W'(p.desc)};
                            if(p.seen==0) p.info.head=CELL_ID_W'(selected_cell);
                        end
                        if(beat.last) plan.commit='{1,DESC_ID_W'(p.desc),p.info.qid,p.info};
                    end
                end
            end
        end
    end

    always @(posedge clk) begin : advance
        beat_t discard;
        packet p,removed;
        int q,id;
        #1; // Monitors sample immutable pre-state before fixture state advances.
        if(!obs.rst_n) begin
            if(!was_reset) reset_count++;was_reset=1;
            foreach(ingress[port]) begin ingress[port].words.delete();receiving[port]=null;pending_status[port]='0;end
            foreach(queues[qi]) begin queues[qi].packets.delete();deficit[qi]=0;h[qi]=0;end
            foreach(used_cells[ci]) used_cells[ci]=0;
            foreach(used_desc[di]) used_desc[di]=0;
            reserved.delete();active=null;cleaning=null;rr=0;cursor=0;visit=0;offset=0;cell_index=0;
            u=N_CELL;r=0;a=0;d=N_DESC;cycle=0;completed=0;duplicate_sent=0;
        end else begin
            was_reset=0;cycle++;
            foreach(pending_status[port]) pending_status[port]='0;
            if(events.cell_free.valid) begin
                id=int'(events.cell_free.id);used_cells[id]=0;a--;
                if(events.cell_free.abort_source) begin r++;id=cleaning.cells.pop_front();end
                else begin u++;h[int'(events.cell_free.qid)]--;cell_index++;end
            end
            if(events.abort_done.valid) begin
                p=cleaning;u+=int'(p.info.ncell);r-=int'(p.info.ncell);h[int'(p.info.qid)]-=int'(p.info.ncell);d++;
                used_desc[p.desc]=0;reserved.delete(p.desc);
                pending_status[int'(p.info.source)]='{1,FRAME_ERROR,p.info.tag,8'(p.info.qid),p.info.length};cleaning=null;
            end
            if(tx.valid && tx.ready) begin
                if(active!=null) begin
                    if(tx.beat.last) begin
                        previous_last=tx.beat;completed++;d++;used_desc[active.desc]=0;reserved.delete(active.desc);active=null;
                    end else offset++;
                end else begin duplicate_sent=1;stale_sent=1;end
            end
            // plan.dispatch was computed before any current commit or completion.
            if(plan.dispatch.valid) begin
                q=int'(plan.dispatch.qid);active=queues[q].packets.pop_front();offset=0;cell_index=0;
                deficit[q]=next_credit-int'(active.info.length);visit=1;
            end else if(active==null && !events.tx_done.valid) begin
                deficit[cursor]=queues[cursor].packets.size()==0?0:next_credit;
                cursor=(cursor+1)%N_Q;visit=0;
            end
            if(plan.rx_service.valid) begin
                id=selected;p=selected_packet;discard=ingress[id].words.pop_front();rr=(id+1)%N_RX;
                if(plan.admit.valid) begin
                    receiving[id]=p;
                    if(!p.rejected) begin
                        used_desc[p.desc]=1;reserved[p.desc]=p;d--;u-=int'(p.info.ncell);r+=int'(p.info.ncell);h[int'(p.info.qid)]+=int'(p.info.ncell);
                    end else pending_status[id]='{1,plan.admit.reason,plan.admit.tag,plan.admit.qid,plan.admit.length};
                end
                if(plan.cell_alloc.valid) begin p.cells.push_back(selected_cell);used_cells[selected_cell]=1;a++;r--;end
                if(plan.abort_mark.valid) begin p.bad=1;cleaning=p;end
                if(!p.rejected && !p.bad) p.words.push_back(discard);
                if(plan.commit.valid) begin
                    queues[int'(p.info.qid)].packets.push_back(p);pending_status[id]='{1,COMMITTED,p.info.tag,8'(p.info.qid),p.info.length};
                end
                p.seen+=8;
                if(discard.last) receiving[id]=null;
            end
            if(plan.dispatch.valid) begin
                q=int'(plan.dispatch.qid);
                if(queues[q].packets.size()==0) begin deficit[q]=0;cursor=(q+1)%N_Q;visit=0;end
            end
            for(int port=0;port<N_RX;port++) if(capture_valid[port]) ingress[port].words.push_back(captures[port]);
        end
    end

    logic have_aw,have_w;
    logic [31:0] awaddr,wdata,control;
    logic [3:0] wstrb;
    // Independent holds, registered outputs and read-before-write.
    always @(posedge clk) begin
        if(!obs.rst_n) begin bus.rsp<='0;have_aw<=0;have_w<=0;control<=0;end
        else begin
            bus.rsp.awready<=!have_aw && !bus.rsp.bvalid;
            bus.rsp.wready<=!have_w && !bus.rsp.bvalid;
            bus.rsp.arready<=!bus.rsp.rvalid;
            if(bus.req.awvalid && bus.rsp.awready) begin have_aw<=1;awaddr<=bus.req.awaddr;bus.rsp.awready<=0;end
            if(bus.req.wvalid && bus.rsp.wready) begin have_w<=1;wdata<=bus.req.wdata;wstrb<=bus.req.wstrb;bus.rsp.wready<=0;end
            if(have_aw && have_w && !bus.rsp.bvalid) begin
                bus.rsp.bvalid<=1;bus.rsp.bresp<=awaddr==0?OKAY:DECERR;
                if(awaddr==0) for(int lane=0;lane<4;lane++) if(wstrb[lane]) control[lane*8+:8]<=wdata[lane*8+:8];
            end
            if(bus.rsp.bvalid && bus.req.bready) begin bus.rsp.bvalid<=0;have_aw<=0;have_w<=0;end
            if(bus.req.arvalid && bus.rsp.arready) begin
                bus.rsp.arready<=0;bus.rsp.rvalid<=1;bus.rsp.rresp<=OKAY;
                case(bus.req.araddr)
                    0:bus.rsp.rdata<=control;
                    'h024:bus.rsp.rdata<=32'(u);
                    'h028:bus.rsp.rdata<=32'(r);
                    'h02c:bus.rsp.rdata<=32'(d);
                    default:begin bus.rsp.rdata<=0;bus.rsp.rresp<=DECERR;end
                endcase
            end
            if(bus.rsp.rvalid && bus.req.rready) bus.rsp.rvalid<=0;
        end
    end
endmodule
