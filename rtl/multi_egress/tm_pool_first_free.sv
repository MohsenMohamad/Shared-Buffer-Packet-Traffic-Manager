// Two-level priority selection from Decision 0010. Both profiles have complete groups.
module tm_pool_first_free #(
    parameter int SIZE = 16,
    parameter int GROUP_SIZE = 16,
    localparam int ID_W = SIZE > 1 ? $clog2(SIZE) : 1
) (
    input  logic [SIZE-1:0] available,
    output logic any_free,
    output logic [ID_W-1:0] selected
);
    localparam int GROUPS = SIZE / GROUP_SIZE;
    logic [GROUPS-1:0] nonempty;

    for (genvar group_index = 0; group_index < GROUPS; group_index++) begin : g_nonempty
        assign nonempty[group_index] = |available[group_index*GROUP_SIZE +: GROUP_SIZE];
    end

    assign any_free = |nonempty;

    always_comb begin : select_address
        logic [ID_W-1:0] group_id, offset;
        logic [GROUP_SIZE-1:0] group_bits;
        group_id = '0;
        for (int group_index = GROUPS-1; group_index >= 0; group_index--)
            if (nonempty[group_index]) group_id = ID_W'(group_index);

        group_bits = available[group_id*GROUP_SIZE +: GROUP_SIZE];
        offset = '0;
        for (int bit_index = GROUP_SIZE-1; bit_index >= 0; bit_index--)
            if (group_bits[bit_index]) offset = ID_W'(bit_index);

        selected = ID_W'(group_id * GROUP_SIZE) | offset;
    end
endmodule
