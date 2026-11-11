// Unresolved sentinel is intentional: both frontends MUST reject bad elaborations.
localparam bit CONFIG_VALID =
    DATA_W==64 && (N_RX==1 || N_RX==2 || N_RX==4) &&
    (N_Q==2 || N_Q==4 || N_Q==8 || N_Q==16) &&
    (CELL_BYTES==16 || CELL_BYTES==32 || CELL_BYTES==64) &&
    N_CELL>=16 && N_CELL<=1024 && (N_CELL & (N_CELL-1))==0 &&
    N_DESC>=8 && N_DESC<=256 && (N_DESC & (N_DESC-1))==0 &&
    MAX_PACKET_BYTES>=64 && MAX_PACKET_BYTES<=1536 && MAX_PACKET_BYTES<=N_CELL*CELL_BYTES &&
    (RX_FIFO_DEPTH==2 || RX_FIFO_DEPTH==4) &&
    (MEM_RD_LATENCY==1 || MEM_RD_LATENCY==2) && TX_FIFO_DEPTH>=MEM_RD_LATENCY+2 &&
    (SCHED_MODE==0 || SCHED_MODE==1) && QUANTUM_DEFAULT>=64 && QUANTUM_DEFAULT<=4096 &&
    (TRACE_ENABLE==0 || TRACE_ENABLE==1) &&
    CELL_ID_W>=$clog2(N_CELL) && DESC_ID_W>=$clog2(N_DESC) &&
    CELL_COUNT_W>=$clog2(N_CELL+1) && DESC_COUNT_W>=$clog2(N_DESC+1) &&
    DEFICIT_W>=$clog2(4096+MAX_PACKET_BYTES);
generate if (!CONFIG_VALID) begin : g_invalid
    TM_INVALID_CONFIGURATION invalid_configuration();
end endgenerate
