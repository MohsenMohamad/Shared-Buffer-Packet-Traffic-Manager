module tm_multi_layout #(
`include "tm_multi_parameters.svh"
`define TM_MULTI_ANSI_TYPES
`include "tm_multi_types.svh"
`undef TM_MULTI_ANSI_TYPES
) (output bit done);
    import tm_multi_fixed::*;

    // Independent offsets and widths from the interface tables.
    localparam bit IS_SMALL = PROFILE == 1;
    localparam int PORTS = IS_SMALL ? 2 : 4;
    localparam int P = IS_SMALL ? 1 : 2;
    localparam int Q = IS_SMALL ? 3 : 4;
    localparam int C = IS_SMALL ? 4 : 10;
    localparam int D = IS_SMALL ? 3 : 8;
    localparam int K = IS_SMALL ? 5 : 11;
    localparam int OWNER = IS_SMALL ? 151 : 158;
    localparam int TAG = IS_SMALL ? 157 : 171;
    localparam int READ = IS_SMALL ? 162 : 182;
    localparam int OUT = IS_SMALL ? 113 : 115;
    localparam int EGRESS_DATA_LSB = IS_SMALL ? 48 : 50;
    localparam int EGRESS_KEEP_LSB = IS_SMALL ? 40 : 42;
    localparam int EGRESS_LAST_BIT = IS_SMALL ? 39 : 41;
    localparam int EGRESS_SOURCE_LSB = IS_SMALL ? 38 : 39;
    localparam int BATCH = IS_SMALL ? 3589 : 6360;
    localparam int FRAME_MAX = IS_SMALL ? 192 : 1536;

    ingress_ports_t ingress;
    egress_ports_t egress, egress_stim;
    disposition_ports_t disposition, disposition_stim;
    memory_read_t cell_read, read_stim;
    memory_write_t cell_write, write_stim;
    memory_response_t cell_response;
    edge_batch_t observation, observation_stim;
    logic [N_RX-1:0] ingress_ready, ingress_ready_stim;
    logic [N_TX-1:0] egress_ready;
    bit reverse_bytes, truncate_route, suppress_cleanup;
    wire [PORTS*124-1:0] ingress_bits = boundary.ingress;
    wire [PORTS*OUT-1:0] egress_bits = egress;
    wire [PORTS*52-1:0] disposition_bits = disposition;

    tm_multi_ports #(.PROFILE(PROFILE), .MEM_RD_LATENCY(MEM_RD_LATENCY)) boundary (
        .clk(1'b0), .rst_n(1'b1), .epoch_id(64'h1020_3040_5060_7080),
        .ingress(ingress), .ingress_ready(ingress_ready), .egress(egress),
        .egress_ready(egress_ready), .disposition(disposition),
        .cell_read(cell_read), .cell_write(cell_write), .cell_response(cell_response),
        .observation(observation),
        .s_axil_awvalid(1'b0), .s_axil_awready(), .s_axil_awaddr(32'b0), .s_axil_awprot(3'b0),
        .s_axil_wvalid(1'b0), .s_axil_wready(), .s_axil_wdata(32'b0), .s_axil_wstrb(4'b0),
        .s_axil_bvalid(), .s_axil_bready(1'b0), .s_axil_bresp(),
        .s_axil_arvalid(1'b0), .s_axil_arready(), .s_axil_araddr(32'b0), .s_axil_arprot(3'b0),
        .s_axil_rvalid(), .s_axil_rready(1'b0), .s_axil_rdata(), .s_axil_rresp()
    );

    task automatic check(input bit condition, input string detector);
        if (!condition)
            $fatal(1, "TM03_DETECT %s profile=%0d latency=%0d", detector, PROFILE, MEM_RD_LATENCY);
    endtask

    task automatic mark(input string name);
        $display("TM03_CASE %s profile=%0d latency=%0d", name, PROFILE, MEM_RD_LATENCY);
    endtask

    task automatic check_profile();
        rx_id_t source;
        tx_id_t destination;
        qid_t queue_id;
        cell_id_t cell_id;
        desc_id_t descriptor_id;
        cell_count_t free_cells;
        desc_count_t free_descriptors;

        source = rx_id_t'(PORTS-1);
        destination = tx_id_t'(PORTS-1);
        queue_id = qid_t'(IS_SMALL ? 7 : 15);
        cell_id = cell_id_t'(IS_SMALL ? 15 : 1023);
        descriptor_id = desc_id_t'(IS_SMALL ? 7 : 255);
        free_cells = cell_count_t'(IS_SMALL ? 16 : 1024);
        free_descriptors = desc_count_t'(IS_SMALL ? 8 : 256);
        check($bits(source) == P && $bits(destination) == P && $bits(queue_id) == Q &&
              $bits(cell_id) == C && $bits(descriptor_id) == D && $bits(free_cells) == K &&
              $bits(free_descriptors) == (IS_SMALL ? 4 : 9) && $bits(deficit_t) == 13,
              "profile-width");
        check(int'(source) == PORTS-1 && int'(destination) == PORTS-1 &&
              int'(queue_id) == (IS_SMALL ? 7 : 15) && int'(cell_id) == (IS_SMALL ? 15 : 1023) &&
              int'(descriptor_id) == (IS_SMALL ? 7 : 255) && int'(free_cells) == (IS_SMALL ? 16 : 1024) &&
              int'(free_descriptors) == (IS_SMALL ? 8 : 256), "profile-values");
        check($bits(boundary.observation) == BATCH && $bits(boundary.ingress) == PORTS*124 &&
              $bits(boundary.egress) == PORTS*OUT && $bits(boundary.disposition) == PORTS*52 &&
              $bits(boundary.cell_read) == READ && $bits(boundary.cell_response) == READ+512 &&
              $bits(boundary.cell_write) == C+513 && boundary.MEM_RD_LATENCY == MEM_RD_LATENCY,
              "port-width");
        mark("profile");
    endtask

    task automatic check_bytes();
        logic [7:0] masks [0:7] = '{8'h01, 8'h03, 8'h07, 8'h0f, 8'h1f, 8'h3f, 8'h7f, 8'hff};
        logic [15:0] lengths [0:10] = '{65, 66, 67, 68, 69, 70, 71, 72, 60, 64, 16'(FRAME_MAX)};
        logic [123:0] raw_word;

        ingress = '0;
        for (int lane = 0; lane < 8; lane++)
            ingress[0].beat.data[8*(reverse_bytes ? 7-lane : lane) +: 8] = 8'(17*lane);
        ingress[0].valid = 1;
        ingress[0].beat.last = 1;
        for (int sample = 0; sample < 11; sample++) begin
            ingress[0].metadata.length = lengths[sample];
            ingress[0].beat.keep = sample < 8 ? 8'((1 << (sample+1))-1) :
                                   sample == 8 ? 8'h0f : 8'hff;
            #1;
            raw_word = ingress_bits[123:0];
            check(raw_word[122:59] == 64'h7766_5544_3322_1100, "byte-order");
            check(raw_word[123] && raw_word[50] && raw_word[49:34] == lengths[sample] &&
                  raw_word[58:51] == (sample < 8 ? masks[sample] :
                                       sample == 8 ? 8'h0f : 8'hff), "final-keep");
        end
        for (int lane = 0; lane < 8; lane++) begin
            ingress[0].beat.data = 64'h80 << (8*lane);
            ingress[0].beat.keep = 8'h01 << lane;
            #1;
            raw_word = ingress_bits[123:0];
            check(raw_word[122:59] == (64'h80 << (8*lane)) &&
                  raw_word[58:51] == (8'h01 << lane), "byte-lane-one-hot");
        end
        mark("bytes-keeps");
    endtask

    task automatic check_disposition_layout(
        input logic [51:0] word_bits, input bit valid, input logic [2:0] code,
        input logic [15:0] length, input logic [7:0] destination, traffic_class,
        input logic [15:0] opaque_tag
    );
        check(word_bits[51] == valid && word_bits[50:48] == code, "disposition-code-presence");
        if (valid) begin
            check(word_bits[31:24] == destination && word_bits[23:16] == traffic_class,
                  "disposition-destination-class-layout");
            check(word_bits[47:32] == length && word_bits[15:0] == opaque_tag,
                  "disposition-length-tag-layout");
        end
    endtask

    task automatic check_headers();
        logic [7:0] routes [0:6] = '{8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h80, 8'hff};
        logic [7:0] classes [0:4] = '{8'h00, 8'h03, 8'h04, 8'h80, 8'hff};
        logic [15:0] lengths [0:4] = '{59, 60, 16'(FRAME_MAX), 16'(FRAME_MAX+1), 16'h8060};
        disposition_code_t codes [0:6] =
            '{COMMITTED, BAD_ROUTE, BAD_LENGTH, QUEUE_LIMIT, NO_DESCRIPTOR, NO_CELLS, FRAME_ERROR};
        logic [15:0] opaque_tag;
        logic [123:0] raw_word;
        logic [51:0] status_word;
        logic [OUT-1:0] output_word;

        ingress = '0;
        disposition_stim = '0;
        egress_stim = '0;
        for (int sample = 0; sample < 8; sample++) begin
            opaque_tag = sample[0] ? 16'hab5a : 16'h125a;
            ingress[0].metadata = '{lengths[sample%5], routes[sample%7],
                                    classes[sample%5], opaque_tag, 2'(sample)};
            if (truncate_route)
                ingress[0].metadata.destination[7] = 0;
            disposition_stim[0] = '{valid: sample < 7, code: codes[sample%7],
                length: lengths[sample%5], destination: routes[sample%7],
                traffic_class: classes[sample%5], tag_value: opaque_tag};
            egress_stim[0].valid = 1;
            egress_stim[0].original_ecn = 2'(sample);
            egress_stim[0].mark_request = sample[2];
            #1;
            raw_word = ingress_bits[123:0];
            status_word = disposition_bits[51:0];
            output_word = egress_bits[OUT-1:0];
            check(raw_word[33:26] == routes[sample%7], "raw-route");
            check(raw_word[49:34] == lengths[sample%5] && raw_word[25:18] == classes[sample%5] &&
                  raw_word[17:2] == opaque_tag && raw_word[1:0] == 2'(sample), "raw-metadata");
            check_disposition_layout(status_word, sample < 7, 3'(sample%7), lengths[sample%5],
                                     routes[sample%7], classes[sample%5], opaque_tag);
            check(output_word[2:0] == {2'(sample), sample[2]}, "ecn-and-mark");
        end
        mark("raw-and-status");
    endtask

    task automatic check_ports();
        logic [PORTS-1:0] active;
        logic [123:0] expected_ingress;
        logic [OUT-1:0] output_word;

        for (int pattern = 0; pattern < (1 << PORTS); pattern++) begin
            active = PORTS'(pattern);
            ingress_ready_stim = ~active;
            egress_ready = active;
            for (int lane = 0; lane < PORTS; lane++) begin
                ingress[lane] = '{active[lane], '{64'h1122_3344_5566_7780+64'(lane), 8'(16+lane), lane[0]},
                                  '{16'(60+lane), 8'(lane), 8'(3-lane), 16'hca00+16'(lane), 2'(lane)}};
                egress_stim[lane] = '{valid: active[lane],
                    beat: '{data: 64'h7766_5544_3322_1100+64'(lane), keep: 8'(32+lane), last: !lane[0]},
                    source: P'(PORTS-1-lane), destination: P'(lane), traffic_class: 2'(lane),
                    length: 16'(72+lane), tag_value: 16'hbe00+16'(lane),
                    original_ecn: 2'(3-lane), mark_request: lane[0]};
                disposition_stim[lane] = '{valid: active[lane], code: COMMITTED, length: 16'(60+lane),
                    destination: 8'(lane), traffic_class: 8'(3-lane), tag_value: 16'hca00+16'(lane)};
            end
            #1;
            check(ingress_ready == ~active && boundary.egress_ready == active, "ready-lanes");
            for (int lane = 0; lane < PORTS; lane++) begin
                expected_ingress = {active[lane], 64'h1122_3344_5566_7780+64'(lane), 8'(16+lane),
                    lane[0], 16'(60+lane), 8'(lane), 8'(3-lane), 16'hca00+16'(lane), 2'(lane)};
                output_word = egress_bits[OUT*lane+:OUT];
                check(ingress_bits[124*lane+:124] == expected_ingress &&
                      output_word[OUT-1] == active[lane], "physical-port-order");
                if (active[lane]) begin
                    check(output_word[EGRESS_SOURCE_LSB+:P] == P'(PORTS-1-lane) &&
                          output_word[37+:P] == P'(lane), "egress-source-destination-layout");
                    check(output_word[EGRESS_DATA_LSB+:64] == 64'h7766_5544_3322_1100+64'(lane) &&
                          output_word[EGRESS_KEEP_LSB+:8] == 8'(32+lane) &&
                          output_word[EGRESS_LAST_BIT] == !lane[0] &&
                          output_word[36:35] == 2'(lane) && output_word[34:19] == 16'(72+lane) &&
                          output_word[18:3] == 16'hbe00+16'(lane) &&
                          output_word[2:1] == 2'(3-lane) && output_word[0] == lane[0],
                          "egress-packet-layout");
                end
                check_disposition_layout(disposition_bits[52*lane+:52], active[lane], 3'd0,
                                         16'(60+lane), 8'(lane), 8'(3-lane), 16'hca00+16'(lane));
            end
        end
        mark("physical-ports");
    endtask

    task automatic check_memory();
        logic [511:0] expected_write, expected_response;
        logic [TAG-1:0] expected_tag;
        logic [63:0] epoch;
        epoch = 64'h8020_3040_5060_7081;
        read_stim = '{1'b1, '{'{'{epoch, P'(PORTS-1), 64'h8110_2233_4455_6677},
                      Q'('1), D'('1), 16'hcc00}, P'(PORTS-1), K'(7)}, C'(3)};
        write_stim = '{1'b1, C'(3 | (1 << (C-1))), '0};
        cell_response = '{1'b1, read_stim.tag_value, C'(3), '0};
        expected_tag = {epoch, P'(PORTS-1), 64'h8110_2233_4455_6677,
                         Q'('1), D'('1), 16'hcc00, P'(PORTS-1), K'(7)};
        for (int lane = 0; lane < 64; lane++) begin
            expected_write = (512'h81 << (8*lane)) | 512'h22;
            expected_response = (512'hd4 << (8*(63-lane))) | (512'h13 << 504);
            write_stim.data = expected_write;
            cell_response.data = expected_response;
            #1;
            check(cell_read == {1'b1, expected_tag, C'(3)} &&
                  cell_write == {1'b1, C'(3 | (1 << (C-1))), expected_write} &&
                  boundary.cell_response == {1'b1, expected_tag, C'(3), expected_response},
                  "memory-lane-layout");
        end
        cell_response.tag_value.owner.frame.epoch = 64'h0123_4567_89ab_cdef;
        cell_response.tag_value.owner.tag_value = 16'hdd00;
        #1;
        check(boundary.cell_response[512+C+TAG-1 -:64] == 64'h0123_4567_89ab_cdef &&
              boundary.cell_response[512+C+K+P+:16] == 16'hdd00 &&
              cell_read[READ-2 -:64] == epoch && boundary.epoch_id == 64'h1020_3040_5060_7080,
              "memory-response-epoch-tag");
        mark("memory");
    endtask

    function automatic owner_t owner(input int lane);
        return '{'{64'h1020_3040_5060_7080, P'(lane), 64'(lane)}, Q'(lane),
                  D'(lane), 16'(lane)};
    endfunction

    function automatic logic [OWNER-1:0] owner_bits(input int lane);
        return {64'h1020_3040_5060_7080, P'(lane), 64'(lane), Q'(lane), D'(lane), 16'(lane)};
    endfunction

`include "tm_multi_batch_test.svh"

    initial begin
        int selected_profile;
        done = 0;
        // Isolate one profile at a time when a declaration swap is expected to stop simulation.
        if (!$value$plusargs("layout-profile=%d", selected_profile) || PROFILE == selected_profile) begin
            reverse_bytes = !IS_SMALL && MEM_RD_LATENCY == 2 && $test$plusargs("reverse-bytes");
            truncate_route = !IS_SMALL && MEM_RD_LATENCY == 2 && $test$plusargs("truncate-route");
            suppress_cleanup = !IS_SMALL && MEM_RD_LATENCY == 2 && $test$plusargs("suppress-cleanup");
            // Drive the otherwise unimplemented declaration outputs through the real ports.
            force boundary.ingress_ready = ingress_ready_stim;
            force boundary.egress = egress_stim;
            force boundary.disposition = disposition_stim;
            force boundary.cell_read = read_stim;
            force boundary.cell_write = write_stim;
            force boundary.observation = observation_stim;
            check_profile();
            check_bytes();
            check_headers();
            check_ports();
            check_memory();
            check_batch();
        end
        done = 1;
    end
endmodule

module tm_multi_layout_top;
    wire [4:0] done;
    tm_multi_layout #(.PROFILE(0), .MEM_RD_LATENCY(1)) primary_l1(done[0]);
    tm_multi_layout #(.PROFILE(0), .MEM_RD_LATENCY(2)) primary_l2(done[1]);
    tm_multi_layout #(.PROFILE(1), .MEM_RD_LATENCY(1)) small_l1(done[2]);
    tm_multi_layout #(.PROFILE(1), .MEM_RD_LATENCY(2)) small_l2(done[3]);
    tm_multi_csr_test csr(done[4]);
    initial begin
        wait (&done);
        $display("TM03_LAYOUT_PASS");
        $finish;
    end
endmodule
