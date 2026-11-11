// Shift-register reference queue, independent of the circular implementation.
logic [BEAT_W-1:0] f_queue [0:RX_FIFO_DEPTH-1];
integer f_count;
logic f_past=0, f_filled=0, f_reset_busy=0;
always @(posedge clk) begin
    f_past<=1;
    if (!rst_n) begin
        f_count<=0;
        f_filled<=0;
        if(f_past && $past(rst_n) && $past(f_count)>0) f_reset_busy<=1;
    end else begin
        a_count: assert(f_count==int'(occupancy));
        a_bounds: assert(f_count>=0 && f_count<=RX_FIFO_DEPTH);
        a_ready: assert(s_ready==(enable && f_count<RX_FIFO_DEPTH));
        a_valid: assert(m_valid==(f_count>0));
        a_empty: assert(empty==(f_count==0));
        // Relating every occupied slot makes arbitrary-duration order inductive.
        for(integer k=0;k<RX_FIFO_DEPTH;k=k+1) begin
            if(k<f_count) assert(storage[PTR_W'(rd_ptr+PTR_W'(k))]==f_queue[k]);
        end
        a_pointer: assert(wr_ptr==PTR_W'(rd_ptr+PTR_W'(f_count)));
        if(m_valid) a_head: assert(m_beat==f_queue[0]);
        if(f_past && $past(rst_n && m_valid && !m_ready)) begin
            a_stalled_valid: assert(m_valid);
            a_stalled_data: assert(m_beat==$past(m_beat));
        end
        if(pop) for(integer k=0;k<RX_FIFO_DEPTH-1;k=k+1) f_queue[k]<=f_queue[k+1];
        if(push) f_queue[f_count-int'(pop)]<=s_beat;
        f_count<=f_count+int'(push)-int'(pop);
        if(f_count==RX_FIFO_DEPTH) f_filled<=1;
        c_full: cover(f_count==RX_FIFO_DEPTH);
        c_collision: cover(push && pop);
        c_stall: cover(m_valid && !m_ready);
        c_wrap: cover(push && wr_ptr==PTR_W'(RX_FIFO_DEPTH-1));
        c_drain: cover(f_filled && f_count==0);
        c_reset_collision: cover(f_reset_busy && f_count==0 && s_valid && m_ready);
    end
end
