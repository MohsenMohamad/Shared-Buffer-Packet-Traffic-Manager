module cell_control #(
    parameter int P = 4, N_CELL = 1024, N_DESC = 256, ABORT_FEEDBACK = 0,
    localparam int B = $clog2(P), C = $clog2(N_CELL), D = $clog2(N_DESC)
) (
    input logic clk, rst_n,
    input logic [P-1:0] staged_valid, staged_final, previous_valid,
    input logic [P-1:0][C-1:0] previous_cell,
    input logic [P-1:0][D-1:0] staged_desc,
    input logic [P-1:0] read_eligible, read_more,
    input logic [P-1:0][C-1:0] read_cell,
    input logic [P-1:0][D-1:0] read_desc,
    input logic [P-1:0] abort_valid, abort_has_cell, abort_more,
    input logic [P-1:0][4:0] abort_cells,
    input logic [P-1:0][C-1:0] abort_cell,
    input logic [P-1:0][D-1:0] abort_desc,
    input logic [P-1:0] tx_return,
    input logic [P-1:0][C-1:0] tx_return_cell,
    input logic [P-1:0][D-1:0] tx_return_desc,
    output logic write_valid, final_write, issue_valid, cleanup_valid, cleanup_done,
    output logic [B-1:0] write_port, issue_port, cleanup_port,
    output logic [C-1:0] write_addr, payload_read_addr, tx_successor, abort_successor,
    output logic [D-1:0] write_owner,
    output logic invariant_error
);
    localparam int GROUP = N_CELL >= 32 ? 32 : N_CELL;
    localparam int GROUPS = N_CELL / GROUP;
    logic [N_CELL-1:0] free_cell, allocated, returned;
    logic [C-1:0] links [N_CELL];
    logic [D-1:0] owners [N_CELL];
    logic [B-1:0] wr_cursor, tx_cursor, reclaim_cursor;
    logic [B-1:0] wr, tx, reclaim;
    logic [C-1:0] addr, abort_link;
    logic wr_grant, tx_grant, abort_grant, bad_action;

    function automatic logic [B-1:0] rotate(
        input logic [P-1:0] valid, input logic [B-1:0] cursor
    );
        logic [B-1:0] port_id, selected;
        selected = cursor;
        for (int i = P-1; i >= 0; i--) begin
            port_id = cursor + B'(i);
            if (valid[port_id]) selected = port_id;
        end
        return selected;
    endfunction

    function automatic logic [C-1:0] first_free(input logic [N_CELL-1:0] bits);
        logic [GROUPS-1:0] nonempty;
        logic [C-1:0] block_id, offset;
        logic [GROUP-1:0] block_bits;
        for (int g = 0; g < GROUPS; g++)
            nonempty[g] = |bits[g*GROUP +: GROUP];
        block_id = '0;
        for (int g = GROUPS-1; g >= 0; g--)
            if (nonempty[g]) block_id = C'(g);
        block_bits = bits[block_id * GROUP +: GROUP];
        offset = '0;
        for (int b = GROUP-1; b >= 0; b--)
            if (block_bits[b]) offset = C'(b);
        return C'(block_id * GROUP) | offset;
    endfunction

    logic [P-1:0] reclaim_valid, reclaim_has_cell, reclaim_more;
    logic [P-1:0][C-1:0] reclaim_cell;
    logic [P-1:0][D-1:0] reclaim_desc;
    if (ABORT_FEEDBACK == 0) begin : external_cursor
        assign reclaim_valid = abort_valid;
        assign reclaim_has_cell = abort_has_cell;
        assign reclaim_more = abort_more;
        assign reclaim_cell = abort_cell;
        assign reclaim_desc = abort_desc;
    end else begin : registered_cursor
        for (genvar p = 0; p < P; p++) begin : ingress
            logic [4:0] remaining;
            assign reclaim_has_cell[p] = remaining != 0;
            assign reclaim_more[p] = remaining > 1;
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    reclaim_valid[p] <= 1'b0;
                    remaining <= '0;
                    reclaim_cell[p] <= '0;
                    reclaim_desc[p] <= '0;
                end else if (abort_grant && reclaim == B'(p)) begin
                    if (reclaim_more[p]) begin
                        reclaim_cell[p] <= abort_link;
                        remaining <= remaining - 5'd1;
                    end else begin
                        reclaim_valid[p] <= 1'b0;
                        remaining <= '0;
                    end
                end else if (abort_valid[p] && !reclaim_valid[p]) begin
                    // Abort mark supplies the old first cell and assigned count.
                    // The caller includes any coincident materialization.
                    reclaim_valid[p] <= 1'b1;
                    remaining <= abort_cells[p];
                    reclaim_cell[p] <= abort_cell[p];
                    reclaim_desc[p] <= abort_desc[p];
                end
            end
        end
    end

    assign wr = rotate(staged_valid, wr_cursor);
    assign tx = rotate(read_eligible, tx_cursor);
    assign reclaim = rotate(reclaim_valid, reclaim_cursor);
    assign wr_grant = (|staged_valid) && (|free_cell);
    assign tx_grant = |read_eligible;
    assign abort_grant = |reclaim_valid;
    assign addr = first_free(free_cell);
    assign abort_link = links[reclaim_cell[reclaim]];

    always_comb begin
        allocated = '0;
        returned = '0;
        bad_action = (|staged_valid) && !wr_grant;
        if (wr_grant) allocated[addr] = 1'b1;
        for (int i = 0; i < P; i++) begin
            if (tx_return[i]) begin
                if (free_cell[tx_return_cell[i]] || returned[tx_return_cell[i]]
                    || owners[tx_return_cell[i]] != tx_return_desc[i])
                    bad_action = 1'b1;
                returned[tx_return_cell[i]] = 1'b1;
            end
        end
        if (abort_grant && reclaim_has_cell[reclaim]) begin
            if (free_cell[reclaim_cell[reclaim]] || returned[reclaim_cell[reclaim]]
                || owners[reclaim_cell[reclaim]] != reclaim_desc[reclaim])
                bad_action = 1'b1;
            returned[reclaim_cell[reclaim]] = 1'b1;
        end
        if (tx_grant && (free_cell[read_cell[tx]] || owners[read_cell[tx]] != read_desc[tx]))
            bad_action = 1'b1;
        if (wr_grant && previous_valid[wr] &&
            (free_cell[previous_cell[wr]] || owners[previous_cell[wr]] != staged_desc[wr]))
            bad_action = 1'b1;
    end

    always_ff @(posedge clk) begin
        if (wr_grant && rst_n) begin
            owners[addr] <= staged_desc[wr];
            if (previous_valid[wr])
                links[previous_cell[wr]] <= addr;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            free_cell <= '1;
            wr_cursor <= '0;
            tx_cursor <= '0;
            reclaim_cursor <= '0;
            write_valid <= 1'b0;
            final_write <= 1'b0;
            issue_valid <= 1'b0;
            cleanup_valid <= 1'b0;
            cleanup_done <= 1'b0;
            write_port <= '0;
            issue_port <= '0;
            cleanup_port <= '0;
            write_addr <= '0;
            payload_read_addr <= '0;
            tx_successor <= '0;
            abort_successor <= '0;
            write_owner <= '0;
            invariant_error <= 1'b0;
        end else begin
            free_cell <= (free_cell & ~allocated) | returned;
            write_valid <= wr_grant;
            final_write <= wr_grant && staged_final[wr];
            issue_valid <= tx_grant;
            cleanup_valid <= abort_grant;
            cleanup_done <= abort_grant && (!reclaim_has_cell[reclaim] || !reclaim_more[reclaim]);
            if (wr_grant) begin
                wr_cursor <= wr + B'(1);
                write_port <= wr;
                write_addr <= addr;
                write_owner <= staged_desc[wr];
            end
            if (tx_grant) begin
                tx_cursor <= tx + B'(1);
                issue_port <= tx;
                payload_read_addr <= read_cell[tx];
                if (read_more[tx])
                    tx_successor <= links[read_cell[tx]];
            end
            if (abort_grant) begin
                reclaim_cursor <= reclaim + B'(1);
                cleanup_port <= reclaim;
                if (reclaim_has_cell[reclaim] && reclaim_more[reclaim])
                    abort_successor <= abort_link;
            end
            invariant_error <= invariant_error || bad_action;
        end
    end
endmodule
