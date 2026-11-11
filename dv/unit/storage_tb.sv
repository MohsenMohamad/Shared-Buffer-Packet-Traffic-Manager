module storage_tb #(
`include "tm_parameters.svh"
) ();
`include "tm_types.svh"
logic clk=0, rst_n=0;
always #5 clk=~clk;
logic enable=1, s_valid=0, s_ready, m_valid, m_ready=0, empty;
beat_t s_beat='0, m_beat;
cell_alloc_t allocate='0;
cell_return_t release_cell='0;
admission_t admit='0;
desc_return_t tx_return='0, abort_return='0;
cell_id_t cell_id;
desc_id_t desc_id;
cell_count_t cell_count;
desc_count_t desc_count;
logic cell_available, desc_available, cell_error, desc_error;
tm_axis_rx_fifo_api #(.DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES), .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY), .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .SCHED_MODE(SCHED_MODE), .QUANTUM_DEFAULT(QUANTUM_DEFAULT), .TRACE_ENABLE(TRACE_ENABLE), .CELL_ID_W(CELL_ID_W), .DESC_ID_W(DESC_ID_W), .CELL_COUNT_W(CELL_COUNT_W), .DESC_COUNT_W(DESC_COUNT_W), .DEFICIT_W(DEFICIT_W)) fifo (.*);
tm_cell_pool_api #(.DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES), .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY), .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .SCHED_MODE(SCHED_MODE), .QUANTUM_DEFAULT(QUANTUM_DEFAULT), .TRACE_ENABLE(TRACE_ENABLE), .CELL_ID_W(CELL_ID_W), .DESC_ID_W(DESC_ID_W), .CELL_COUNT_W(CELL_COUNT_W), .DESC_COUNT_W(DESC_COUNT_W), .DEFICIT_W(DEFICIT_W)) cells (.clk(clk),.rst_n(rst_n),.allocate(allocate),.release_cell(release_cell),.available_id(cell_id),.free_count(cell_count),.available(cell_available),.invariant_error(cell_error));
tm_desc_pool_api #(.DATA_W(DATA_W), .N_RX(N_RX), .N_Q(N_Q), .CELL_BYTES(CELL_BYTES), .N_CELL(N_CELL), .N_DESC(N_DESC), .MAX_PACKET_BYTES(MAX_PACKET_BYTES), .RX_FIFO_DEPTH(RX_FIFO_DEPTH), .MEM_RD_LATENCY(MEM_RD_LATENCY), .TX_FIFO_DEPTH(TX_FIFO_DEPTH), .SCHED_MODE(SCHED_MODE), .QUANTUM_DEFAULT(QUANTUM_DEFAULT), .TRACE_ENABLE(TRACE_ENABLE), .CELL_ID_W(CELL_ID_W), .DESC_ID_W(DESC_ID_W), .CELL_COUNT_W(CELL_COUNT_W), .DESC_COUNT_W(DESC_COUNT_W), .DEFICIT_W(DEFICIT_W)) descriptors (.clk(clk),.rst_n(rst_n),.admit(admit),.tx_return(tx_return),.abort_return(abort_return),.available_id(desc_id),.free_count(desc_count),.available(desc_available),.invariant_error(desc_error));

