// Evidence only: this subscriber sees sealed monitor batches and has no model
// or generator handles. Sequence records never become checker expectations.
class tm_handshake_recorder extends uvm_subscriber #(tm_sample);
    `uvm_component_utils(tm_handshake_recorder)
    int record_file;
    function new(string name, uvm_component parent);
        super.new(name, parent);
        record_file = $fopen("handshakes.jsonl", "w");
        if(record_file == 0) `uvm_fatal("HANDSHAKE_RECORD", "cannot open handshake record")
    endfunction
    function void record_beat(string kind, int source, stream_sample_t sample, monitor_batch_t batch);
        if(sample.valid && sample.ready)
            $fdisplay(record_file, "{\"kind\":\"%s\",\"epoch\":%0d,\"cycle\":%0d,\"source\":%0d,\"data\":\"%h\",\"keep\":%0d,\"last\":%0d,\"user\":\"%h\"}",
                kind, batch.epoch, batch.cycle, source, sample.beat.data, sample.beat.keep, sample.beat.last, sample.beat.user);
    endfunction
    function void write(tm_sample sample);
        monitor_batch_t batch = sample.batch;
        stream_sample_t capture;
        status_t status;
        if(batch.reset_asserted) return;
        for(int source=0; source<N_RX; source++) begin
            capture = stream_sample_t'(batch.captures[source*(BEAT_W+2)+:BEAT_W+2]);
            record_beat("capture", source, capture, batch);
            status = status_t'(batch.statuses[source*STATUS_W+:STATUS_W]);
            if(status.valid)
                $fdisplay(record_file, "{\"kind\":\"status\",\"epoch\":%0d,\"cycle\":%0d,\"source\":%0d,\"code\":%0d,\"qid\":%0d,\"length\":%0d,\"tag\":%0d}",
                    batch.epoch, batch.cycle, source, status.code, status.qid, status.length, status.tag);
        end
        record_beat("output", int'(batch.output_sample.beat.user[47:40]), batch.output_sample, batch);
        $fflush(record_file);
    endfunction
    function void final_phase(uvm_phase phase);
        $fclose(record_file);
    endfunction
endclass
