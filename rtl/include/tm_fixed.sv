// Fixed wire layouts and encodings shared by RTL and independent monitors.
package tm_fixed;
    typedef enum logic [3:0] {COMMITTED=0, BAD_QID=1, BAD_LENGTH=2,
        QUEUE_LIMIT=3, NO_DESCRIPTOR=4, NO_CELLS=5, FRAME_ERROR=6} status_code_t;
    typedef enum logic [2:0] {FREE=0, RX=1, QUEUED=2, TX=3, ABORT=4} owner_t;
    typedef enum logic [1:0] {IDLE=0, RECEIVE=1, DRAIN_REJECT=2, ABORT_DRAIN=3} rx_phase_t;
    typedef enum logic [1:0] {OKAY=0, SLVERR=2, DECERR=3} axil_resp_t;
    typedef struct packed {
        logic [23:0] reserved;
        logic [15:0] tag;
        logic [15:0] length;
        logic [7:0] qid;
    } input_user_t;
    typedef struct packed {
        logic [15:0] reserved;
        logic [7:0] source;
        logic [15:0] tag;
        logic [15:0] length;
        logic [7:0] qid;
    } output_user_t;
    typedef struct packed {
        logic valid;
        status_code_t code;
        logic [15:0] tag;
        logic [7:0] qid;
        logic [15:0] length;
    } status_t;
    typedef struct packed {
        logic snapshot;
        logic clear;
    } stats_command_t;
    typedef struct packed {
        logic awvalid;
        logic [31:0] awaddr;
        logic [2:0] awprot;
        logic wvalid;
        logic [31:0] wdata;
        logic [3:0] wstrb;
        logic bready;
        logic arvalid;
        logic [31:0] araddr;
        logic [2:0] arprot;
        logic rready;
    } axil_request_t;
    typedef struct packed {
        logic awready;
        logic wready;
        logic bvalid;
        axil_resp_t bresp;
        logic arready;
        logic rvalid;
        logic [31:0] rdata;
        axil_resp_t rresp;
    } axil_response_t;
    localparam integer STATUS_W=$bits(status_t);
endpackage
