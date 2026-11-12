// Include after the shared production type declarations in a monitor scope.
// This observation record is never registered for synthesis.
// Monitors fill samples from signal handshakes, never from sequence objects.
typedef struct packed {logic valid; logic ready; beat_t beat;} stream_sample_t;
typedef struct packed {logic [31:0] epoch; logic [63:0] cycle;
    logic reset_asserted;
    logic [N_RX*$bits(stream_sample_t)-1:0] captures;
    stream_sample_t output_sample;
    axil_request_t bus_req; axil_response_t bus_rsp;
    logic [N_RX*$bits(status_t)-1:0] statuses;
    trace_t policy;} monitor_batch_t;
// A coordinator waits for one sample (including idle) from each monitor for
// (epoch, cycle), seals the batch, evaluates pre-state, then applies deltas once.
// Packet keys are (epoch, source, frame ordinal); tag is never an identity.
