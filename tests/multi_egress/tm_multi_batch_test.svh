    localparam int DESC_RETURN_LANE_W = IS_SMALL ? 152 : 159;
    localparam int CELL_RETURN_LANE_W = IS_SMALL ? 156 : 169;
    localparam int CLEANUP_W = IS_SMALL ? 158 : 171;
    localparam int ABORT_LANE_W = IS_SMALL ? 157 : 170;
    localparam int RESPONSE_EVENT_W = IS_SMALL ? 163 : 183;
    localparam int ISSUE_EVENT_W = IS_SMALL ? 167 : 193;
    localparam int EGRESS_SERVICE_W = IS_SMALL ? 158 : 171;
    localparam int DISPATCH_LANE_W = IS_SMALL ? 168 : 175;
    localparam int PUBLICATION_W = IS_SMALL ? 180 : 199;
    localparam int WRITE_EVENT_W = IS_SMALL ? 162 : 181;
    localparam int ADMISSION_LANE_W = IS_SMALL ? 197 : 210;
    localparam int INGRESS_SERVICE_W = IS_SMALL ? 205 : 206;

    localparam int CELL_RETURN_BASE = IS_SMALL ? 456 : 795;
    localparam int CLEANUP_BASE = IS_SMALL ? 924 : 1640;
    localparam int ABORT_BASE = IS_SMALL ? 1082 : 1811;
    localparam int RESPONSE_BASE = IS_SMALL ? 1396 : 2491;
    localparam int ISSUE_BASE = IS_SMALL ? 1559 : 2674;
    localparam int EGRESS_SERVICE_BASE = IS_SMALL ? 1726 : 2867;
    localparam int DISPATCH_BASE = IS_SMALL ? 2042 : 3551;
    localparam int PUBLICATION_BASE = IS_SMALL ? 2378 : 4251;
    localparam int WRITE_EVENT_BASE = IS_SMALL ? 2558 : 4450;
    localparam int ADMISSION_BASE = IS_SMALL ? 2720 : 4631;
    localparam int INGRESS_SERVICE_BASE = IS_SMALL ? 3114 : 5471;
    localparam int EPOCH_BASE = IS_SMALL ? 3524 : 6295;
    localparam logic [63:0] EPOCH = 64'h1020_3040_5060_7080;

    task automatic check_return_lanes();
        logic [BATCH-1:0] expected;
        logic [PORTS:0] mask;
        for (int pattern = 0; pattern < 1 << (PORTS+1); pattern++) begin
            mask = (PORTS+1)'(pattern);
            observation_stim = '0;
            observation_stim.present = 1;
            observation_stim.epoch = EPOCH;
            expected = '0;
            expected[BATCH-1] = 1;
            expected[EPOCH_BASE+:64] = EPOCH;
            for (int lane = 0; lane <= PORTS; lane++) begin
                if (mask[lane]) begin
                    observation_stim.cell_return[lane] = '{1'b1, owner(lane), C'(lane)};
                    observation_stim.descriptor_return[lane] = '{1'b1, owner(lane)};
                    expected[CELL_RETURN_BASE+CELL_RETURN_LANE_W*lane+:CELL_RETURN_LANE_W] =
                        {1'b1, owner_bits(lane), C'(lane)};
                    expected[DESC_RETURN_LANE_W*lane+:DESC_RETURN_LANE_W] = {1'b1, owner_bits(lane)};
                end
            end
            if (suppress_cleanup)
                observation_stim.cell_return[PORTS].present = 0;
            #1;
            check(observation.cell_return[PORTS].present == mask[PORTS] &&
                  observation.descriptor_return[PORTS].present == mask[PORTS],
                  "cleanup-return");
            check(observation == expected, "return-lane-layout");
        end
        mark("all-return-masks");
        // Cleanup can finish with zero assigned cells or reclaim a non-final cell.
        observation_stim = '0;
        observation_stim.present = 1;
        observation_stim.epoch = EPOCH;
        observation_stim.cleanup = '{1'b1, owner(PORTS), 1'b1, K'(1)};
        observation_stim.descriptor_return[PORTS] = '{1'b1, owner(PORTS)};
        #1;
        check(observation.cleanup.done && !observation.cell_return[PORTS].present &&
              observation.descriptor_return[PORTS].present, "cleanup-zero-cells");
        observation_stim.cleanup.done = 0;
        observation_stim.cleanup.released = 0;
        observation_stim.descriptor_return = '0;
        observation_stim.cell_return[PORTS] = '{1'b1, owner(PORTS), C'(2)};
        #1;
        check(!observation.cleanup.done && observation.cell_return[PORTS].present &&
              !observation.descriptor_return[PORTS].present, "cleanup-intermediate");
    endtask

    task automatic check_event_lanes();
        logic [BATCH-1:0] expected;
        logic [PORTS-1:0] mask;
        stream_beat_t beat;
        owner_t frame_owner;
        for (int pattern = 0; pattern < 1 << PORTS; pattern++) begin
            mask = PORTS'(pattern);
            observation_stim = '0;
            expected = '0;
            observation_stim.present = 1;
            observation_stim.epoch = EPOCH;
            expected[BATCH-1] = 1;
            expected[EPOCH_BASE+:64] = EPOCH;
            for (int lane = 0; lane < PORTS; lane++) begin
                if (mask[lane]) begin
                    beat = '{64'h8000_0000_0000_0070+64'(lane), 8'h03, lane[0]};
                    frame_owner = owner(lane);
                    observation_stim.ingress_service[lane] =
                        '{1'b1, frame_owner.frame, 1'b1, lane[0], beat};
                    observation_stim.egress_service[lane] =
                        '{1'b1, owner(lane), C'(lane), 1'b1, lane[0]};
                    observation_stim.dispatch[lane] = '{1'b1, owner(lane), 16'(60+lane)};
                    observation_stim.abort_mark[lane] = '{1'b1, owner(lane), K'(lane+1)};
                    expected[INGRESS_SERVICE_BASE+INGRESS_SERVICE_W*lane+:INGRESS_SERVICE_W] =
                        {1'b1, EPOCH, P'(lane), 64'(lane), 1'b1, lane[0],
                         64'h8000_0000_0000_0070+64'(lane), 8'h03, lane[0]};
                    expected[EGRESS_SERVICE_BASE+EGRESS_SERVICE_W*lane+:EGRESS_SERVICE_W] =
                        {1'b1, owner_bits(lane), C'(lane), 1'b1, lane[0]};
                    expected[DISPATCH_BASE+DISPATCH_LANE_W*lane+:DISPATCH_LANE_W] =
                        {1'b1, owner_bits(lane), 16'(60+lane)};
                    expected[ABORT_BASE+ABORT_LANE_W*lane+:ABORT_LANE_W] =
                        {1'b1, owner_bits(lane), K'(lane+1)};
                end
            end
            #1;
            check(observation == expected, "physical-event-lane-layout");
        end
    endtask

    task automatic check_admissions();
        logic [BATCH-1:0] expected;
        int source;
        owner_t frame_owner;
        for (int count = 0; count <= PORTS; count++) begin
            observation_stim = '0;
            observation_stim.present = 1;
            observation_stim.epoch = EPOCH;
            expected = '0;
            expected[BATCH-1] = 1;
            expected[EPOCH_BASE+:64] = EPOCH;
            for (int lane = 0; lane < count; lane++) begin
                source = (lane + PORTS-1) % PORTS;
                frame_owner = owner(source);
                observation_stim.admission[lane] = '{1'b1, frame_owner.frame,
                    '{16'(65+lane), 8'(source), 8'(lane), 16'ha100+16'(lane), 2'(lane)},
                    GRANT, COMMITTED, 1'b1, Q'(4*source+lane), K'(2), D'(lane)};
                expected[ADMISSION_BASE+ADMISSION_LANE_W*lane+:ADMISSION_LANE_W] =
                    {1'b1, EPOCH, P'(source), 64'(source),
                     16'(65+lane), 8'(source), 8'(lane), 16'ha100+16'(lane), 2'(lane),
                     2'd0, 3'd0, 1'b1, Q'(4*source+lane), K'(2), D'(lane)};
            end
            #1;
            check(observation == expected, "admission-prefix-layout");
        end
        observation_stim = '0;
        observation_stim.present = 1;
        observation_stim.epoch = EPOCH;
        frame_owner = owner(0);
        observation_stim.admission[0] = '{1'b1, frame_owner.frame,
            '{16'd59, 8'h80, 8'hff, 16'h9955, 2'b10},
            REJECT, BAD_ROUTE, 1'b0, '0, '0, '0};
        expected = '0;
        expected[BATCH-1] = 1;
        expected[EPOCH_BASE+:64] = EPOCH;
        expected[ADMISSION_BASE+:ADMISSION_LANE_W] = {1'b1, EPOCH, P'(0), 64'd0,
            16'd59, 8'h80, 8'hff, 16'h9955, 2'b10, 2'd1, 3'd1, 1'b0, Q'(0), K'(0), D'(0)};
        #1;
        check(observation == expected, "admission-reject-layout");
        observation_stim.admission[0] = '{1'b1, frame_owner.frame,
            '{16'd65, 8'd0, 8'd0, 16'h9955, 2'b10},
            WAIT_PENDING, NO_DESCRIPTOR, 1'b1, '0, K'(2), '0};
        expected[ADMISSION_BASE+:ADMISSION_LANE_W] = {1'b1, EPOCH, P'(0), 64'd0,
            16'd65, 8'd0, 8'd0, 16'h9955, 2'b10, 2'd2, 3'd4, 1'b1, Q'(0), K'(2), D'(0)};
        #1;
        check(observation == expected, "admission-wait-layout");
    endtask

    task automatic check_correlation();
        logic [BATCH-1:0] expected;
        owner_t frame_owner, issue_owner, response_owner;
        logic [OWNER-1:0] issue_bits, response_bits;
        // A repeated opaque tag on distinct frames of one ingress, a second
        // ingress, and a stale memory response from a previous epoch.
        observation_stim = '0;
        observation_stim.present = 1;
        observation_stim.epoch = EPOCH;
        expected = '0;
        expected[BATCH-1] = 1;
        expected[EPOCH_BASE+:64] = EPOCH;
        frame_owner = '{'{EPOCH, P'(0), 64'd0}, Q'(0), D'(0), 16'h9955};
        issue_owner = '{'{EPOCH, P'(0), 64'd1}, Q'(0), D'(1), 16'h9955};
        response_owner = '{'{EPOCH, P'(1), 64'd0}, Q'(4), D'(2), 16'h9955};
        observation_stim.cell_write = '{1'b1, frame_owner, K'(0), C'(2), 1'b1};
        observation_stim.publication = '{1'b1, frame_owner, C'(2), K'(1), 16'd60, 2'b10, 1'b1};
        observation_stim.read_issue = '{'{1'b1, '{issue_owner, P'(0), K'(0)}, C'(3)}, 1'b1, C'(4)};
        observation_stim.read_response = '{'{1'b1, '{response_owner, P'(1), K'(1)}, C'(5)}, 1'b1};
        observation_stim.cleanup = '{1'b1, owner(PORTS), 1'b1, K'(2)};

        issue_bits = {EPOCH, P'(0), 64'd1, Q'(0), D'(1), 16'h9955};
        response_bits = {EPOCH, P'(1), 64'd0, Q'(4), D'(2), 16'h9955};
        expected[CLEANUP_BASE+:CLEANUP_W] = {1'b1, owner_bits(PORTS), 1'b1, K'(2)};
        expected[WRITE_EVENT_BASE+:WRITE_EVENT_W] =
            {1'b1, EPOCH, P'(0), 64'd0, Q'(0), D'(0), 16'h9955, K'(0), C'(2), 1'b1};
        expected[PUBLICATION_BASE+:PUBLICATION_W] =
            {1'b1, EPOCH, P'(0), 64'd0, Q'(0), D'(0), 16'h9955, C'(2), K'(1), 16'd60, 2'b10, 1'b1};
        expected[ISSUE_BASE+:ISSUE_EVENT_W] =
            {1'b1, issue_bits, P'(0), K'(0), C'(3), 1'b1, C'(4)};
        expected[RESPONSE_BASE+:RESPONSE_EVENT_W] =
            {1'b1, response_bits, P'(1), K'(1), C'(5), 1'b1};
        #1;
        check(observation == expected, "singleton-and-owner-layout");
        check(observation.publication.owner.frame != observation.read_issue.command.tag_value.owner.frame &&
              observation.publication.owner.frame != observation.read_response.identity.tag_value.owner.frame &&
              observation.read_issue.command.tag_value.owner.frame !=
                  observation.read_response.identity.tag_value.owner.frame, "repeated-opaque-tag");
        observation_stim.read_response.identity.tag_value.owner = frame_owner;
        observation_stim.read_response.identity.tag_value.owner.frame.epoch = EPOCH-1;
        observation_stim.read_response.accepted_epoch = 0;
        #1;
        check(observation.read_response.identity.valid && !observation.read_response.accepted_epoch &&
              observation.read_response.identity.tag_value.owner.frame != observation.publication.owner.frame &&
              observation.read_response.identity.tag_value.owner.frame.epoch == EPOCH-1,
              "stale-response-identity");
    endtask

    task automatic check_allocation_return_overlap();
        owner_t new_owner;
        logic [BATCH-1:0] expected;
        // Keep independent members populated in the same word. The lane-layout
        // fixture does not model pre-edge ownership, credit or scheduler state.
        observation_stim = '0;
        expected = '0;
        observation_stim.present = 1;
        observation_stim.epoch = EPOCH;
        expected[BATCH-1] = 1;
        expected[EPOCH_BASE+:64] = EPOCH;
        for (int lane = 0; lane <= PORTS; lane++) begin
            observation_stim.cell_return[lane] = '{1'b1, owner(lane), C'(lane)};
            observation_stim.descriptor_return[lane] = '{1'b1, owner(lane)};
            expected[CELL_RETURN_BASE+CELL_RETURN_LANE_W*lane+:CELL_RETURN_LANE_W] =
                {1'b1, owner_bits(lane), C'(lane)};
            expected[DESC_RETURN_LANE_W*lane+:DESC_RETURN_LANE_W] = {1'b1, owner_bits(lane)};
        end
        observation_stim.cleanup = '{1'b1, owner(PORTS), 1'b1, K'(1)};
        expected[CLEANUP_BASE+:CLEANUP_W] = {1'b1, owner_bits(PORTS), 1'b1, K'(1)};
        for (int lane = 0; lane < PORTS; lane++) begin
            new_owner = '{'{EPOCH, P'(lane), 64'(48+lane)}, Q'(4*lane), D'(PORTS+1+lane), 16'h3355};
            observation_stim.admission[lane] = '{1'b1, new_owner.frame,
                '{16'd64, 8'(lane), 8'd0, 16'h3355, 2'b00}, GRANT, COMMITTED,
                1'b1, new_owner.qid, K'(1), new_owner.desc};
            expected[ADMISSION_BASE+ADMISSION_LANE_W*lane+:ADMISSION_LANE_W] =
                {1'b1, EPOCH, P'(lane), 64'(48+lane), 16'd64, 8'(lane), 8'd0, 16'h3355, 2'b00,
                 2'd0, 3'd0, 1'b1, Q'(4*lane), K'(1), D'(PORTS+1+lane)};
        end
        new_owner = '{'{EPOCH, P'(0), 64'd64}, Q'(0), D'(2*PORTS+1), 16'h7788};
        observation_stim.cell_write = '{1'b1, new_owner, K'(0), C'(PORTS+1), 1'b1};
        expected[WRITE_EVENT_BASE+:WRITE_EVENT_W] =
            {1'b1, EPOCH, P'(0), 64'd64, Q'(0), D'(2*PORTS+1), 16'h7788, K'(0), C'(PORTS+1), 1'b1};
        #1;
        check(observation == expected, "allocation-return-overlap");
        mark("allocation-return-overlap");
    endtask

    task automatic check_batch();
        observation_stim = '0;
        #1;
        check(observation == '0, "absent-batch");
        check_return_lanes();
        check_event_lanes();
        check_admissions();
        check_correlation();
        check_allocation_return_overlap();
        mark("batch-and-correlation");
    endtask
