// Verification-only independent live-ID model; no return legality assumptions.
logic [CAPACITY-1:0] f_live;
logic f_error, f_alloc;
logic [RETURNS-1:0] f_returns;
integer f_population;
always_comb begin
    f_population=0;
    for(integer bit_id=0;bit_id<CAPACITY;bit_id=bit_id+1)
        f_population=f_population+int'(free_bitmap[bit_id]);
    f_alloc=alloc_valid && available && alloc_id==available_id;
    f_returns='0;
    for(integer r=0;r<RETURNS;r=r+1) begin
        if(return_valid[r] && int'(return_id[r*ID_W +: ID_W])<CAPACITY)
            f_returns[r]=f_live[return_id[r*ID_W +: ID_W]];
        if(r==1 && f_returns[0] && return_id[r*ID_W +: ID_W]==return_id[0 +: ID_W])
            f_returns[r]=0;
    end
end
always @(posedge clk) begin
    if (!rst_n) begin
        f_live <= '0;
        f_error <= 0;
    end else begin
        for(integer id=0;id<CAPACITY;id=id+1) begin
            if(f_alloc && alloc_id==ID_W'(id)) f_live[id]<=1;
            for(integer r=0;r<RETURNS;r=r+1)
                if(f_returns[r] && return_id[r*ID_W +: ID_W]==ID_W'(id)) f_live[id]<=0;
        end
        f_error <= f_error || (alloc_valid && !f_alloc) || (|(return_valid & ~f_returns));
    end
end
always @(posedge clk) begin
    if (rst_n) begin
        a_population: assert(int'(free_count)==f_population);
        a_bound: assert(free_count<=COUNT_W'(CAPACITY));
        a_ownership: assert(f_live==~free_bitmap);
        a_error: assert(invariant_error==f_error);
        a_allocation: assert(alloc_ok==f_alloc);
        a_returns: assert(return_ok==f_returns);
        a_availability: assert(available==(free_count!=0));
        if(available) begin
            a_free_selection: assert(free_bitmap[available_id]);
            for(integer id=0;id<CAPACITY;id=id+1)
                if(id<int'(available_id)) assert(!free_bitmap[id]);
        end
        if(f_alloc) a_no_live_reallocation: assert(!f_live[alloc_id]);
        c_exhaust: cover(free_count==0);
        c_invalid: cover(|(return_valid & ~f_returns));
        c_simultaneous: cover(f_alloc && (|f_returns));
        if(RETURNS==2) begin
            c_two_returns: cover(&f_returns);
            c_alloc_two_returns: cover(f_alloc && (&f_returns));
            c_duplicate: cover((&return_valid) && f_returns[0] && !f_returns[RETURNS-1] &&
                                   return_id[0 +: ID_W]==return_id[(RETURNS-1)*ID_W +: ID_W]);
        end
    end
end
logic f_was_exhausted=0, f_reset_active=0, f_past=0;
always @(posedge clk) begin
    f_past<=1;
    if(!rst_n) f_was_exhausted<=0;
    if(rst_n && free_count==0) f_was_exhausted<=1;
    if(f_past && !rst_n && $past(rst_n) && f_live!=0) f_reset_active<=1;
    c_recovery: cover(rst_n && f_was_exhausted && free_count==COUNT_W'(CAPACITY));
    c_reset_active: cover(rst_n && f_reset_active && free_count==COUNT_W'(CAPACITY) && !invariant_error);
end