beat_t expected[$];
bit [N_CELL-1:0] cell_owned='0;
bit [N_DESC-1:0] desc_owned='0;
bit cell_expected_error=0, desc_expected_error=0;
int cycles=0, pushes=0, pops=0, simultaneous=0, blocked=0;
int cell_allocs=0, desc_allocs=0, two_returns=0, mixed=0, invalids=0;
bit last_push;
// Test inputs settle on falling edges. Models consume only sampled actions.
task automatic tick;
    bit push, pop;
    beat_t discarded;
    @(posedge clk);
    cycles++;
    if (!rst_n) begin
        expected.delete(); cell_owned='0; desc_owned='0;
        cell_expected_error=0; desc_expected_error=0;
        assert (!s_ready && !m_valid && !cell_available && !desc_available)
            else $fatal(1,"reset accepted action");
    end else begin
        assert (empty == (expected.size()==0) && m_valid == (expected.size()!=0))
            else $fatal(1,"FIFO validity");
        assert (s_ready == (enable && expected.size()<RX_FIFO_DEPTH))
            else $fatal(1,"FIFO registered ready");
        if (m_valid) assert (m_beat===expected[0]) else $fatal(1,"FIFO order/stall");
        push=s_valid && s_ready; pop=m_valid && m_ready; last_push=push;
        if (pop) begin discarded=expected.pop_front(); pops++; end
        if (push) begin expected.push_back(s_beat); pushes++; end
        if (push && pop) simultaneous++;
        if (s_valid && !s_ready) blocked++;
        check_cell(); check_desc();
    end
    #1;
    assert (int'(cell_count)==N_CELL-$countones(cell_owned) && cell_error==cell_expected_error)
        else $fatal(1,"cell merged state count=%0d expected=%0d error=%0d",cell_count,N_CELL-$countones(cell_owned),cell_error);
    assert (int'(desc_count)==N_DESC-$countones(desc_owned) && desc_error==desc_expected_error)
        else $fatal(1,"descriptor merged state count=%0d expected=%0d",desc_count,N_DESC-$countones(desc_owned));
    @(negedge clk);
endtask
task automatic check_cell;
    bit [N_CELL-1:0] old_owned;
    bit alloc_ok, r0_ok;
    int a, r0;
    old_owned=cell_owned;
    assert (cell_available==($countones(old_owned)<N_CELL)) else $fatal(1,"cell availability");
    if (cell_available) begin
        assert (!old_owned[int'(cell_id)]) else $fatal(1,"live ID selected");
        for (int i=0;i<int'(cell_id);i++) assert(old_owned[i]) else $fatal(1,"priority API");
    end
    a=int'(allocate.id); r0=int'(release_cell.id);
    alloc_ok=allocate.valid && cell_available && a==int'(cell_id);
    r0_ok=release_cell.valid && r0<N_CELL && old_owned[r0];
    if (allocate.valid) begin
        if (alloc_ok) begin cell_owned[a]=1; cell_allocs++; end
        else begin cell_expected_error=1; invalids++; end
    end
    if (release_cell.valid) begin
        if (r0_ok) cell_owned[r0]=0;
        else begin cell_expected_error=1; invalids++; end
    end
endtask
task automatic check_desc;
    bit [N_DESC-1:0] old_owned;
    bit alloc_ok, r0_ok;
    int a, r0;
    old_owned=desc_owned;
    assert (desc_available==($countones(old_owned)<N_DESC)) else $fatal(1,"desc availability");
    if (desc_available) begin
        assert (!old_owned[int'(desc_id)]) else $fatal(1,"live ID selected");
        for (int i=0;i<int'(desc_id);i++) assert(old_owned[i]) else $fatal(1,"priority API");
    end
    a=int'(admit.desc); r0=int'(tx_return.desc);
    alloc_ok=(admit.valid && admit.accept) && desc_available && a==int'(desc_id);
    r0_ok=tx_return.valid && r0<N_DESC && old_owned[r0];
    if ((admit.valid && admit.accept)) begin
        if (alloc_ok) begin desc_owned[a]=1; desc_allocs++; end
        else begin desc_expected_error=1; invalids++; end
    end
    if (tx_return.valid) begin
        if (r0_ok) desc_owned[r0]=0;
        else begin desc_expected_error=1; invalids++; end
    end
    if (abort_return.valid) begin
        if (int'(abort_return.desc)<N_DESC && old_owned[int'(abort_return.desc)] && !(r0_ok && abort_return.desc==tx_return.desc)) begin
            desc_owned[int'(abort_return.desc)]=0;
            if (r0_ok) begin two_returns++; if (alloc_ok) mixed++; end
        end else begin desc_expected_error=1; invalids++; end
    end
endtask
task automatic idle_inputs;
    allocate='0; release_cell='0; admit='0; tx_return='0; abort_return='0;
    s_valid=0; m_ready=0;
endtask
task automatic reset_all;
    rst_n=0;
    tick(); tick();
    rst_n=1;
    idle_inputs();
    tick();
    assert(empty && !m_valid && !cell_error && !desc_error) else $fatal(1,"reset recovery");
endtask
task automatic pool_actions(input bit a, input int c, input int d,
                            input bit r0, input int c0, input int d0,
                            input bit r1, input int d1);
    allocate.valid=a; allocate.id=CELL_ID_W'(c);
    admit.valid=a; admit.accept=a; admit.desc=DESC_ID_W'(d);
    release_cell.valid=r0; release_cell.id=CELL_ID_W'(c0);
    tx_return.valid=r0; tx_return.desc=DESC_ID_W'(d0);
    abort_return.valid=r1; abort_return.desc=DESC_ID_W'(d1);
    tick(); idle_inputs();
endtask
int seed, unused_random;
beat_t beat;
initial begin
    if ($test$plusargs("TRACE")) begin $dumpfile("wave.vcd"); $dumpvars(0,storage_tb); end
    if (!$value$plusargs("SEED=%d",seed)) seed=17;
    unused_random=$urandom(seed);
    @(negedge clk);
    reset_all();
    // Rejected admission is not a descriptor allocation.
    admit.valid=1; admit.accept=0; tick(); idle_inputs();
    // Exhaust both capacities without relying on their ratio.
    for(int i=0;i<N_CELL || i<N_DESC;i++) begin
        allocate.valid=(i<N_CELL); allocate.id=cell_id;
        admit.valid=(i<N_DESC); admit.accept=1; admit.desc=desc_id;
        tick(); idle_inputs();
    end
    assert(!cell_available && !desc_available) else $fatal(1,"exhaustion");
    // An owned return into an exhausted allocator cannot fund this allocation.
    pool_actions(1,0,0,1,0,0,1,1);
    assert(cell_count==1 && desc_count==2) else $fatal(1,"same-edge bypass");
    pool_actions(1,int'(cell_id),int'(desc_id),1,1,2,1,3);
    // Live allocation collides with returns of its pre-state free ID.
    pool_actions(1,int'(cell_id),int'(desc_id),1,int'(cell_id),int'(desc_id),1,int'(desc_id));
    // Duplicate owned descriptor is returned once. First lane already-free,
    // second owned must still proceed. Oversized index ports exercise invalid IDs.
    pool_actions(0,0,0,1,2,4,1,4);
    pool_actions(0,0,0,1,2,4,1,5);
    pool_actions(0,0,0,1,N_CELL,N_DESC,1,N_DESC+1);
    // Return every live member and prove full recovery despite sticky errors.
    for(int i=0;i<N_CELL || i<N_DESC;i++) begin
        if(i<N_CELL && cell_owned[i]) begin release_cell.valid=1; release_cell.id=CELL_ID_W'(i); end
        if(i<N_DESC && desc_owned[i]) begin tx_return.valid=1; tx_return.desc=DESC_ID_W'(i); end
        tick(); idle_inputs();
    end
    assert(int'(cell_count)==N_CELL && int'(desc_count)==N_DESC) else $fatal(1,"recovery");
    // Rapid reuse, invalid allocations and arbitrary release requests.
    for(int i=0;i<1200;i++) begin
        pool_actions(1, int'(cell_id), int'(desc_id), 1, i%N_CELL, i%N_DESC, 1, (i+1)%N_DESC);
    end
    pool_actions(1,N_CELL,N_DESC,0,0,0,0,0);
    // Reset collides with allocation and two returns during active ownership.
    allocate.valid=1; admit.valid=1; admit.accept=1;
    release_cell.valid=1; tx_return.valid=1; abort_return.valid=1;
    reset_all();
    // Empty cannot fall through, full cannot pop and accept on the same edge.
    m_ready=1; tick();
    m_ready=0; s_valid=1;
    for(int i=0;i<RX_FIFO_DEPTH;i++) begin s_beat=BEAT_W'(i+1); tick(); end
    s_beat=BEAT_W'(99); repeat(3) tick();
    m_ready=1; tick(); tick(); // full-to-pop bubble, then replacement
    repeat(10) begin s_beat=BEAT_W'($urandom); tick(); end
    // Reset with full FIFO and both attempted handshakes cancels old payload.
    m_ready=0;
    repeat(RX_FIFO_DEPTH) tick();
    m_ready=1; reset_all();
    // Nonempty FIFO reset, including an update collision.
    s_valid=1; s_beat=BEAT_W'(123); tick(); m_ready=1; reset_all();
    // Source obeys held-valid stability; randomized data exercise every field.
    for(int i=0;i<2400;i++) begin
        if(!s_valid || last_push) begin
            s_valid=1'($urandom_range(0,1));
            beat.data={$urandom,$urandom}; beat.keep=8'($urandom);
            beat.last=1'($urandom); beat.user={$urandom,$urandom}; s_beat=beat;
        end
        m_ready=1'($urandom_range(0,1));
        tick();
    end
    // Disable acceptance while allowing stored data to drain.
    enable=0; s_valid=1; m_ready=1; repeat(RX_FIFO_DEPTH+2) tick();
    enable=1; s_valid=0; repeat(RX_FIFO_DEPTH+2) tick();
    assert(expected.size()==0 && simultaneous>0 && blocked>0 && two_returns>0 && mixed>0 && invalids>0)
        else $fatal(1,"empty scenario selection");
    $display("TM_STORAGE_PASS cycles=%0d pushes=%0d pops=%0d simultaneous=%0d blocked=%0d cell_allocs=%0d desc_allocs=%0d two_returns=%0d mixed=%0d invalids=%0d",cycles,pushes,pops,simultaneous,blocked,cell_allocs,desc_allocs,two_returns,mixed,invalids);
    $finish;
end
endmodule
