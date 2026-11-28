module multi_egress_pool_candidate;
    import uvm_pkg::*;
    import multi_egress_pool_types::*;
    import multi_egress_pool_bench::*;

    localparam int PROFILE = N_RX == 2 ? tm_multi_fixed::SMALL : tm_multi_fixed::PRIMARY;
    bit clk;
    always #5 clk = ~clk;
    multi_egress_pool_bus signals(clk);
    pool_candidate_bus port_signals(clk);

    tm_resource_pools #(.PROFILE(PROFILE)) dut (
        .clk, .rst_n(port_signals.rst_n), .ready(port_signals.ready),
        .reserve_commit(port_signals.reserve_commit), .reserve_cells(port_signals.reserve_cells),
        .reserve_qid(port_signals.reserve_qid), .rank_valid(port_signals.rank_valid),
        .rank_id(port_signals.rank_id), .grant_desc(port_signals.grant_desc),
        .write_offer(port_signals.write_offer), .write_accept(port_signals.write_accept),
        .write_id(port_signals.write_id),
        .tx_present(port_signals.tx_present), .tx_final(port_signals.tx_final),
        .tx_cell(port_signals.tx_cell), .tx_qid(port_signals.tx_qid), .tx_desc(port_signals.tx_desc),
        .cleanup_present(port_signals.cleanup_present), .cleanup_has_cell(port_signals.cleanup_has_cell),
        .cleanup_done(port_signals.cleanup_done), .cleanup_cell(port_signals.cleanup_cell),
        .cleanup_qid(port_signals.cleanup_qid), .cleanup_desc(port_signals.cleanup_desc),
        .cleanup_released(port_signals.cleanup_released),
        .free_cells(port_signals.free_cells), .unreserved(port_signals.unreserved),
        .reserved_free(port_signals.reserved_free), .free_desc(port_signals.free_desc),
        .held(port_signals.held)
    );

    // Passive taps at the input of the actual state-owning submodules.
    assign port_signals.cell_present = dut.cells.return_present;
    assign port_signals.desc_present = dut.descriptors.return_present;
    assign port_signals.release_present = dut.accounting.release_present;
    assign port_signals.return_cell = dut.cells.return_cell;
    assign port_signals.return_desc = dut.descriptors.return_desc;
    assign port_signals.release_qid = dut.accounting.release_qid;
    assign port_signals.release_cells = dut.accounting.release_cells;
    assign port_signals.cell_free = dut.cells.free_bits;
    assign port_signals.desc_free = dut.descriptors.free_bits;

    initial begin
        uvm_config_db#(virtual multi_egress_pool_bus)::set(null, "uvm_test_top", "bus", signals);
        uvm_config_db#(virtual pool_candidate_bus)::set(null, "uvm_test_top", "candidate", port_signals);
        run_test("pool_test");
    end
endmodule
