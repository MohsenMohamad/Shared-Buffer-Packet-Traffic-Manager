// Unresolved sentinels deliberately fail elaboration in the qualified frontends.
if (PROFILE != tm_multi_fixed::PRIMARY && PROFILE != tm_multi_fixed::SMALL) begin : g_profile
    TM_MULTI_INVALID_PROFILE invalid_profile();
end
if (MEM_RD_LATENCY != 1 && MEM_RD_LATENCY != 2) begin : g_latency
    TM_MULTI_INVALID_READ_LATENCY invalid_read_latency();
end
if (N_RX != (PROFILE == tm_multi_fixed::SMALL ? 2 : 4) ||
    N_TX != (PROFILE == tm_multi_fixed::SMALL ? 2 : 4) ||
    N_CLASS != tm_multi_fixed::CLASS_COUNT ||
    N_CELL != (PROFILE == tm_multi_fixed::SMALL ? 16 : 1024) ||
    N_DESC != (PROFILE == tm_multi_fixed::SMALL ? 8 : 256) ||
    MAX_FRAME_BYTES != (PROFILE == tm_multi_fixed::SMALL ? 192 : 1536)) begin : g_geometry
    TM_MULTI_INVALID_GEOMETRY invalid_geometry();
end
if (DATA_W != 64 || CELL_W != 512) begin : g_width
    TM_MULTI_INVALID_PAYLOAD_WIDTH invalid_payload_width();
end
