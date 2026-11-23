    class pool_coverage;
        int hits[bin_t];
        int active_edges, grants, writes, retirements, completions;

        covergroup edge_bins with function sample(bin_t kind);
            observed: coverpoint kind;
        endgroup

        function new();
            edge_bins = new;
        endfunction

        function void hit(bin_t kind);
            if (!hits.exists(kind)) hits[kind] = 0;
            ++hits[kind];
            edge_bins.sample(kind);
        endfunction

        function int observed(bin_t kind);
            return hits.exists(kind) ? hits[kind] : 0;
        endfunction

        function void need(bin_t kind);
            require(observed(kind) != 0, {"missing coverage ", kind.name()});
        endfunction

        function void observe(pool_edge_t tr);
            int committed = $countones(tr.pins.commit);
            int tx = $countones(tr.pins.tx_present);
            int finished = $countones(tr.pins.tx_present & tr.pins.tx_final);
            bit completed_cleanup = tr.pins.cleanup_present && tr.pins.cleanup_done;
            int returned = tx + int'(tr.pins.cleanup_present && tr.pins.cleanup_has_cell);
            bit denied = 0;
            bit absent = 0;
            if (tr.pre.counts.d == 0 && finished != 0 && committed == 0) hit(D0_RETURN);
            if (tr.pre.counts.d == 1 && finished != 0 && committed == 1) hit(D1_RETURN);
            if (tr.pre.counts.d == 2 && finished != 0 && committed == 2) hit(D2_RETURN);
            if (tr.pre.counts.u == 0 && (tx != 0 || completed_cleanup)) hit(U0_RETURN);
            if (tr.pre.counts.f == 1 && tr.pre.counts.r == 1 && tr.pre.write_accept && tx != 0)
                hit(F1_EXCHANGE);
            if (committed == PORTS && tr.pre.write_accept && tx == PORTS) hit(ALL_GRANTS);
            if (returned == PORTS + 1 && finished == PORTS && completed_cleanup) hit(ALL_RETURNS);
            if (tx == 1 && tr.pins.tx_present[PORTS - 1]) hit(HIGH_TX);
            if (tx != 0 && tx < PORTS) hit(SPARSE_TX);
            if (tx + int'(tr.pins.cleanup_present) > 1) hit(PARALLEL_RETURNS);
            if (committed != 0 && (tx != 0 || tr.pins.cleanup_present)) hit(GRANT_RETURN);
            if (tr.pins.cleanup_present && !tr.pins.cleanup_done) hit(PARTIAL_CLEANUP);
            if (completed_cleanup && !tr.pins.cleanup_has_cell) hit(ZERO_CLEANUP);
            for (int lane = 0; lane < PORTS; ++lane) begin
                if (tr.pins.commit[lane]) begin
                    if (denied) hit(DENIED_HOLE);
                    if (absent) hit(ABSENT_HOLE);
                end else if (tr.intent.requests[lane].present) denied = 1;
                else absent = 1;
            end
            if (committed != 0 || tr.pre.write_accept || tx != 0 || tr.pins.cleanup_present)
                ++active_edges;
            if (tr.pre.write_accept) ++writes;
            if (completed_cleanup) ++completions;
            grants += committed;
            retirements += tx;
        endfunction

        function void summary(int edge_index);
            $display("TOTAL edge=%0d active=%0d grants=%0d write=%0d tx=%0d cleanup=%0d",
                     edge_index, active_edges, grants, writes, retirements, completions);
            for (bin_t kind = kind.first(); ; kind = kind.next()) begin
                $display("COVERAGE %s %0d", kind.name(), observed(kind));
                if (kind == kind.last()) break;
            end
        endfunction
    endclass
