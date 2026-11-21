module tm_multi_csr_test (output bit done);
    import tm_multi_csr::*;

    typedef struct packed {
        logic [2:0] access_kind;
        logic high_word;
        logic [31:0] mask;
        logic [31:0] reset_value;
        logic [31:0] minimum;
        logic [31:0] maximum;
    } expected_word_t;

    // The reviewed table is independently indexed by aligned byte address.
    expected_word_t expected [0:4095];
    bit [4095:0] used;
    bit alias_csr, swap_halves;

    task automatic check(input bit condition, input string detector, input int address);
        if (!condition)
            $fatal(1, "TM03_DETECT %s address=%08x", detector, address);
    endtask

    task automatic add_word(input int address, input logic [2:0] kind,
                            input logic [31:0] mask = 0, input logic [31:0] reset_value = 0,
                            input logic [31:0] min_value = 0, input logic [31:0] max_value = 0,
                            input logic high_word = 0);
        check(address[1:0] == 0 && address >= 0 && address < 'h4000,
              "expected-table-alignment", address);
        check(!used[address/4], "expected-table-alias", address);
        used[address/4] = 1;
        expected[address/4] = '{kind, high_word, mask, reset_value, min_value, max_value};
    endtask

    task automatic add_counters(input int base, input int count);
        for (int n = 0; n < count; n++) begin
            add_word(base + 8*n, 3);
            add_word(base + 8*n + 4, 3, 0, 0, 0, 0, 1);
        end
    endtask

    task automatic check_queue(input int ports, input int port_index, input int traffic_class,
                               input int pool, input int frame_max);
        int base, observed;
        base = 'h1000 + 'h100 * (4*port_index + traffic_class);
        observed = queue_address(ports, port_index, traffic_class, 'h08);
        if (alias_csr && port_index == 0 && traffic_class == 0)
            observed = queue_address(ports, port_index, traffic_class, 'h04);
        check(observed == base+'h08, "csr-address-alias", observed);
        for (int offset = 0; offset < 'h100; offset += 4)
            check(queue_address(ports, port_index, traffic_class, offset) == base+offset,
                  "csr-queue-coordinate", base+offset);
        add_word(base+'h00, 5, 'h7ff, pool, 0, pool);
        add_word(base+'h04, 5, 'h7ff, 0, 0, pool);
        add_word(base+'h08, 5, 'h1fff, 0, 0, 4096);
        add_word(base+'h0c, 5, 'h1fff, frame_max, 64, 4096);
        add_word(base+'h10, 5, 1, 0, 0, 1);
        add_word(base+'h14, 5, 'hf_ffff, 'h8_0000, 0, 'h8_0000);
        add_word(base+'h18, 5, 'hffff, frame_max, 0, 65535);
        add_word(base+'h1c, 5, 1, 0, 0, 1);
        add_word(base+'h20, 5, 'h7ff, 1, 1, pool);
        for (int offset = 'h24; offset <= 'h30; offset += 4)
            add_word(base+offset, 2);
        for (int offset = 'h34; offset <= 'h40; offset += 4)
            add_word(base+offset, 3);
        add_counters(base+'h48, 11);
    endtask

    task automatic check_map(input int ports, input int pool, input int frame_max);
        register_info_t info;
        int base, address, expected_count;
        used = '0;
        foreach (expected[n])
            expected[n] = '0;
        add_word('h0000, 1, 0, 1);
        add_word('h0004, 4, 1, 0, 0, 1);
        add_word('h0008, 2);
        add_word('h000c, 5, 3, 0, 0, 3);
        add_word('h0010, 6, 1, 0, 0, 1);
        for (int offset = 'h14; offset <= 'h1c; offset += 4)
            add_word(offset, 2);
        for (int offset = 'h20; offset <= 'h28; offset += 4)
            add_word(offset, 3);
        for (int port_index = 0; port_index < ports; port_index++) begin
            for (int traffic_class = 0; traffic_class < 4; traffic_class++)
                check_queue(ports, port_index, traffic_class, pool, frame_max);

            base = 'h2000 + 'h100 * port_index;
            for (int offset = 0; offset < 'h100; offset += 4)
                check(egress_address(ports, port_index, offset) == base+offset,
                      "csr-egress-coordinate", base+offset);
            add_word(base+'h00, 5, 3, 0, 0, 2);
            add_word(base+'h04, 5, 3, 0, 0, 3);
            add_word(base+'h08, 5, 1, 0, 0, 1);
            add_word(base+'h0c, 5, 'hf_ffff, 'h8_0000, 0, 'h8_0000);
            add_word(base+'h10, 5, 'hffff, frame_max, 0, 65535);
            add_counters(base+'h18, 5);

            for (int bucket = 0; bucket < 5; bucket++) begin
                base = 'h3000 + 'h400 * port_index + 'h80 * bucket;
                for (int offset = 0; offset < 'h80; offset += 4)
                    check(ingress_address(ports, port_index, bucket, offset) == base+offset,
                          "csr-ingress-coordinate", base+offset);
                add_counters(base, 11);
            end
        end

        expected_count = ports == 4 ? 1135 : 573;
        check($countones(used) == expected_count, "csr-enumeration-count", 0);
        foreach (expected[n]) begin
            address = 4*n;
            info = decode(address, ports, ports, pool, frame_max);
            check(!info.misaligned &&
                  {info.access_kind, info.counter_high, info.write_mask, info.reset_value,
                   info.minimum, info.maximum} == expected[n], "csr-map-metadata", address);
            for (int low_bits = 1; low_bits <= 3; low_bits++) begin
                info = decode(address+low_bits, ports, ports, pool, frame_max);
                check(info.misaligned == used[n] && info.access_kind == expected[n].access_kind,
                      "csr-misaligned-mapped", address+low_bits);
            end
        end
        check(queue_address(ports, 0, 4, 0) == '1 &&
              queue_address(ports, ports, 0, 0) == '1 &&
              queue_address(ports, 0, 0, 'h100) == '1 &&
              queue_address(ports, 32'hffff_ffff, 0, 0) == '1 &&
              egress_address(ports, ports, 0) == '1 &&
              egress_address(ports, 0, 'h100) == '1 &&
              ingress_address(ports, 0, 5, 0) == '1 &&
              ingress_address(ports, ports, 0, 0) == '1 &&
              ingress_address(ports, 0, 0, 'h80) == '1, "csr-illegal-coordinate", 0);
        info = decode(32'hffff_ffff, ports, ports, pool, frame_max);
        check(info.access_kind == 0 && !info.misaligned, "csr-invalid-sentinel", -1);
        info = decode(32'h8000_0004, ports, ports, pool, frame_max);
        check(info.access_kind == 0, "csr-high-address-no-alias", 'h8000_0004);
        $display("TM03_CSR_MAP ports=%0d words=%0d", ports, expected_count);
    endtask

    task automatic check_snapshot_words(input int ports, input int pool, input int frame_max);
        logic [63:0] counters [0:1] = '{64'h0123_4567_89ab_cdef, 64'hfedc_ba98_7654_3210};
        logic [31:0] halves [0:3] = '{32'h89ab_cdef, 32'h0123_4567, 32'h7654_3210, 32'hfedc_ba98};
        int addresses [0:3] = '{'h1048, 'h104c, 'h1050, 'h1054};
        register_info_t info;
        logic [31:0] data;
        for (int n = 0; n < 4; n++) begin
            info = decode(addresses[n], ports, ports, pool, frame_max);
            data = snapshot_counter_word(counters[n/2], info.counter_high ^ swap_halves);
            check(data == halves[n] && info.access_kind == 3, "snapshot-word-order", addresses[n]);
        end
        $display("TM03_CSR_SNAPSHOT ports=%0d words=4", ports);
    endtask

    task automatic check_counter_constants();
        check({8'(Q_ADMITTED), 8'(Q_PUBLISHED), 8'(Q_BAD_LENGTH), 8'(Q_QUEUE_LIMIT),
               8'(Q_NO_DESCRIPTOR), 8'(Q_NO_CELLS), 8'(Q_FRAME_ERROR), 8'(Q_DISPATCHED),
               8'(Q_RETIRED_FRAMES), 8'(Q_RETIRED_BYTES), 8'(Q_MARK_REQUESTS)} ==
              88'h00_01_02_03_04_05_06_07_08_09_0a, "csr-queue-counter-indices", 'h1048);
        check({8'(E_BEATS), 8'(E_BYTES), 8'(E_FRAMES), 8'(E_STALL), 8'(E_STARVED)} ==
              40'h00_01_02_03_04, "csr-egress-counter-indices", 'h2018);
        check({8'(I_BEATS), 8'(I_BYTES), 8'(I_LAST), 8'(I_ADMITTED), 8'(I_PUBLISHED),
               8'(I_BAD_ROUTE), 8'(I_BAD_LENGTH), 8'(I_QUEUE_LIMIT), 8'(I_NO_DESCRIPTOR),
               8'(I_NO_CELLS), 8'(I_FRAME_ERROR)} == 88'h00_01_02_03_04_05_06_07_08_09_0a,
              "csr-ingress-counter-indices", 'h3000);
        check(COUNTER_LOW == 0 && COUNTER_HIGH == 4 && COUNTER_STRIDE == 8,
              "csr-counter-stride", 0);
    endtask

    initial begin
        done = 0;
        alias_csr = $test$plusargs("alias-csr");
        swap_halves = $test$plusargs("swap-halves");
        check(AXI_OKAY == 2'b00 && AXI_SLVERR == 2'b10 && AXI_DECERR == 2'b11,
              "csr-axi-response", 0);
        check(RUN == 'h0004 && STATUS == 'h0008 && ADMISSION == 'h000c && SNAPSHOT == 'h0010 &&
              RUN_ENABLE == 1 && STATUS_IDLE == 1 && STATUS_INITIALIZED == 2 &&
              STATUS_SNAPSHOT_VALID == 4 && ADMISSION_WAIT == 1 && ADMISSION_DYNAMIC == 2 &&
              SNAPSHOT_TRIGGER == 1 && UNCLASSIFIED == 4, "csr-global-constants", 0);
        check_counter_constants();
        check_map(4, 1024, 1536);
        check_map(2, 16, 192);
        check_snapshot_words(4, 1024, 1536);
        check_snapshot_words(2, 16, 192);
        done = 1;
    end
endmodule
