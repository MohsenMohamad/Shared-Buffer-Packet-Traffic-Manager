// Widths are literal interface expectations for two simultaneous profiles.
module tm_multi_pair (
    input logic [495:0] primary_ingress,
    input logic [247:0] small_ingress,
    output logic [459:0] primary_egress,
    output logic [225:0] small_egress,
    input logic [693:0] primary_response,
    input logic [673:0] small_response
);
    tm_multi_ports #(.PROFILE(0), .MEM_RD_LATENCY(2)) primary_ports(
        .ingress(primary_ingress), .egress(primary_egress), .cell_response(primary_response)
    );
    tm_multi_ports #(.PROFILE(1), .MEM_RD_LATENCY(1)) small_ports(
        .ingress(small_ingress), .egress(small_egress), .cell_response(small_response)
    );
endmodule
