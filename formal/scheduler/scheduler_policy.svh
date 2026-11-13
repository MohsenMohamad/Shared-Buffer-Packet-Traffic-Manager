// Independent policy history: only queue queries, static quanta and TX events
// determine this state. Observed grants and DUT FSM state never advance it.
// State equalities below are induction lemmas, not reference inputs.
qid_t policy_queue;
logic policy_open, policy_busy;
logic [N_Q*DEFICIT_W-1:0] policy_credit, policy_credit_next;
qid_t policy_queue_next;
logic policy_open_next, policy_eligible, policy_dispatch;
integer policy_funded;
descriptor_t policy_head;
always_comb begin
    policy_head = head_info[policy_queue*DESC_INFO_W +: DESC_INFO_W];
    policy_funded = int'(policy_credit[policy_queue*DEFICIT_W +: DEFICIT_W]);
    if(SCHED_MODE==1 && !policy_open && counts[policy_queue*DESC_COUNT_W +: DESC_COUNT_W]!=0)
        policy_funded += int'(cfg.quantum[policy_queue*13 +: 13]);
    policy_eligible = cfg.run && !policy_busy &&
        counts[policy_queue*DESC_COUNT_W +: DESC_COUNT_W]!=0 &&
        (SCHED_MODE==0 || int'(policy_head.length)<=policy_funded);
    policy_dispatch = policy_eligible && tx_ready;
    policy_queue_next = policy_queue;
    policy_open_next = policy_open;
    policy_credit_next = policy_credit;
    if(cfg.run && !policy_busy) begin
        if(counts[policy_queue*DESC_COUNT_W +: DESC_COUNT_W]==0) begin
            policy_credit_next[policy_queue*DEFICIT_W +: DEFICIT_W] = '0;
            policy_open_next = 0;
            policy_queue_next = Q_ID_W'((int'(policy_queue)+1)%N_Q);
        end else if(SCHED_MODE==1) begin
            policy_credit_next[policy_queue*DEFICIT_W +: DEFICIT_W] = DEFICIT_W'(policy_funded);
            policy_open_next = 1;
            if(!policy_eligible) begin
                policy_open_next = 0;
                policy_queue_next = Q_ID_W'((int'(policy_queue)+1)%N_Q);
            end
        end
        if(policy_dispatch) begin
            policy_credit_next[policy_queue*DEFICIT_W +: DEFICIT_W] =
                SCHED_MODE==1 ? DEFICIT_W'(policy_funded-int'(policy_head.length)) : '0;
            if(SCHED_MODE==0 ||
               (counts[policy_queue*DESC_COUNT_W +: DESC_COUNT_W]==1 &&
                !(commit.valid && commit.qid==policy_queue))) begin
                policy_credit_next[policy_queue*DEFICIT_W +: DEFICIT_W] = '0;
                policy_open_next = 0;
                policy_queue_next = Q_ID_W'((int'(policy_queue)+1)%N_Q);
            end
        end
    end
end
always_ff @(posedge clk) begin
    if(!rst_n) begin
        policy_queue <= '0;
        policy_open <= 0;
        policy_busy <= 0;
        policy_credit <= '0;
    end else begin
        policy_queue <= policy_queue_next;
        policy_open <= policy_open_next;
        policy_credit <= policy_credit_next;
        policy_busy <= policy_dispatch || (policy_busy && !tx_done.valid);
        // Policy legality and mandatory baseline timing have distinct labels.
        a_policy_grant: assert(!dispatch.valid || (policy_eligible && tx_ready));
        a_policy_head: assert(!dispatch.valid || (dispatch.qid==policy_queue &&
            dispatch.desc==heads[policy_queue*DESC_ID_W +: DESC_ID_W] && dispatch.info==policy_head));
        a_policy_timing: assert(dispatch.valid==policy_dispatch);
        a_policy_credit: assert(deficits==policy_credit);
        a_policy_cursor: assert(dut.cursor==policy_queue);
        a_policy_visit: assert(dut.visit_active==policy_open);
        a_policy_busy: assert(dut.tx_owned==policy_busy);
        c_completion_wait: cover(policy_busy && tx_done.valid && tx_ready &&
            counts[policy_queue*DESC_COUNT_W +: DESC_COUNT_W]!=0);
        if(SCHED_MODE==1) c_paused_visit: cover(!cfg.run && policy_open && !policy_busy);
        c_reset_owned: cover(history && !$past(rst_n) && $past(policy_busy));
    end
end
