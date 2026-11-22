    // Sample both native covergroups and mandatory-bin counts after a checked edge.
    class pool_coverage extends uvm_object;
        `uvm_object_utils(pool_coverage)
        covergroup descriptor_cross with function sample(int returns, int grants, int old_free, int source);
            cp_returns: coverpoint returns { bins count[] = {[0:N_TX+1]}; }
            cp_grants: coverpoint grants { bins count[] = {[0:N_RX]}; }
            cp_old_free: coverpoint old_free { bins bucket[] = {[0:4]}; }
            cp_source: coverpoint source { bins origin[] = {[0:3]}; }
            combinations: cross cp_returns, cp_grants, cp_old_free, cp_source;
        endgroup
        covergroup cell_cross with function sample(int returns, int writes, int old_free, int source);
            cp_returns: coverpoint returns { bins count[] = {[0:N_TX+1]}; }
            cp_writes: coverpoint writes { bins count[] = {[0:1]}; }
            cp_old_free: coverpoint old_free { bins bucket[] = {[0:4]}; }
            cp_source: coverpoint source { bins origin[] = {[0:3]}; }
            combinations: cross cp_returns, cp_writes, cp_old_free, cp_source;
        endgroup

        function new(string name = "pool_coverage");
            super.new(name);
            descriptor_cross = new;
            cell_cross = new;
        endfunction

        int hits[2][N_TX+2][N_RX+1][5][4];
        int random_hits[2][N_TX+2][N_RX+1][5][4];

        function void sample(int grants, int writes, int desc_returns, int cell_returns,
                             int desc_bucket, int cell_bucket, int desc_source, int cell_source,
                             bit random_case);
            descriptor_cross.sample(desc_returns, grants, desc_bucket, desc_source);
            cell_cross.sample(cell_returns, writes, cell_bucket, cell_source);
            ++hits[0][desc_returns][grants][desc_bucket][desc_source];
            ++hits[1][cell_returns][writes][cell_bucket][cell_source];
            if (random_case) begin
                ++random_hits[0][desc_returns][grants][desc_bucket][desc_source];
                ++random_hits[1][cell_returns][writes][cell_bucket][cell_source];
            end
        endfunction

        function string exclusion(int kind, int returns, int allocations, int bucket, int origin);
            int capacity = kind == 0 ? N_DESC : N_CELL;
            int low, high;
            int needed = allocations;
            case (bucket)
                0: begin low = 0; high = 0; end
                1: begin low = 1; high = 1; end
                2: begin low = 2; high = 4; end
                3: begin low = 5; high = capacity - 1; end
                4: begin low = capacity; high = capacity; end
                default: return "unknown occupancy bucket";
            endcase
            if ((returns == 0) != (origin == 0))
                return "only an empty mask has no source";
            if (origin == 1 && returns > N_TX)
                return "one return per TX lane";
            if (origin == 2 && returns != 1)
                return "one dedicated cleanup lane";
            if (origin == 3 && returns < 2)
                return "mixed source needs two distinct return lanes";
            if (kind == 0 && origin >= 2 && allocations == N_RX)
                return "the ingress completing cleanup is unavailable for a grant";
            if (kind == 1 && origin >= 2) begin
                ++needed;
                if (needed > high)
                    return "abort cleanup and the RX writer need distinct reserved free cells";
            end
            if (allocations > high)
                return "allocation cannot exceed pre-edge free ID count";
            if ((low > needed ? low : needed) + returns > capacity)
                return "returns must have distinct pre-edge owners";
            return "";
        endfunction

        function void check_and_report(int handle, bit require_all);
            for (int kind = 0; kind < 2; ++kind) begin
                int required_count = 0;
                int reached = 0;
                int random_reached = 0;
                string name = kind == 0 ? "descriptor" : "cell";
                for (int ret = 0; ret <= N_TX+1; ++ret)
                    for (int alloc = 0; alloc <= (kind == 0 ? N_RX : 1); ++alloc)
                        for (int bucket = 0; bucket < 5; ++bucket)
                            for (int origin = 0; origin < 4; ++origin) begin
                                string reason = exclusion(kind, ret, alloc, bucket, origin);
                                int count = hits[kind][ret][alloc][bucket][origin];
                                int random_count = random_hits[kind][ret][alloc][bucket][origin];
                                $fdisplay(handle, "%s %0d %0d %0d %0d %0d %0d %s",
                                          name, ret, alloc, bucket, origin, count, random_count, reason);
                                if (reason == "") begin
                                    ++required_count;
                                    reached += int'(count > 0);
                                    random_reached += int'(random_count > 0);
                                end else if (count != 0) begin
                                    `uvm_fatal("EXCLUDED_BIN",
                                        $sformatf("%s %0d %0d %0d %0d: %s", name, ret, alloc, bucket, origin, reason))
                                end
                            end
                if (require_all && required_count != (kind == 0 ?
                        (N_RX == 4 ? 125 : 51) : (N_RX == 4 ? 62 : 38)))
                    `uvm_fatal("COVERAGE_PLAN", {"Unexpected required bin count for ", name})
                if (require_all && reached != required_count)
                    `uvm_fatal("REQUIRED_BINS",
                        $sformatf("%s reached %0d/%0d", name, reached, required_count))
                $display("POOL_COVERAGE %s %0d/%0d random=%0d", name, reached, required_count, random_reached);
            end
        endfunction
    endclass

    function automatic int occupancy_bucket(int count, int capacity);
        if (count < 2)
            return count;
        if (count <= 4)
            return 2;
        return count == capacity ? 4 : 3;
    endfunction

    function automatic int return_source(bit [N_TX:0] mask);
        if (mask == 0)
            return 0;
        if (!mask[N_TX])
            return 1;
        return mask[N_TX-1:0] == 0 ? 2 : 3;
    endfunction
