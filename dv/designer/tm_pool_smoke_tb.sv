module tm_pool_smoke_tb;
    import uvm_pkg::*;
    import tm_pool_smoke_types::*;
    import tm_pool_smoke_pkg::*;

    tm_pool_smoke_if bus();

    tm_resource_pools #(.PROFILE(PROFILE)) dut (
        .clk(bus.clk), .rst_n(bus.rst_n),
        .reserve_commit(bus.pins.commit), .reserve_cells(bus.pins.cells),
        .reserve_qid(bus.pins.qid), .rank_valid(bus.sampled.rank_valid),
        .rank_id(bus.sampled.rank_id), .grant_desc(bus.sampled.grant_desc),
        .write_offer(bus.pins.write_offer), .write_accept(bus.sampled.write_accept),
        .write_id(bus.sampled.write_id), .tx_present(bus.pins.tx_present),
        .tx_final(bus.pins.tx_final), .tx_cell(bus.pins.tx_cell),
        .tx_qid(bus.pins.tx_qid), .tx_desc(bus.pins.tx_desc),
        .cleanup_present(bus.pins.cleanup_present), .cleanup_has_cell(bus.pins.cleanup_has_cell),
        .cleanup_done(bus.pins.cleanup_done), .cleanup_cell(bus.pins.cleanup_cell),
        .cleanup_qid(bus.pins.cleanup_qid), .cleanup_desc(bus.pins.cleanup_desc),
        .cleanup_released(bus.pins.cleanup_released), .ready(bus.sampled.ready),
        .free_cells(bus.sampled.counts.f), .unreserved(bus.sampled.counts.u),
        .reserved_free(bus.sampled.counts.r), .free_desc(bus.sampled.counts.d),
        .held(bus.sampled.counts.h)
    );

    initial begin
        bit fault_review;
        fault_review = $test$plusargs("review_fault");
        uvm_config_db#(virtual tm_pool_smoke_if)::set(null, "*", "bus", bus);
        run_test(fault_review ? "pool_fault_review" : "pool_smoke_test");
    end
endmodule
